//! context contains compiled bytecode information

const std = @import("std");
const object = @import("object.zig");

const Object = object.Object;

pub const Context = struct {
    allocator: std.mem.Allocator,
    bytecode: std.ArrayList(u8),
    constants: std.ArrayList(*Object),
    lines: std.ArrayList(usize),
};
