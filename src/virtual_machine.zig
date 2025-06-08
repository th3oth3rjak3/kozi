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
const Object = value_file.Object;
const Op = opcode_file.Op;
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

    const Self = @This();

    pub fn init(garbage_collector: *GarbageCollector) VirtualMachine {
        return VirtualMachine{
            .gc = garbage_collector,
            .stack = [_]Value{Value.Nil} ** STACK_MAX,
            .compiled_function = null,
            .ip = 0,
            .stack_top = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn interpret(self: *Self, source: []const u8, fun: *CompiledFunction) !InterpretResult {
        self.resetStack();
        var compiler = Compiler.init(fun);

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
                    var b = self.pop();
                    var a = self.pop();
                    const result = a.asNumber() + b.asNumber();
                    self.push(Value{ .Number = result });
                },
                .Constant => {
                    const value: Value = self.readConstant();
                    self.push(value);
                },
                .Divide => {
                    var b = self.pop();
                    var a = self.pop();
                    const result = a.asNumber() / b.asNumber();
                    self.push(Value{ .Number = result });
                },
                .Multiply => {
                    var b = self.pop();
                    var a = self.pop();
                    const result = a.asNumber() * b.asNumber();
                    self.push(Value{ .Number = result });
                },
                .Negate => {
                    var popped = self.pop();
                    const negated = popped.negate();
                    self.push(Value{ .Number = negated });
                },
                .Pop => {
                    _ = self.pop();
                },
                .Return => {
                    const value = self.pop();
                    try value.printValue(WRITER);
                    try WRITER.print("\n", .{});
                    BUF_WRITER.flush() catch {};
                    return .Ok;
                },
                .Subtract => {
                    var b = self.pop();
                    var a = self.pop();
                    const result = a.asNumber() - b.asNumber();
                    self.push(Value{ .Number = result });
                },
            }
        }
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

    pub fn traceRoots(self: *Self) void {
        std.io.getStdErr().writer().print("TRACING ROOTS!!\n", .{}) catch unreachable;
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

        // TODO: global scanning
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
