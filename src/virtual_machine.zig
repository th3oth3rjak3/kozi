//! vm is the bytecode virtual machine that processes the bytecode instructions.

const std = @import("std");
const expect = std.testing.expect;

const value_file = @import("value.zig");
const garbage_collector = @import("garbage_collector.zig");
const compiled_function = @import("compiled_function.zig");

const Object = value_file.Object;
const Value = value_file.Value;
const CompiledFunction = compiled_function.CompiledFunction;
const GarbageCollector = garbage_collector.GarbageCollector;
const ArrayList = std.ArrayList;

pub const VirtualMachine = struct {
    gc: *GarbageCollector,
    stack: ArrayList(Value),
    compiled_function: ?*CompiledFunction,

    const Self = @This();

    pub fn init(gc: *GarbageCollector) VirtualMachine {
        return VirtualMachine{
            .gc = gc,
            .stack = ArrayList(Value).init(gc.backing_allocator),
            .compiled_function = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit();
    }

    pub fn push(self: *Self, value: Value) !void {
        try self.stack.append(value);
    }
};
