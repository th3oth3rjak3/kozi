const std = @import("std");

/// charToOwnedString converts a character into an owned string.
pub fn charToOwnedString(allocator: *std.mem.Allocator, c: u8) ![]u8 {
    var buf: [1]u8 = .{c}; // temporary buffer with the char
    return try allocator.dupe(u8, &buf);
}
