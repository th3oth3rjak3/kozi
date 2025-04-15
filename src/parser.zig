//! parser converts the lexer tokens into an abstract syntax tree.

const std = @import("std");
const l = @import("lexer.zig");
const t = @import("token.zig");
const ast = @import("ast.zig");

/// Parser converts tokens created by the lexer into the abstract syntax
/// tree nodes that are used to intepret the language.
pub const Parser = struct {
    /// The allocator for allocating additional memory.
    allocator: *std.mem.Allocator,
    /// A lexer for getting tokens.
    lexer: *l.Lexer,

    const Self = @This();

    pub fn init(allocator: *std.mem.Allocator, lexer: *l.Lexer) *Parser {
        var p = Parser{
            .allocator = allocator,
            .lexer = lexer,
        };

        return &p;
    }

    /// parse reads all the source code and turns the tokens into an abstract syntax tree.
    pub fn parseProgram(self: *Self) *ast.Program {
        // var statements = std.ArrayList(ast.Statement).init(self.allocator.*);

        // var tok: ?t.Token = self.lexer.nextToken() catch |err| {
        //     const stdout = std.io.getStdOut();
        //     defer stdout.close();
        //     stdout.writer().print("Error while processing source code: {s}", err);
        //     return null;
        // };

        // statements.addOne(ast.Statement.Expression{token: })
        // const p = ast.Program{ .statements = &statements };
        //
        const statements: []ast.Statement = &[_]ast.Statement{};
        _ = self;
        var program = ast.Program{ .statements = statements };
        return &program;
    }
};
