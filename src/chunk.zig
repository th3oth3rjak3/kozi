const std = @import("std");
const opcode_file = @import("opcodes.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const testing = std.testing;

const Op = opcode_file.Op;

pub const Chunk = struct {
    allocator: Allocator,
    bytecode: ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: Allocator) Chunk {
        return .{
            .allocator = allocator,
            .bytecode = ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.bytecode.deinit();
    }

    pub fn write(self: *Self, byte: u8) !void {
        try self.bytecode.append(byte);
    }

    pub fn writeOp(self: *Self, op: Op) !void {
        try self.bytecode.append(@intFromEnum(op));
    }
};

test "We can create a new chunk" {
    var chunk = Chunk.init(testing.allocator);
    defer chunk.deinit();

    try chunk.bytecode.append(0);
    try testing.expectEqual(1, chunk.bytecode.items.len);
}

test "Chunk can write bytes" {
    var chunk = Chunk.init(testing.allocator);
    defer chunk.deinit();

    try chunk.write(42);
    try testing.expectEqual(42, chunk.bytecode.items[0]);
}

test "Chunk can write Op's" {
    var chunk = Chunk.init(testing.allocator);
    defer chunk.deinit();

    try chunk.writeOp(Op.Pop);
    try testing.expectEqual(@intFromEnum(Op.Pop), chunk.bytecode.items[0]);
}
