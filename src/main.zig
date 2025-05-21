//! The Kozi Programming Language
//! Author: Jake Hathaway <jake.d.hathaway@gmail.com>
//! May 21, 2025

const std = @import("std");
const builtin = @import("builtin");
const vm = @import("vm.zig");
const compiler = @import("compiler.zig");
const disassembler = @import("disassembler.zig");
const op = @import("opcodes.zig");

var debugAllocator = std.heap.DebugAllocator(.{}).init;

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
            .allocator = debugAllocator.allocator(),
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
        const result = debugAllocator.deinit();
        if (result == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        } else {
            std.debug.print("No memory leaks detected.\n", .{});
        }
    };

    // Read args from the command line.
    const args = try std.process.argsAlloc(mem.allocator);
    defer std.process.argsFree(mem.allocator, args);

    std.debug.print("{}", .{vm});

    // if we have args, run file
    if (args.len > 1) {
        // try runFile(mem.allocator, args[1]);
    } else {
        // try runRepl(mem.allocator);
    }
}

test "run all tests" {
    _ = vm;
    _ = compiler;
    _ = disassembler;
    _ = op;
}
