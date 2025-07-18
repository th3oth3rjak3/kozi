//! compiled_function contains compiled bytecode information

const std = @import("std");
const opcode_file = @import("opcodes.zig");
const value_file = @import("value.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Op = opcode_file.Op;
const Value = value_file.Value;

pub const CompiledFunction = struct {
    allocator: Allocator,
    bytecode: std.ArrayList(u8),
    constants: std.ArrayList(Value),
    lines: std.ArrayList(usize),

    const Self = @This();

    pub fn init(allocator: Allocator) CompiledFunction {
        return CompiledFunction{
            .allocator = allocator,
            .bytecode = std.ArrayList(u8).init(allocator),
            .constants = std.ArrayList(Value).init(allocator),
            .lines = std.ArrayList(usize).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.constants.clearAndFree();
        self.bytecode.clearAndFree();
        self.lines.clearAndFree();
        self.constants.deinit();
        self.bytecode.deinit();
        self.lines.deinit();
    }

    pub fn reset(self: *Self) void {
        self.bytecode.clearAndFree();
        self.bytecode.deinit();
        self.bytecode = std.ArrayList(u8).init(self.allocator);

        self.lines.clearAndFree();
        self.lines.deinit();
        self.lines = std.ArrayList(usize).init(self.allocator);
    }

    pub fn addConstant(self: *Self, value: Value) !u16 {
        for (self.constants.items, 0..) |existing_value, i| {
            if (existing_value.equals(&value)) {
                return @intCast(i);
            }
        }
        try self.constants.append(value);
        return @intCast(self.constants.items.len - 1);
    }

    pub fn writeByte(self: *Self, byte: u8, line: usize) !void {
        try self.bytecode.append(byte);
        try self.lines.append(line);
    }

    pub fn writeShort(self: *Self, short: u16, line: usize) !void {
        const high_byte: u8 = @intCast(short >> 8);
        const low_byte: u8 = @intCast(short & 0xFF);
        try self.writeByte(high_byte, line);
        try self.writeByte(low_byte, line);
    }

    pub fn writeOp(self: *Self, op: Op, line: usize) !void {
        try self.bytecode.append(@intFromEnum(op));
        try self.lines.append(line);
    }
};

test "We can create a new CompiledFunction" {
    var fun = CompiledFunction.init(std.testing.allocator);
    defer fun.deinit();

    try fun.bytecode.append(0);
    try std.testing.expectEqual(1, fun.bytecode.items.len);
}

test "CompiledFunction can write bytes" {
    var fun = CompiledFunction.init(std.testing.allocator);
    defer fun.deinit();

    try fun.writeByte(42, 1);
    try std.testing.expectEqual(42, fun.bytecode.items[0]);
    try std.testing.expectEqual(1, fun.lines.items[0]);
}

test "CompiledFunction can write Op's" {
    var fun = CompiledFunction.init(std.testing.allocator);
    defer fun.deinit();

    try fun.writeOp(Op.Pop, 2);
    try std.testing.expectEqual(@intFromEnum(Op.Pop), fun.bytecode.items[0]);
    try std.testing.expectEqual(2, fun.lines.items[0]);
}
