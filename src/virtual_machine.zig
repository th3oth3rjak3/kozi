//! vm is the bytecode virtual machine that processes the bytecode instructions.

const std = @import("std");
const expect = std.testing.expect;
const gc_file = @import("gc_allocator.zig");

const value_file = @import("value.zig");
const compiled_function = @import("compiled_function.zig");

const Object = value_file.Object;
const Value = value_file.Value;
const CompiledFunction = compiled_function.CompiledFunction;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const GarbageCollector = gc_file.GcAllocator;

pub const VirtualMachine = struct {
    gc: *GarbageCollector,
    stack: ArrayList(Value),
    compiled_function: ?*CompiledFunction,

    const Self = @This();

    pub fn init(garbage_collector: *GarbageCollector) VirtualMachine {
        return VirtualMachine{
            .gc = garbage_collector,
            .stack = ArrayList(Value).init(garbage_collector.allocator()),
            .compiled_function = null,
        };
    }

    pub fn deinit(self: *Self) void {
        while (self.stack.items.len > 0) {
            _ = self.stack.pop();
        }
        self.gc.collect();
        self.stack.deinit();
    }

    pub fn traceRoots(self: *Self) void {
        for (self.stack.items) |value| {
            switch (value) {
                .String => |s| {
                    self.gc.markObject(s);
                },
                else => {},
            }
        }

        // TODO: global scanning
    }

    pub fn push(self: *Self, value: Value) !void {
        try self.stack.append(value);
    }
};
