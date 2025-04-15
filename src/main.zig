//! The Kozi Programming Language
//! Author: Jake Hathaway <jake.d.hathaway@gmail.com>
//! April 14, 2025

const std = @import("std");
const builtin = @import("builtin");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

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
    var mem = getAllocator();
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

    // if we have args, run file
    if (args.len > 1) {
        try runFile(&mem.allocator, args[1]);
    } else {
        try runRepl(&mem.allocator);
    }
}

/// runFile opens the file at the provided path and runs the source code.
///
/// Parameters:
///  - allocator: The allocator to handle all memory allocations.
///  - filePath: The relative file path from the current working directory.
fn runFile(allocator: *std.mem.Allocator, filePath: []const u8) !void {
    const sourceCode = getFileContents(allocator, filePath) catch |err| {
        const stderr = std.io.getStdErr();
        defer stderr.close();
        const errMsg = "Error: could not open file at the provided path '{s}' ({s})\n";
        stderr.writer().print(errMsg, .{ filePath, @errorName(err) }) catch {};
        return;
    };
    defer allocator.free(sourceCode);

    const l = try lexer.Lexer.init(allocator, sourceCode, filePath);
    defer allocator.destroy(l);
    var token = try l.nextToken();
    while (token.tokenType != .Eof) {
        var buf: [1024]u8 = undefined;
        const msg = token.toString(&buf);
        try std.io.getStdOut().writer().print("{s}\n", .{msg});
        token = try l.nextToken();
    }
}

/// getFileContents reads source code from a file.
///
/// Parameters:
///  - allocator: The allocator used to hold the source code.
///  - filePath: The relative file path from the current working directory.
///
/// Returns:
///  - ![]u8: The source code read into memory.
fn getFileContents(allocator: *std.mem.Allocator, filePath: []const u8) ![]u8 {
    const kb: usize = 1024;
    const mb: usize = kb * 1024;
    const maxFileSize: usize = 500 * mb;
    const file = try std.fs.cwd().openFile(filePath, .{});
    defer file.close();
    const fileContents = try file.readToEndAlloc(allocator.*, maxFileSize);
    return fileContents;
}

/// runRepl starts a Read, Eval, Print, Loop cycle in the terminal
/// for trying out the language.
fn runRepl(allocator: *std.mem.Allocator) !void {
    while (true) {
        var buffer: [1024]u8 = undefined; // 1KB buffer on the stack
        const stdout = std.io.getStdOut();
        stdout.writer().print(">>> ", .{}) catch {}; // TODO: error handling
        const stdin = std.io.getStdIn();
        const sourceCode = stdin.reader().readUntilDelimiterOrEof(&buffer, '\n') catch {
            return;
        }; // TODO: error handling
        if (sourceCode == null) {
            continue;
        }
        var l = try lexer.Lexer.init(allocator, sourceCode.?, "REPL");
        defer allocator.destroy(l);
        // var p = parser.Parser.init(allocator, l);
        // const program = p.parseProgram();
        // _ = program;
        var token = l.nextToken() catch {
            _ = try std.io.getStdErr().write("The provided input was invalid, please try again.\n");
            continue;
        };
        while (token.tokenType != .Eof) {
            var buf: [1024]u8 = undefined;
            const msg = token.toString(&buf);
            try stdout.writer().print("{s}\n", .{msg});
            token = try l.nextToken();
        }
    }
}
