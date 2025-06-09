//! vm is the bytecode virtual machine that processes the bytecode instructions.

const std = @import("std");
const builtin = @import("builtin");
const expect = std.testing.expect;
const gc_file = @import("gc_allocator.zig");
const disassembler = @import("disassembler.zig");

const value_file = @import("value.zig");
const compiled_function = @import("compiled_function.zig");
const compiler_file = @import("compiler.zig");
const opcode_file = @import("opcodes.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
var BUF_WRITER = std.io.bufferedWriter(std.io.getStdOut().writer());
const WRITER = BUF_WRITER.writer();
const Compiler = compiler_file.Compiler;
const CompiledFunction = compiled_function.CompiledFunction;
const GarbageCollector = gc_file.GcAllocator;
const GcObject = gc_file.GcObject;
const Object = value_file.Object;
const Op = opcode_file.Op;
const String = value_file.String;
const Value = value_file.Value;

const STACK_MAX: usize = 256;

pub const InterpretResult = enum(u8) {
    Ok,
    CompileError,
    RuntimeError,
};

pub const VirtualMachine = struct {
    gc: *GarbageCollector,
    stack: [STACK_MAX]Value,
    stack_top: usize,
    ip: usize,
    compiled_function: ?*CompiledFunction,
    globals: *std.AutoHashMap(*GcObject(String), Value),

    const Self = @This();

    pub fn init(garbage_collector: *GarbageCollector, globals: *std.AutoHashMap(*GcObject(String), Value)) VirtualMachine {
        return VirtualMachine{
            .gc = garbage_collector,
            .stack = [_]Value{Value.Nil} ** STACK_MAX,
            .compiled_function = null,
            .ip = 0,
            .stack_top = 0,
            .globals = globals,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn interpret(self: *Self, source: []const u8, fun: *CompiledFunction) !InterpretResult {
        self.resetStack();
        var compiler = Compiler.init(self.gc, fun);

        if (!try compiler.compile(source)) {
            return .CompileError;
        }

        self.compiled_function = fun;
        return self.run();
    }

    pub fn run(self: *Self) !InterpretResult {
        if (self.compiled_function.?.bytecode.items.len == 0) {
            return .Ok;
        }
        while (true) {
            if (builtin.mode == .Debug) {
                try WRITER.print("          ", .{});

                var current: usize = 0;
                while (current < self.stack_top) {
                    try WRITER.print("[ ", .{});
                    try self.stack[current].printValue(WRITER);
                    try WRITER.print(" ]", .{});
                    current += 1; // This correctly advances by sizeof(Value)
                }
                try WRITER.print("\n", .{});

                _ = try disassembler.disassembleInstruction(
                    self.compiled_function.?,
                    self.ip,
                    WRITER,
                );
            }

            const instruction = self.readOp();

            switch (instruction) {
                .Add => {
                    const both_numbers = self.peek(0).isNumber() and self.peek(1).isNumber();
                    const both_strings = self.peek(0).isString() and self.peek(1).isString();
                    if (!both_numbers and !both_strings) {
                        self.runtimeError("Operands must be numbers or strings.", .{});
                        return .RuntimeError;
                    }
                    var b = self.pop();
                    var a = self.pop();
                    if (both_numbers) {
                        const result = a.asNumber() + b.asNumber();
                        self.push(Value{ .Number = result });
                    }
                    if (both_strings) {
                        var buf = std.ArrayList(u8).init(self.gc.backing_allocator);
                        defer buf.deinit();
                        try buf.appendSlice(a.asStringLiteral());
                        try buf.appendSlice(b.asStringLiteral());
                        const new_str = try buf.toOwnedSlice();
                        defer self.gc.backing_allocator.free(new_str);
                        const alloc_str = try self.gc.allocString(new_str);
                        self.push(Value{ .String = alloc_str });
                    }
                },
                .Constant => {
                    const value: Value = self.readConstant();
                    self.push(value);
                },
                .DefineGlobal => {
                    const name = self.readString();
                    try self.globals.put(name, self.peek(0));
                    _ = self.pop();
                },
                .Divide => {
                    if (!self.peek(0).isNumber() or !self.peek(1).isNumber()) {
                        self.runtimeError("Operands must be numbers.", .{});
                        return .RuntimeError;
                    }
                    var b = self.pop();
                    var a = self.pop();
                    const result = a.asNumber() / b.asNumber();
                    self.push(Value{ .Number = result });
                },
                .Equal => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(Value{ .Bool = a.equals(&b) });
                },
                .False => {
                    self.push(Value{ .Bool = false });
                },
                .GetGlobal => {
                    const str = self.readString();
                    const value = self.globals.get(str);
                    if (value == null) {
                        self.runtimeError("Undefined let binding '{s}'.", .{str.data.value});
                        return .RuntimeError;
                    }

                    self.push(value.?);
                },
                .Greater => {
                    if (!self.peek(0).isNumber() or !self.peek(1).isNumber()) {
                        self.runtimeError("Operands must be numbers.", .{});
                        return .RuntimeError;
                    }
                    var b = self.pop();
                    var a = self.pop();
                    const result = a.asNumber() > b.asNumber();
                    self.push(Value{ .Bool = result });
                },
                .GreaterEqual => {
                    if (!self.peek(0).isNumber() or !self.peek(1).isNumber()) {
                        self.runtimeError("Operands must be numbers.", .{});
                        return .RuntimeError;
                    }
                    var b = self.pop();
                    var a = self.pop();
                    const result = a.asNumber() >= b.asNumber();
                    self.push(Value{ .Bool = result });
                },
                .Less => {
                    if (!self.peek(0).isNumber() or !self.peek(1).isNumber()) {
                        self.runtimeError("Operands must be numbers.", .{});
                        return .RuntimeError;
                    }
                    var b = self.pop();
                    var a = self.pop();
                    const result = a.asNumber() < b.asNumber();
                    self.push(Value{ .Bool = result });
                },
                .LessEqual => {
                    if (!self.peek(0).isNumber() or !self.peek(1).isNumber()) {
                        self.runtimeError("Operands must be numbers.", .{});
                        return .RuntimeError;
                    }
                    var b = self.pop();
                    var a = self.pop();
                    const result = a.asNumber() <= b.asNumber();
                    self.push(Value{ .Bool = result });
                },
                .Multiply => {
                    if (!self.peek(0).isNumber() or !self.peek(1).isNumber()) {
                        self.runtimeError("Operands must be numbers.", .{});
                        return .RuntimeError;
                    }
                    var b = self.pop();
                    var a = self.pop();
                    const result = a.asNumber() * b.asNumber();
                    self.push(Value{ .Number = result });
                },
                .Negate => {
                    if (!self.peek(0).isNumber()) {
                        self.runtimeError("Operand must be a number.", .{});
                        return .RuntimeError;
                    }
                    var popped = self.pop();
                    const negated = popped.negate();
                    self.push(Value{ .Number = negated });
                },
                .Nil => {
                    self.push(Value.Nil);
                },
                .Not => {
                    const to_push = self.pop().isFalsey();
                    self.push(Value{ .Bool = to_push });
                },
                .NotEqual => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(Value{ .Bool = !a.equals(&b) });
                },
                .Pop => {
                    _ = self.pop();
                },
                .Print => {
                    try self.pop().printValue(WRITER);
                    try WRITER.print("\n", .{});
                    try BUF_WRITER.flush();
                },
                .Return => {
                    return .Ok;
                },
                .SetGlobal => {
                    const name = self.readString();
                    const entry = self.globals.getEntry(name);
                    if (entry == null) {
                        self.runtimeError("Undefined let binding '{s}'.", .{name.data.value});
                        return .RuntimeError;
                    }

                    entry.?.value_ptr.* = self.peek(0);
                },
                .Subtract => {
                    if (!self.peek(0).isNumber() or !self.peek(1).isNumber()) {
                        self.runtimeError("Operands must be numbers.", .{});
                        return .RuntimeError;
                    }
                    var b = self.pop();
                    var a = self.pop();
                    const result = a.asNumber() - b.asNumber();
                    self.push(Value{ .Number = result });
                },
                .True => {
                    self.push(Value{ .Bool = true });
                },
            }
        }
    }

    inline fn peek(self: *Self, distance: usize) Value {
        const idx = self.stack_top - distance - 1;
        return self.stack[idx];
    }

    inline fn runtimeError(self: *Self, comptime message: []const u8, args: anytype) void {
        var buf_writer = std.io.bufferedWriter(std.io.getStdErr().writer());
        var writer = buf_writer.writer();
        defer buf_writer.flush() catch {};

        writer.print(message, args) catch {};
        writer.print("\n", .{}) catch {};
        const instruction = self.ip - 1;
        const line = self.compiled_function.?.lines.items[instruction];
        writer.print("[line {d}] in script\n", .{line}) catch {};
        self.resetStack();
    }

    inline fn resetStack(self: *Self) void {
        self.stack_top = 0;
        self.stack = [_]Value{Value.Nil} ** STACK_MAX;
        self.ip = 0;
    }

    inline fn readByte(self: *Self) u8 {
        const byte = self.compiled_function.?.bytecode.items[self.ip];
        self.ip += 1;
        return byte;
    }

    inline fn readShort(self: *Self) u16 {
        const high_byte = self.readByte();
        const low_byte = self.readByte();
        const short = @as(u16, high_byte) << 8 | @as(u16, low_byte);
        return short;
    }

    inline fn readOp(self: *Self) Op {
        const byte = self.readByte();
        return @enumFromInt(byte);
    }

    inline fn readConstant(self: *Self) Value {
        const idx = self.readShort();
        return self.compiled_function.?.constants.items[idx];
    }

    inline fn readString(self: *Self) *GcObject(String) {
        return self.readConstant().asString();
    }

    pub fn traceRoots(self: *Self) void {
        var slot: usize = 0;
        while (slot < self.stack_top) {
            const item = self.stack[slot];
            switch (item) {
                .String => |s| {
                    self.gc.markObject(s);
                },
                else => {},
            }
            slot += @sizeOf(Value);
        }

        var iterator = self.globals.valueIterator();
        while (iterator.next()) |v| {
            switch (v.*) {
                .String => |s| {
                    self.gc.markObject(s);
                },
                else => {},
            }
        }

        if (self.compiled_function) |fun| {
            for (fun.constants.items) |value| {
                switch (value) {
                    .String => |s| {
                        self.gc.markObject(s);
                    },
                    else => {},
                }
            }
        }
    }

    pub inline fn push(self: *Self, value: Value) void {
        self.stack[self.stack_top] = value;
        self.stack_top += 1;
    }

    inline fn pop(self: *Self) Value {
        self.stack_top -= 1;
        return self.stack[self.stack_top];
    }
};
