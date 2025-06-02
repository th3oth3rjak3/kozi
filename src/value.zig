//! value contains the runtime objects used in the language.

const garbage_collector = @import("garbage_collector.zig");
const std = @import("std");
const GarbageCollector = garbage_collector.GarbageCollector;

pub const ObjectKind = enum(u8) {
    String,
};

pub const Object = struct {
    marked: bool,
    kind: ObjectKind,
};

pub const String = struct {
    header: Object,
    data: []const u8,
};

pub const Value = union(enum) {
    Bool: bool,
    Number: f64,
    Nil,
    String: *String,
};
