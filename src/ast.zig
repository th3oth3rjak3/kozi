//! ast contains definitions for the Abstract Syntax Tree

const std = @import("std");
const t = @import("token.zig");

pub const Program = struct {
    statements: []Statement,

    pub fn init(allocator: *std.mem.Allocator, capacity: usize) !Program {
        return Program{
            .statements = try allocator.alloc(Statement, capacity),
        };
    }

    pub fn deinit(self: *Program, allocator: *std.mem.Allocator) void {
        for (self.statements) |*stmt| {
            stmt.deinit(allocator);
        }
        allocator.free(self.statements);
    }
};

pub const Statement = union(enum) {
    Let: LetStatement,
    Return: ReturnStatement,
    Expression: ExpressionStatement,

    pub fn deinit(self: *Statement, allocator: *std.mem.Allocator) void {
        switch (self.*) {
            .Let => |*s| s.deinit(allocator),
            .Return => |*s| s.deinit(allocator),
            .Expression => |*s| s.deinit(allocator),
        }
    }
};

pub const Expression = union(enum) {
    Identifier: Identifier,
    NumberLiteral: NumberLiteral,
    BooleanLiteral: BooleanLiteral,
    Prefix: PrefixExpression,
    Infix: InfixExpression,
    If: IfExpression,
    Function: FunctionLiteral,
    Call: CallExpression,

    pub fn deinit(self: *Expression, allocator: *std.mem.Allocator) void {
        switch (self.*) {
            .Identifier => {},
            .IntegerLiteral => {},
            .BooleanLiteral => {},
            .Prefix => |*e| e.deinit(allocator),
            .Infix => |*e| e.deinit(allocator),
            .If => |*e| e.deinit(allocator),
            .Function => |*e| e.deinit(allocator),
            .Call => |*e| e.deinit(allocator),
        }
    }
};

// STATEMENTS

pub const LetStatement = struct {
    token: t.Token,
    name: Identifier,
    value: Expression,

    pub fn deinit(self: *LetStatement, allocator: *std.mem.Allocator) void {
        self.value.deinit(allocator);
    }
};

pub const ReturnStatement = struct {
    token: t.Token,
    return_value: Expression,

    pub fn deinit(self: *ReturnStatement, allocator: *std.mem.Allocator) void {
        self.return_value.deinit(allocator);
    }
};

pub const ExpressionStatement = struct {
    token: t.Token,
    expression: Expression,

    pub fn deinit(self: *ExpressionStatement, allocator: *std.mem.Allocator) void {
        self.expression.deinit(allocator);
    }
};

// EXPRESSIONS

pub const Identifier = struct {
    token: t.Token,
    value: []const u8,
};

pub const NumberLiteral = struct {
    token: t.Token,
    value: f64,
};

pub const BooleanLiteral = struct {
    token: t.Token,
    value: bool,
};

pub const PrefixExpression = struct {
    token: t.Token,
    operator: []const u8,
    right: *Expression,

    pub fn deinit(self: *PrefixExpression, allocator: *std.mem.Allocator) void {
        self.right.deinit(allocator);
        allocator.destroy(self.right);
    }
};

pub const InfixExpression = struct {
    token: t.Token,
    operator: []const u8,
    left: *Expression,
    right: *Expression,

    pub fn deinit(self: *InfixExpression, allocator: *std.mem.Allocator) void {
        self.left.deinit(allocator);
        self.right.deinit(allocator);
        allocator.destroy(self.left);
        allocator.destroy(self.right);
    }
};

pub const IfExpression = struct {
    token: t.Token,
    condition: *Expression,
    consequence: BlockStatement,
    alternative: ?BlockStatement,

    pub fn deinit(self: *IfExpression, allocator: *std.mem.Allocator) void {
        self.condition.deinit(allocator);
        allocator.destroy(self.condition);
        self.consequence.deinit(allocator);
        if (self.alternative) |*alt| alt.deinit(allocator);
    }
};

pub const FunctionLiteral = struct {
    token: t.Token,
    parameters: []Identifier,
    body: BlockStatement,

    pub fn deinit(self: *FunctionLiteral, allocator: *std.mem.Allocator) void {
        allocator.free(self.parameters);
        self.body.deinit(allocator);
    }
};

pub const CallExpression = struct {
    token: t.Token,
    function: *Expression,
    arguments: []Expression,

    pub fn deinit(self: *CallExpression, allocator: *std.mem.Allocator) void {
        self.function.deinit(allocator);
        allocator.destroy(self.function);
        for (self.arguments) |*arg| {
            arg.deinit(allocator);
        }
        allocator.free(self.arguments);
    }
};

pub const BlockStatement = struct {
    token: t.Token,
    statements: []Statement,

    pub fn deinit(self: *BlockStatement, allocator: *std.mem.Allocator) void {
        for (self.statements) |*stmt| {
            stmt.deinit(allocator);
        }
        allocator.free(self.statements);
    }
};
