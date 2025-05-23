const std = @import("std");

/// Compiler converts source code into runnable bytecode.
pub const Compiler = struct {
    const Self = @This();

    pub fn init() Compiler {
        return Compiler{};
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};
