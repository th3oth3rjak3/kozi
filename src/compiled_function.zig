//! compiled_function contains compiled bytecode information

const std = @import("std");
const value_file = @import("value.zig");

const Object = value_file.Object;
const Value = value_file.Value;
const Allocator = std.mem.Allocator;

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
        self.lines.deinit();
        self.constants.deinit();
        self.bytecode.deinit();
    }

    pub fn write(self: *Self, byte: u8) void {
        _ = self;
        _ = byte;
        @panic("TODO: implement compiled function write method.");
    }
};
