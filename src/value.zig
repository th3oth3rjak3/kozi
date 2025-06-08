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
        return switch (self.*) {
            .Number => true,
            else => false,
        };
    }

    pub fn asNumber(self: *const Self) f64 {
        return switch (self.*) {
            .Number => |n| n,
            else => @panic("NOT A NUMBER"),
        };
    }

    pub fn isBool(self: *const Self) bool {
        return switch (self.*) {
            .Bool => true,
            else => false,
        };
    }

    pub fn asBool(self: *const Self) bool {
        return switch (self.*) {
            .Bool => |b| b,
            else => @panic("NOT A BOOLEAN"),
        };
    }

    pub fn isString(self: *const Self) bool {
        return switch (self.*) {
            .String => true,
            else => false,
        };
    }

    pub fn asString(self: *const Self) *GcObject(String) {
        return switch (self.*) {
            .String => |s| s,
            else => @panic("NOT A STRING"),
        };
    }

    pub fn asStringLiteral(self: *const Self) []const u8 {
        return switch (self.*) {
            .String => |s| s.data.value,
            else => @panic("NOT A STRING"),
        };
    }

    pub fn negate(self: *const Self) f64 {
        return self.asNumber() * -1;
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

    pub fn isFalsey(self: *const Self) bool {
        return switch (self.*) {
            .Bool => |b| !b,
            .Nil => true,
            else => false,
        };
    }

    pub fn equals(self: *const Self, rhs: *const Self) bool {
        if (std.meta.activeTag(self.*) != std.meta.activeTag(rhs.*)) {
            return false;
        }

        return switch (self.*) {
            .Number => |a| a == rhs.asNumber(),
            .Bool => |a| a == rhs.asBool(),
            .Nil => true,
            .String => |a| std.mem.eql(u8, a.data.value, rhs.String.data.value),
        };
    }
};

pub const String = struct {
    value: []const u8,
};
