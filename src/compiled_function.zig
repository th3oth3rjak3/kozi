//! compiled_function contains compiled bytecode information

const std = @import("std");
const value_file = @import("value.zig");
const garbage_collector = @import("garbage_collector.zig");

const Object = value_file.Object;
const Value = value_file.Value;
const GarbageCollector = garbage_collector.GarbageCollector;

pub const CompiledFunction = struct {
    gc: *GarbageCollector,
    bytecode: std.ArrayList(u8),
    constants: std.ArrayList(Value),
    lines: std.ArrayList(usize),

    const Self = @This();

    pub fn init(gc: *GarbageCollector) CompiledFunction {
        return CompiledFunction{
            .gc = gc,
            .bytecode = std.ArrayList(u8).init(gc.backing_allocator),
            .constants = std.ArrayList(Value).init(gc.backing_allocator),
            .lines = std.ArrayList(usize).init(gc.backing_allocator),
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
