const std = @import("std");
const builtin = @import("builtin");

const compiled_function_file = @import("compiled_function.zig");
const disassembler = @import("disassembler.zig");
const gc_file = @import("gc_allocator.zig");
const scanner_file = @import("scanner.zig");
const opcode_file = @import("opcodes.zig");
const value_file = @import("value.zig");

const Allocator = std.mem.Allocator;
const CompiledFunction = compiled_function_file.CompiledFunction;
const GarbageCollector = gc_file.GcAllocator;
const Op = opcode_file.Op;
const Token = scanner_file.Token;
const TokenType = scanner_file.TokenType;
const Scanner = scanner_file.Scanner;
const ScanError = scanner_file.ScanError;
const ScanResult = scanner_file.ScanResult;
const Value = value_file.Value;

var BUF_WRITER = std.io.bufferedWriter(std.io.getStdOut().writer());
const WRITER = BUF_WRITER.writer();
const UINT8_MAX: usize = std.math.maxInt(u8) + 1;

pub const Precedence = enum(u8) {
    None,
    Assignment,
    Or,
    And,
    Equality,
    Comparison,
    Term,
    Factor,
    Unary,
    Call,
    Primary,
};

const ParseFn = *const fn (compiler: *Compiler, can_assign: bool) anyerror!void;

const ParseRule = struct {
    prefix: ?ParseFn,
    infix: ?ParseFn,
    precedence: Precedence,
};

const RULES = std.EnumArray(TokenType, ParseRule).init(.{
    .LeftParen = .{ .prefix = Compiler.grouping, .infix = null, .precedence = .None },
    .RightParen = .{ .prefix = null, .infix = null, .precedence = .None },
    .LeftBrace = .{ .prefix = null, .infix = null, .precedence = .None },
    .RightBrace = .{ .prefix = null, .infix = null, .precedence = .None },
    .LeftBracket = .{ .prefix = null, .infix = null, .precedence = .None },
    .RightBracket = .{ .prefix = null, .infix = null, .precedence = .None },
    .Comma = .{ .prefix = null, .infix = null, .precedence = .None },
    .Period = .{ .prefix = null, .infix = null, .precedence = .None },
    .Semicolon = .{ .prefix = null, .infix = null, .precedence = .None },
    .Minus = .{ .prefix = Compiler.unary, .infix = Compiler.binary, .precedence = .Term },
    .MinusEqual = .{ .prefix = null, .infix = null, .precedence = .None },
    .Plus = .{ .prefix = null, .infix = Compiler.binary, .precedence = .Term },
    .PlusEqual = .{ .prefix = null, .infix = null, .precedence = .None },
    .Star = .{ .prefix = null, .infix = Compiler.binary, .precedence = .Factor },
    .StarEqual = .{ .prefix = null, .infix = null, .precedence = .None },
    .Slash = .{ .prefix = null, .infix = Compiler.binary, .precedence = .Factor },
    .SlashEqual = .{ .prefix = null, .infix = null, .precedence = .None },
    .Bang = .{ .prefix = Compiler.unary, .infix = null, .precedence = .None },
    .BangEqual = .{ .prefix = null, .infix = Compiler.binary, .precedence = .Equality },
    .Equal = .{ .prefix = null, .infix = null, .precedence = .None },
    .EqualEqual = .{ .prefix = null, .infix = Compiler.binary, .precedence = .Equality },
    .Greater = .{ .prefix = null, .infix = Compiler.binary, .precedence = .Comparison },
    .GreaterEqual = .{ .prefix = null, .infix = Compiler.binary, .precedence = .Comparison },
    .Less = .{ .prefix = null, .infix = Compiler.binary, .precedence = .Comparison },
    .LessEqual = .{ .prefix = null, .infix = Compiler.binary, .precedence = .Comparison },
    .Identifier = .{ .prefix = Compiler.variable, .infix = null, .precedence = .None },
    .String = .{ .prefix = Compiler.string, .infix = null, .precedence = .None },
    .Number = .{ .prefix = Compiler.number, .infix = null, .precedence = .None },
    .And = .{ .prefix = null, .infix = null, .precedence = .None },
    .Class = .{ .prefix = null, .infix = null, .precedence = .None },
    .Else = .{ .prefix = null, .infix = null, .precedence = .None },
    .False = .{ .prefix = Compiler.literal, .infix = null, .precedence = .None },
    .For = .{ .prefix = null, .infix = null, .precedence = .None },
    .Fun = .{ .prefix = null, .infix = null, .precedence = .None },
    .If = .{ .prefix = null, .infix = null, .precedence = .None },
    .Nil = .{ .prefix = Compiler.literal, .infix = null, .precedence = .None },
    .Or = .{ .prefix = null, .infix = null, .precedence = .None },
    .Print = .{ .prefix = null, .infix = null, .precedence = .None },
    .Return = .{ .prefix = null, .infix = null, .precedence = .None },
    .Super = .{ .prefix = null, .infix = null, .precedence = .None },
    .This = .{ .prefix = null, .infix = null, .precedence = .None },
    .True = .{ .prefix = Compiler.literal, .infix = null, .precedence = .None },
    .Let = .{ .prefix = null, .infix = null, .precedence = .None },
    .While = .{ .prefix = null, .infix = null, .precedence = .None },
    .EOF = .{ .prefix = null, .infix = null, .precedence = .None },
});

pub const Local = struct {
    name: Token,
    depth: isize,
};

/// Compiler converts source code into runnable bytecode.
pub const Compiler = struct {
    gc: *GarbageCollector,
    scanner: Scanner,
    current: Token,
    previous: Token,
    had_error: bool,
    panic_mode: bool,
    compiled_function: *CompiledFunction,
    scope_depth: isize,
    locals: [UINT8_MAX]Local,
    local_count: usize,

    const Self = @This();

    /// After compilation of source code, the scope that calls "compile" will
    /// own the memory for the CompiledFunction and must deinit the object when
    /// it goes out of scope.
    pub fn init(gc: *GarbageCollector, compiled_function: *CompiledFunction) Compiler {
        return Compiler{
            .gc = gc,
            .scanner = undefined,
            .current = undefined,
            .previous = undefined,
            .had_error = false,
            .panic_mode = false,
            .compiled_function = compiled_function,
            .locals = [_]Local{Local{ .name = undefined, .depth = undefined }} ** UINT8_MAX,
            .local_count = 0,
            .scope_depth = 0,
        };
    }

    pub fn compile(self: *Self, source: []const u8) !bool {
        self.scanner = Scanner.new(source);
        self.advance();

        while (!self.match(.EOF)) {
            try self.declaration();
        }

        return self.end();
    }

    pub fn end(self: *Self) bool {
        self.emitReturn() catch {};
        if (self.had_error) {
            return false;
        }

        if (builtin.mode == .Debug) {
            disassembler.disassembleCompiledFunction(self.compiled_function, "code") catch {};
        }
        return true;
    }

    pub fn advance(self: *Self) void {
        self.previous = self.current;
        const result = self.scanner.scanToken();

        if (result.isOk()) {
            self.current = result.unwrap();
        } else {
            self.handleError(result.unwrapErr());
        }
    }

    pub fn match(self: *Self, token_type: TokenType) bool {
        if (!self.check(token_type)) {
            return false;
        }

        self.advance();
        return true;
    }

    pub fn check(self: *Self, token_type: TokenType) bool {
        return self.current.token_type == token_type;
    }

    fn handleError(self: *Self, err: ScanError) void {
        if (self.panic_mode) {
            return;
        }
        self.had_error = true;
        self.panic_mode = true;

        err.format("", .{}, WRITER) catch {};
        WRITER.print("\n", .{}) catch {};
        BUF_WRITER.flush() catch {};
    }

    fn handleCurrentError(self: *Self, message: []const u8) void {
        if (self.panic_mode) {
            return;
        }
        self.had_error = true;
        self.panic_mode = true;

        const err = ScanError{
            .column = self.current.column,
            .line = self.current.line,
            .kind = ScanError.ErrorKind.UnexpectedCharacter,
            .message = message,
            .codepoint = null,
        };

        err.format("", .{}, WRITER) catch {};
        WRITER.print("\n", .{}) catch {};
        BUF_WRITER.flush() catch {};
    }

    fn handlePreviousError(self: *Self, message: []const u8) void {
        if (self.panic_mode) {
            return;
        }
        self.had_error = true;
        self.panic_mode = true;

        const err = ScanError{
            .column = self.previous.column,
            .line = self.previous.line,
            .kind = ScanError.ErrorKind.UnexpectedCharacter,
            .message = message,
            .codepoint = null,
        };

        err.format("", std.fmt.FormatOptions{}, WRITER) catch {};
        WRITER.print("\n", .{}) catch {};
        BUF_WRITER.flush() catch {};
    }

    fn consume(self: *Self, token_type: TokenType, message: []const u8) !void {
        if (self.current.token_type == token_type) {
            self.advance();
            return;
        }

        self.handleCurrentError(message);
    }

    pub fn emitByte(self: *Self, byte: u8) !void {
        return self.compiled_function.*.writeByte(byte, self.previous.line);
    }

    fn emitShort(self: *Self, short: u16) !void {
        return self.compiled_function.writeShort(short, self.previous.line);
    }

    fn emitJump(self: *Self, op: Op) !usize {
        try self.emitOp(op);
        try self.emitByte(0xFF);
        try self.emitByte(0xFF);
        return self.compiled_function.bytecode.items.len - 2;
    }

    fn patchJump(self: *Self, offset: usize) !void {
        const jump = self.compiled_function.bytecode.items.len - offset - 2;

        if (jump > std.math.maxInt(u16)) {
            self.handlePreviousError("Too much code to jump over.");
        }

        self.compiled_function.bytecode.items[offset] = @intCast((jump >> 8) & 0xFF);
        self.compiled_function.bytecode.items[offset + 1] = @intCast(jump & 0xFF);
    }

    fn emitOp(self: *Self, op: Op) !void {
        return self.compiled_function.writeOp(op, self.previous.line);
    }

    fn emitReturn(self: *Self) !void {
        return self.emitOp(Op.Return);
    }

    fn emitConstant(self: *Self, value: Value) !void {
        try self.emitOp(Op.Constant);
        const idx = try self.makeConstant(value);
        try self.emitShort(idx);
    }

    fn makeConstant(self: *Self, value: Value) !u16 {
        if (self.compiled_function.*.constants.items.len > std.math.maxInt(u16)) {
            self.handlePreviousError("Too many constants.");
            return 0;
        }

        const idx = try self.compiled_function.addConstant(value);
        return idx;
    }

    pub fn parsePrecedence(self: *Self, precedence: Precedence) !void {
        self.advance();
        const prefix_rule = RULES.get(self.previous.token_type).prefix;
        if (prefix_rule == null) {
            self.handlePreviousError("Expect expression.");
            return;
        }

        const can_assign = @intFromEnum(precedence) <= @intFromEnum(Precedence.Assignment);
        if (prefix_rule) |pfx| {
            try pfx(self, can_assign);
        }

        while (@intFromEnum(precedence) <= @intFromEnum(RULES.get(self.current.token_type).precedence)) {
            self.advance();
            const infix_rule = RULES.get(self.previous.token_type).infix;
            if (infix_rule) |ifx| {
                try ifx(self, can_assign);
            }
        }
    }

    pub fn synchronize(self: *Self) !void {
        self.panic_mode = false;

        while (self.current.token_type != .EOF) {
            if (self.previous.token_type == .Semicolon) {
                return;
            }

            switch (self.current.token_type) {
                .Class => return,
                .Fun => return,
                .Let => return,
                .For => return,
                .If => return,
                .While => return,
                .Print => return,
                .Return => return,
                else => {},
            }

            self.advance();
        }
    }

    pub fn expression(self: *Self) !void {
        return self.parsePrecedence(Precedence.Assignment);
    }

    pub fn declaration(self: *Self) !void {
        if (self.match(.Let)) {
            try self.varDeclaration();
        } else {
            try self.statement();
        }

        if (self.panic_mode) {
            try self.synchronize();
        }
    }

    pub fn statement(self: *Self) anyerror!void {
        if (self.match(.Print)) {
            try self.printStatement();
        } else if (self.match(.LeftBrace)) {
            self.beginScope();
            try self.block();
            try self.endScope();
        } else if (self.match(.If)) {
            try self.ifStatement();
        } else {
            try self.expressionStatement();
        }
    }

    pub fn beginScope(self: *Self) void {
        self.scope_depth += 1;
    }

    pub fn endScope(self: *Self) !void {
        self.scope_depth -= 1;

        while (self.local_count > 0 and self.locals[self.local_count - 1].depth > self.scope_depth) {
            try self.emitOp(.Pop);
            self.local_count -= 1;
        }
    }

    pub fn block(self: *Self) anyerror!void {
        while (!self.check(.RightBrace) and !self.check(.EOF)) {
            try self.declaration();
        }

        try self.consume(.RightBrace, "Expect '}' after block.");
    }

    pub fn printStatement(self: *Self) !void {
        try self.expression();
        try self.consume(.Semicolon, "Expect ';' after value.");
        try self.emitOp(.Print);
    }

    pub fn expressionStatement(self: *Self) !void {
        try self.expression();
        try self.consume(.Semicolon, "Expect ';' after expression.");
        try self.emitOp(.Pop);
    }

    pub fn ifStatement(self: *Self) !void {
        try self.consume(.LeftParen, "Expect '(' after 'if'.");
        try self.expression();
        try self.consume(.RightParen, "Expect ')' after condition.");

        const thenJump = try self.emitJump(.JumpFalse);
        try self.emitOp(.Pop);
        try self.statement();

        const elseJump = try self.emitJump(.Jump);

        try self.patchJump(thenJump);
        try self.emitOp(.Pop);

        if (self.match(.Else)) {
            try self.statement();
        }

        try self.patchJump(elseJump);
    }

    pub fn varDeclaration(self: *Self) !void {
        const global = try self.parseVariable("Expect let binding name.");

        if (self.match(.Equal)) {
            try self.expression();
        } else {
            try self.emitOp(.Nil);
        }

        try self.consume(.Semicolon, "Expect ';' after let binding declaration.");
        try self.defineVariable(global);
    }

    pub fn parseVariable(self: *Self, message: []const u8) !u16 {
        try self.consume(.Identifier, message);

        try self.declareVariable();
        if (self.scope_depth > 0) {
            return 0;
        }

        return self.identifierConstant(&self.previous);
    }

    pub fn identifierConstant(self: *Self, token: *Token) !u16 {
        const owned = try self.gc.allocString(token.lexeme);
        return self.makeConstant(Value{ .String = owned });
    }

    pub fn defineVariable(self: *Self, idx: u16) !void {
        if (self.scope_depth > 0) {
            self.markInitialized();
            return;
        }

        try self.emitOp(.DefineGlobal);
        try self.emitShort(idx);
    }

    pub fn markInitialized(self: *Self) void {
        self.locals[self.local_count - 1].depth = self.scope_depth;
    }

    pub fn declareVariable(self: *Self) !void {
        if (self.scope_depth == 0) {
            return;
        }

        const name = self.previous;

        var i = self.local_count - 1;
        while (i >= 0) {
            const local = self.locals[i];
            if (local.depth != -1 and local.depth < self.scope_depth) {
                break;
            }

            if (self.identifiersEqual(name, local.name)) {
                self.handlePreviousError("Already a let binding with this name in this scope.");
            }

            i -= 1;
        }

        try self.addLocal(name);
    }

    fn identifiersEqual(self: *Self, a: Token, b: Token) bool {
        _ = self;
        return std.mem.eql(u8, a.lexeme, b.lexeme);
    }

    pub fn addLocal(self: *Self, token: Token) !void {
        if (self.local_count >= UINT8_MAX) {
            self.handlePreviousError("Too many local let bindings in function.");
            return;
        }
        const local = Local{ .name = token, .depth = -1 };
        self.locals[self.local_count] = local;
        self.local_count += 1;
    }

    pub fn number(self: *Self, can_assign: bool) !void {
        _ = can_assign;
        const value = try std.fmt.parseFloat(f64, self.previous.lexeme);
        return self.emitConstant(Value{ .Number = value });
    }

    pub fn string(self: *Self, can_assign: bool) !void {
        _ = can_assign;
        const new_str = try self.gc.allocString(self.previous.lexeme);
        try self.emitConstant(Value{ .String = new_str });
    }

    pub fn variable(self: *Self, can_assign: bool) !void {
        try self.namedVariable(&self.previous, can_assign);
    }

    pub fn namedVariable(self: *Self, token: *Token, can_assign: bool) !void {
        var get_op: Op = undefined;
        var set_op: Op = undefined;

        var arg = self.resolveLocal(token);
        if (arg != -1) {
            get_op = .GetLocal;
            set_op = .SetLocal;
        } else {
            arg = @intCast(try self.identifierConstant(token));
            get_op = .GetGlobal;
            set_op = .SetGlobal;
        }

        // assignment case
        if (can_assign and self.match(.Equal)) {
            try self.expression();
            try self.emitOp(set_op);
            try self.emitShort(@intCast(arg));
        } else {
            try self.emitOp(get_op);
            try self.emitShort(@intCast(arg));
        }
    }

    pub fn resolveLocal(self: *Self, token: *Token) isize {
        var i = self.local_count - 1;
        while (i >= 0) {
            const local = self.locals[i];
            if (self.identifiersEqual(token.*, local.name)) {
                if (local.depth == -1) {
                    self.handlePreviousError("Can't read local let binding in its own initializer.");
                }
                return @intCast(i);
            }
            i -= 1;
        }
    }

    pub fn grouping(self: *Self, can_assign: bool) !void {
        _ = can_assign;
        try self.expression();
        try self.consume(TokenType.RightParen, "Expect ')' after expression.");
    }

    pub fn unary(self: *Self, can_assign: bool) !void {
        _ = can_assign;
        const op = self.previous.token_type;

        try self.parsePrecedence(Precedence.Unary);

        switch (op) {
            .Minus => {
                try self.emitOp(Op.Negate);
            },
            .Bang => {
                try self.emitOp(Op.Not);
            },
            else => {},
        }
    }

    pub fn binary(self: *Self, can_assign: bool) !void {
        _ = can_assign;
        const op = self.previous.token_type;
        const rule = RULES.get(op);
        const int_prec: u8 = @intFromEnum(rule.precedence) + 1;
        try self.parsePrecedence(@enumFromInt(int_prec));

        switch (op) {
            .Plus => {
                try self.emitOp(Op.Add);
            },
            .Minus => {
                try self.emitOp(Op.Subtract);
            },
            .Star => {
                try self.emitOp(Op.Multiply);
            },
            .Slash => {
                try self.emitOp(Op.Divide);
            },
            .BangEqual => {
                try self.emitOp(Op.NotEqual);
            },
            .EqualEqual => {
                try self.emitOp(Op.Equal);
            },
            .Greater => {
                try self.emitOp(Op.Greater);
            },
            .GreaterEqual => {
                try self.emitOp(Op.GreaterEqual);
            },
            .Less => {
                try self.emitOp(Op.Less);
            },
            .LessEqual => {
                try self.emitOp(Op.LessEqual);
            },
            else => {},
        }
    }

    pub fn literal(self: *Self, can_assign: bool) !void {
        _ = can_assign;
        switch (self.previous.token_type) {
            .False => try self.emitOp(.False),
            .True => try self.emitOp(.True),
            .Nil => try self.emitOp(.Nil),
            else => {},
        }
    }
};
