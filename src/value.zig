//! value contains the runtime objects used in the language.

const std = @import("std");
const gc_allocator_file = @import("gc_allocator.zig");

const GcObject = gc_allocator_file.GcObject;
const AnyWriter = std.io.AnyWriter;

pub const Value = union(enum) {
    Bool: bool,
    Number: f64,
    Nil,
    String: *GcObject(String),

    const Self = @This();

    pub fn isNumber(self: *const Self) bool {
        return switch (self) {
            .Number => true,
            else => false,
        };
    }

    pub fn asNumber(self: *Self) f64 {
        return self.Number;
    }

    pub fn printValue(self: *const Self, writer: anytype) !void {
        switch (self.*) {
            .Bool => |b| {
                try std.fmt.format(writer, "{any}", .{b});
            },
            .Number => |n| {
                try std.fmt.format(writer, "{d}", .{n});
            },
            .Nil => {
                try std.fmt.format(writer, "nil", .{});
            },
            .String => |s| {
                try std.fmt.format(writer, "{s}", .{s.data.value});
            },
        }
    }
};

pub const String = struct {
    value: []const u8,
};
