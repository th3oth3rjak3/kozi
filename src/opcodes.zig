//! opcodes.zig contains all the types related to reading and writing bytecode.

const std = @import("std");
const expect = std.testing.expect;

/// Op represents an operation to be performed by the virtual machine.
pub const Op = enum(u8) {
    /// Pop the topmost value from the stack.
    Pop,
    /// Return from a function.
    Return,
    /// Load the constant at the address specified in the following two bytes (u16)
    Constant,
    /// Negate a numeric value, e.g.: 1 -> -1
    Negate,
    Add,
    Subtract,
    Multiply,
    Divide,
    Nil,
    True,
    False,
    Not,
    Equal,
    NotEqual,
    Greater,
    GreaterEqual,
    Less,
    LessEqual,
    Print,
    DefineGlobal,
    GetGlobal,
    SetGlobal,
};
