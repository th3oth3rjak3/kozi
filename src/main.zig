//! The Kozi Programming Language
//! Author: Jake Hathaway <jake.d.hathaway@gmail.com>
//! May 21, 2025

const std = @import("std");
const builtin = @import("builtin");

const compiled_function_file = @import("compiled_function.zig");
const compiler_file = @import("compiler.zig");
const disassembler = @import("disassembler.zig");
const gc_file = @import("gc_allocator.zig");
const opcode_file = @import("opcodes.zig");
const value = @import("value.zig");
const virtual_machine = @import("virtual_machine.zig");

const Allocator = std.mem.Allocator;
const CompiledFunction = compiled_function_file.CompiledFunction;
const Compiler = compiler_file.Compiler;
const GcAllocator = gc_file.GcAllocator;
const Op = opcode_file.Op;
const String = value.String;
const Value = value.Value;
const VirtualMachine = virtual_machine.VirtualMachine;

var debug_allocator = std.heap.DebugAllocator(.{}).init;

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
            std.debug.print("\n", .{});
            std.debug.print("******************************************************\n", .{});
            std.debug.print("*                                                    *\n", .{});
            std.debug.print("*               Memory Leaks Detected!!!             *\n", .{});
            std.debug.print("*                                                    *\n", .{});
            std.debug.print("******************************************************\n", .{});
        } else {
            std.debug.print("\n", .{});
            std.debug.print("******************************************************\n", .{});
            std.debug.print("*                                                    *\n", .{});
            std.debug.print("*               No Memory Leaks Detected             *\n", .{});
            std.debug.print("*                                                    *\n", .{});
            std.debug.print("******************************************************\n", .{});
        }
    };

    // Read args from the command line.
    const args = try std.process.argsAlloc(mem.allocator);
    defer std.process.argsFree(mem.allocator, args);

    // if we have args, run file
    if (args.len == 2) {
        try runFile(mem.allocator, args[1]);
    } else if (args.len == 1) {
        try runRepl(mem.allocator);
    } else {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("Usage: kozi <path>", .{});
        std.process.exit(64);
    }
}

fn runRepl(allocator: Allocator) !void {
    var gc = GcAllocator.init(allocator);
    defer gc.deinit();

    var vm = VirtualMachine.init(&gc);
    defer vm.deinit();

    gc.setVm(&vm);

    var fun = CompiledFunction.init(allocator);
    defer fun.deinit();

    const stdin = std.io.getStdIn().reader();

    var buf: [1024]u8 = undefined;

    while (true) {
        gc.reset();
        std.debug.print("> ", .{});
        if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |input| {
            // Got input
            const trimmed = std.mem.trim(u8, input, " \t\r\n");
            if (trimmed.len == 0) continue;
            _ = try vm.interpret(trimmed, &fun);
            fun.reset();
        } else {
            // EOF (Ctrl+D) detected
            break;
        }
    }
}

fn runFile(allocator: Allocator, file_path: []const u8) !void {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(file_path, std.fs.File.OpenFlags{});
    defer file.close();
    const source = try file.readToEndAlloc(allocator, std.math.maxInt(u64));
    defer allocator.free(source);

    var gc = GcAllocator.init(allocator);
    defer gc.deinit();

    var vm = VirtualMachine.init(&gc);
    defer vm.deinit();

    gc.setVm(&vm);

    var fun = CompiledFunction.init(allocator);
    defer fun.deinit();

    const result = try vm.interpret(source, &fun);
    switch (result) {
        .Ok => {},
        .CompileError => {
            std.process.exit(65);
        },
        .RuntimeError => {
            std.process.exit(70);
        },
    }
}

test "run all tests" {
    _ = @import("compiled_function.zig");
    _ = @import("compiler.zig");
    _ = @import("disassembler.zig");
    _ = @import("gc_allocator.zig");
    _ = @import("opcodes.zig");
    _ = @import("scanner.zig");
    _ = @import("value.zig");
    _ = @import("virtual_machine.zig");
}
