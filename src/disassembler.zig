//! Disassembler is used for debugging during language development.

const std = @import("std");
const compiled_function_file = @import("compiled_function.zig");
const opcode_file = @import("opcodes.zig");

var BUF_WRITER = std.io.bufferedWriter(std.io.getStdOut().writer());
const WRITER = BUF_WRITER.writer();
const CompiledFunction = compiled_function_file.CompiledFunction;
const Op = opcode_file.Op;

pub fn disassembleCompiledFunction(fun: *const CompiledFunction, name: []const u8) !void {
    defer BUF_WRITER.flush() catch {};
    try WRITER.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < fun.bytecode.items.len) {
        offset = try disassembleInstruction(fun, offset, WRITER);
    }
}

pub fn disassembleInstruction(fun: *const CompiledFunction, offset: usize, writer: anytype) !usize {
    if (offset >= fun.bytecode.items.len) {
        return offset + 1;
    }
    try std.fmt.format(writer, "{d:04} ", .{offset});
    if (offset > 0 and fun.lines.items[offset] == fun.lines.items[offset - 1]) {
        try std.fmt.format(writer, "   | ", .{});
    } else {
        try std.fmt.format(writer, "{d:04} ", .{fun.lines.items[offset]});
    }

    const instruction: Op = @enumFromInt(fun.bytecode.items[offset]);
    return switch (instruction) {
        .Return => simpleInstruction("OP_RETURN", offset, writer),
        .Pop => simpleInstruction("OP_POP", offset, writer),
        .Constant => constantInstruction("OP_CONSTANT", fun, offset, writer),
        .Negate => simpleInstruction("OP_NEGATE", offset, writer),
        .Add => simpleInstruction("OP_ADD", offset, writer),
        .Subtract => simpleInstruction("OP_SUBTRACT", offset, writer),
        .Multiply => simpleInstruction("OP_MULTIPLY", offset, writer),
        .Divide => simpleInstruction("OP_DIVIDE", offset, writer),
        .Nil => simpleInstruction("OP_NIL", offset, writer),
        .True => simpleInstruction("OP_TRUE", offset, writer),
        .False => simpleInstruction("OP_FALSE", offset, writer),
        .Not => simpleInstruction("OP_NOT", offset, writer),
        .Equal => simpleInstruction("OP_EQUAL", offset, writer),
        .NotEqual => simpleInstruction("OP_NOT_EQUAL", offset, writer),
        .Greater => simpleInstruction("OP_GREATER", offset, writer),
        .GreaterEqual => simpleInstruction("OP_GREATER_EQUAL", offset, writer),
        .Less => simpleInstruction("OP_LESS", offset, writer),
        .LessEqual => simpleInstruction("OP_LESS_EQUAL", offset, writer),
    };
}

fn simpleInstruction(name: []const u8, offset: usize, writer: anytype) !usize {
    try std.fmt.format(writer, "{s:<16}\n", .{name});
    return offset + 1;
}

fn constantInstruction(name: []const u8, fun: *const CompiledFunction, offset: usize, writer: anytype) !usize {
    const high_byte: u8 = fun.bytecode.items[offset + 1];
    const low_byte: u8 = fun.bytecode.items[offset + 2];
    const address: u16 = @as(u16, high_byte) << 4 | @as(u16, low_byte);
    const value = fun.constants.items[address];
    try std.fmt.format(writer, "{s:<16} {d:04} '", .{ name, address });
    try value.printValue(writer);
    try std.fmt.format(writer, "'\n", .{});
    return offset + 3;
}
