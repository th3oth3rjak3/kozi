//! opcodes.zig contains all the types related to reading and writing bytecode.

const std = @import("std");
const expect = std.testing.expect;

/// Op represents an operation to be performed by the virtual machine.
pub const Op = enum(u8) {
    /// Pop the topmost value from the stack.
    Pop,
    /// Return from a function.
    Return,

    const Self = @This();

    /// value gets the u8 representation of the enum.
    pub inline fn value(comptime self: Self) u8 {
        return @intFromEnum(self);
    }
};

test "Op.value() should return u8" {
    const ValueType = @TypeOf(Op.Return.value());
    try expect(ValueType == u8);
}
