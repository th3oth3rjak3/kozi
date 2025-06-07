//! value contains the runtime objects used in the language.

const std = @import("std");
const gc_allocator_file = @import("gc_allocator.zig");

const GcObject = gc_allocator_file.GcObject;

pub const Value = union(enum) {
    Bool: bool,
    Number: f64,
    Nil,
    String: *GcObject(String),
};

pub const String = struct {
    value: []const u8,
};
