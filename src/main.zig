//! The Kozi Programming Language
//! Author: Jake Hathaway <jake.d.hathaway@gmail.com>
//! May 21, 2025

const std = @import("std");
const builtin = @import("builtin");
const virtual_machine = @import("virtual_machine.zig");
const garbage_collector = @import("garbage_collector.zig");
const compiler_file = @import("compiler.zig");
const value = @import("value.zig");

const GarbageCollector = garbage_collector.GarbageCollector;
const VirtualMachine = virtual_machine.VirtualMachine;
const Compiler = compiler_file.Compiler;
const Tracer = garbage_collector.Tracer;
const Value = value.Value;

var debug_allocator = std.heap.DebugAllocator(.{}).init;

const Runtime = struct {
    vm: VirtualMachine,
    compiler: Compiler,

    const Self = @This();

    pub fn init(gc: *GarbageCollector) Runtime {
        const vm = VirtualMachine.init(gc);
        const compiler = Compiler.init();
        return .{
            .vm = vm,
            .compiler = compiler,
        };
    }

    pub fn deinit(self: *Self) void {
        self.vm.deinit();
        self.compiler.deinit();
    }
};

/// getAllocator checks the current environment and produces the
/// correct allocator for the program.
pub fn getAllocator() struct {
    allocator: std.mem.Allocator,
    is_debug: bool,
} {
    if (builtin.os.tag == .wasi)
        return .{ .allocator = std.heap.wasm_allocator, .is_debug = false };

    return switch (builtin.mode) {
        .Debug, .ReleaseSafe => .{
            .allocator = debug_allocator.allocator(),
            .is_debug = true,
        },
        .ReleaseFast, .ReleaseSmall => .{
            .allocator = std.heap.smp_allocator,
            .is_debug = false,
        },
    };
}

pub fn main() !void {
    // Setup allocator and check for leaks in debug mode.
    const mem = getAllocator();
    defer if (mem.is_debug) {
        const result = debug_allocator.deinit();
        if (result == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        } else {
            std.debug.print("No memory leaks detected.\n", .{});
        }
    };

    var gc = GarbageCollector.init(mem.allocator);
    defer gc.deinit();

    // Read args from the command line.
    const args = try std.process.argsAlloc(mem.allocator);
    defer std.process.argsFree(mem.allocator, args);

    // if we have args, run file
    if (args.len == 2) {
        try runFile(&gc, args[1]);
    } else if (args.len == 1) {
        try runRepl(&gc);
    } else {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("Usage: kozi <path>", .{});
        std.process.exit(1);
    }
}

fn runRepl(gc: *GarbageCollector) !void {
    var runtime = Runtime.init(gc);
    defer runtime.deinit();

    var buf: [512]u8 = undefined;
    const stdin = std.io.getStdIn().reader();

    std.debug.print("> ", .{});
    const bytesRead = try stdin.read(buf[0..]);
    if (bytesRead == 0) return; // EOF

    const line = buf[0..bytesRead];
    std.debug.print("You typed: {s}\n", .{line});
    _ = try gc.newString(line);
    std.debug.print("There are '{}' bytes allocated.\n", .{gc.bytes_allocated});
    gc.collect();
}

fn runFile(gc: *GarbageCollector, file_path: []const u8) !void {
    var runtime = Runtime.init(gc);
    defer runtime.deinit();
    _ = file_path;
    @panic("TODO: finish runFile implementation.");
}

test "run all tests" {
    _ = @import("virtual_machine.zig");
    _ = @import("compiler.zig");
    _ = @import("disassembler.zig");
    _ = @import("opcodes.zig");
    _ = @import("scanner.zig");
    _ = @import("value.zig");
    _ = @import("compiled_function.zig");
    _ = @import("garbage_collector.zig");
}
