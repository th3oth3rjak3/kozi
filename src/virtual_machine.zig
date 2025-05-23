//! vm is the bytecode virtual machine that processes the bytecode instructions.

const std = @import("std");
const expect = std.testing.expect;

const object = @import("object.zig");
const garbage_collector = @import("garbage_collector.zig");
const function_context = @import("context.zig");

const Tracer = garbage_collector.Tracer;
const Object = object.Object;
const Context = function_context.Context;
const GarbageCollector = garbage_collector.GarbageCollector;

pub const VirtualMachine = struct {
    gc: *GarbageCollector,
    context: ?*Context,
    globals: std.ArrayList(Object),
    stack: std.ArrayList(Object),

    const Self = @This();

    pub fn init(gc: *GarbageCollector) VirtualMachine {
        return VirtualMachine{
            .gc = gc,
            .context = null,
            .globals = std.ArrayList(Object).init(gc.allocator()),
            .stack = std.ArrayList(Object).init(gc.allocator()),
        };
    }

    pub fn deinit(self: *Self) void {
        self.globals.deinit();
        self.stack.deinit();
    }

    // pub fn traceRoots(self: *Self, tracer: *Tracer) anyerror!void {
    //     // mark globals
    //     for (self.globals.items) |*global| {
    //         try tracer.markValue(global);
    //     }
    //
    //     // Mark stack values
    //     for (self.stack.items) |*stack_value| {
    //         try tracer.markValue(stack_value);
    //     }
    //
    //     // Mark constants currently in use
    //     if (self.context) |ctx| {
    //         for (ctx.constants.items) |value| {
    //             try tracer.markValue(value);
    //         }
    //     }
    //
    //     // TODO: mark any other future VM roots.
    // }

    pub fn traceRoots(self: *Self, tracer: *Tracer) anyerror!void {
        std.debug.print("Tracing {} globals\n", .{self.globals.items.len});

        // mark globals
    for (self.globals.items, 0..) |*global, i| {
            std.debug.print("Marking global {}: {any}\n", .{i, global.*});
            try tracer.markValue(global);
        }

        std.debug.print("Tracing {} stack items\n", .{self.stack.items.len});

        // Mark stack values
    for (self.stack.items, 0..) |*stack_value, i| {
            std.debug.print("Marking stack {}: {any}\n", .{i, stack_value.*});
            try tracer.markValue(stack_value);
        }

        // Mark constants currently in use
    if (self.context) |ctx| {
            std.debug.print("Tracing {} constants\n", .{ctx.constants.items.len});
            for (ctx.constants.items, 0..) |value, i| {
                std.debug.print("Marking constant {}: {any}\n", .{i, value});
                try tracer.markValue(value);
            }
        }
    }
};
