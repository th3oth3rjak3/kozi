//! token contains the definitions for lexer tokens and their types.

const std = @import("std");

/// TokenType represents the type of token that was parsed from source.
pub const TokenType = enum(u8) {
    // flow control
    /// Illegal represents an unknown input.
    Illegal,
    /// Eof represents end of file.
    Eof,

    // Literals
    /// A user defined identifier which will be bound to a variable.
    Identifier,
    /// Number represents any number literal.
    Number,
    /// String represents any string literal.
    String,

    // single character tokens
    /// LeftParen -> "("
    LeftParen,
    /// RightParen -> ")"
    RightParen,
    /// LeftCurlyBrace -> "{"
    LeftCurlyBrace,
    /// RightCurlyBrace -> "}"
    RightCurlyBrace,
    /// LeftSquareBracket -> "["
    LeftSquareBracket,
    /// RightSquareBracket -> "]"
    RightSquareBracket,
    /// Comma -> ","
    Comma,
    /// Period -> "."
    Period,
    /// Minus -> "-"
    Minus,
    /// Plus -> "+"
    Plus,
    /// Semicolon -> ";"
    Semicolon,
    /// Colon -> ":"
    Colon,
    /// Slash -> "/"
    Slash,
    /// Asterisk -> "*"
    Asterisk,

    // one or two character tokens
    /// Bang -> "!"
    Bang,
    /// BangEqual -> "!="
    BangEqual,
    /// Assign -> "="
    Assign,
    /// EqualEqual -> "=="
    EqualEqual,
    /// Greater -> ">"
    Greater,
    /// GreaterEqual -> ">="
    GreaterEqual,
    /// Less -> "<"
    Less,
    /// LessEqual -> "<="
    LessEqual,

    // keywords
    /// Logical And
    And,
    /// Break indicates a loop should stop iterating.
    Break,
    /// Class keyword indicating a class definition
    Class,
    /// Continue indicates that a loop should go to the next iteration.
    Continue,
    /// Else from the if/else construct.
    Else,
    /// False meaning not true.
    False,
    /// Fun is the keyword for definining functions.
    Fun,
    /// If is from the if/else construct.
    If,
    /// Let is the identifier binding keyword. e.g. let x = 1
    Let,
    /// Loop defines a loop
    Loop,
    /// Nil represents no value.
    Nil,
    /// Logical or.
    Or,
    /// Return a value from an expression.
    Return,
    /// Super represents a base class for an inheriting class.
    Super,
    /// This represents the current instance of a class
    This,
    /// True represents literal boolean value true.
    True,
};

/// Keywords are reserved keywords for the language.
const Keywords = std.StaticStringMap([]const u8).initComptime(
    .{
        .{ "and", .And },
        .{ "break", .Break },
        .{ "class", .Class },
        .{ "continue", .Continue },
        .{ "else", .Else },
        .{ "false", .False },
        .{ "fun", .Fun },
        .{ "if", .If },
        .{ "let", .Let },
        .{ "loop", .Loop },
        .{ "nil", .Nil },
        .{ "or", .Or },
        .{ "return", .Return },
        .{ "super", .Super },
        .{ "this", .This },
        .{ "true", .True },
    },
);

// const TokenStrings = std.StaticStringMap([]const u8).initComptime(.{
//     .{ .Illegal, "ILLEGAL" },
//     .{ .Eof, "EOF" },
//     .{ .Identifier, "IDENTIFIER" },
//     .{ .Number, "NUMBER" },
//     .{ .String, "STRING" },
//     .{ .LeftParen, "(" },
//     .{ .RightParen, ")" },
//     .{ .LeftCurlyBrace, "{" },
//     .{ .RightCurlyBrace, "}" },
//     .{ .LeftSquareBracket, "[" },
//     .{ .RightSquareBracket, "]" },
//     .{ .Comma, "," },
//     .{ .Period, "." },
//     .{ .Minus, "-" },
//     .{ .Plus, "+" },
//     .{ .Semicolon, ";" },
//     .{ .Colon, ":" },
//     .{ .Slash, "/" },
//     .{ .Asterisk, "*" },
//     .{ .Bang, "!" },
//     .{ .BangEqual, "!=" },
//     .{ .Assign, "=" },
//     .{ .EqualEqual, "==" },
//     .{ .Greater, ">" },
//     .{ .GreaterEqual, ">=" },
//     .{ .Less, "<" },
//     .{ .LessEqual, "<=" },
//     .{ .And, "and" },
//     .{ .Break, "break" },
//     .{ .Class, "class" },
//     .{ .Continue, "continue" },
//     .{ .Else, "else" },
//     .{ .False, "false" },
//     .{ .Fun, "fun" },
//     .{ .If, "if" },
//     .{ .Let, "let" },
//     .{ .Loop, "loop" },
//     .{ .Nil, "nil" },
//     .{ .Or, "or" },
//     .{ .Return, "return" },
//     .{ .Super, "super" },
//     .{ .This, "this" },
//     .{ .True, "true" },
// });

const StringTokens = std.StaticStringMap(TokenType).initComptime(.{
    .{ "ILLEGAL", .Illegal },
    .{ "EOF", .Eof },
    .{ "IDENTIFIER", .Identifier },
    .{ "NUMBER", .Number },
    .{ "STRING", .String },
    .{ "(", .LeftParen },
    .{ ")", .RightParen },
    .{ "{", .LeftCurlyBrace },
    .{ "}", .RightCurlyBrace },
    .{ "[", .LeftSquareBracket },
    .{ "]", .RightSquareBracket },
    .{ ",", .Comma },
    .{ ".", .Period },
    .{ "-", .Minus },
    .{ "+", .Plus },
    .{ ";", .Semicolon },
    .{ ":", .Colon },
    .{ "/", .Slash },
    .{ "*", .Asterisk },
    .{ "!", .Bang },
    .{ "!=", .BangEqual },
    .{ "=", .Assign },
    .{ "==", .EqualEqual },
    .{ ">", .Greater },
    .{ ">=", .GreaterEqual },
    .{ "<", .Less },
    .{ "<=", .LessEqual },
    .{ "and", .And },
    .{ "break", .Break },
    .{ "class", .Class },
    .{ "continue", .Continue },
    .{ "else", .Else },
    .{ "false", .False },
    .{ "fun", .Fun },
    .{ "if", .If },
    .{ "let", .Let },
    .{ "loop", .Loop },
    .{ "nil", .Nil },
    .{ "or", .Or },
    .{ "return", .Return },
    .{ "super", .Super },
    .{ "this", .This },
    .{ "true", .True },
});

pub fn lookupIdent(name: []const u8) TokenType {
    const lookup = StringTokens.get(name);
    if (lookup) |found| {
        return found;
    }
    return .Identifier;
}

/// Token represents the output of a lexer from source code into an
/// intermediate form. Tokens are used as a step between raw source
/// and the AST.
pub const Token = struct {
    /// tokenType is the type of token that this represents
    tokenType: TokenType,
    /// literal is the actual value parsed from source
    literal: []const u8,
    /// lineNumber is which line of the input source the token came from
    lineNumber: usize,
    /// charPosition is which position in the line the token started at
    charPosition: usize,
    /// fileName is the file that the token was parsed from
    fileName: []const u8,

    // const Self = @This();

    pub fn toString(self: @This(), buf: []u8) []const u8 {
        const output = std.fmt.bufPrint(buf, "Token: {s}, Literal: \"{s}\", Line: {d}, Char: {d}, FileName: {s}", .{
            @tagName(self.tokenType),
            self.literal,
            self.lineNumber,
            self.charPosition,
            self.fileName,
        }) catch {
            return "Error";
        };
        return output;
    }
};
