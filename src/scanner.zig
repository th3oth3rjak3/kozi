//! The scanner module contains functions related to producing
//! tokens from source code.

const std = @import("std");
const expect = std.testing.expect;

/// TokenType represents what kind of token it is.
pub const TokenType = enum(u8) {
    /// \(
    LeftParen,
    /// \)
    RightParen,
    /// \{
    LeftBrace,
    /// \}
    RightBrace,
    /// \[
    LeftBracket,
    /// \]
    RightBracket,
    /// \,
    Comma,
    /// \.
    Period,
    /// \-
    Minus,
    /// \-=
    MinusEqual,
    /// \+
    Plus,
    /// \+=
    PlusEqual,
    /// \;
    Semicolon,
    /// \/
    Slash,
    /// \/=
    SlashEqual,
    /// \*
    Star,
    /// \*=
    StarEqual,
    /// \!
    Bang,
    /// \!=
    BangEqual,
    /// \=
    Equal,
    /// \==
    EqualEqual,
    /// \>
    Greater,
    /// \>=
    GreaterEqual,
    /// \<
    Less,
    /// \<=
    LessEqual,

    // Literals.
    Identifier,
    String,
    Number,

    // Keywords.
    And,
    Class,
    Else,
    False,
    For,
    Fun,
    If,
    Nil,
    Or,
    // TODO: Remove this and turn it into a builtin function later.
    Print,
    Return,
    Super,
    This,
    True,
    Let,
    While,

    // other
    Error,
    EOF,
};

/// Token is an internal representation of source code
/// used for parsing.
pub const Token = struct {
    /// tokenType is the internal type of the token, e.g.: class, fun, etc.
    tokenType: TokenType,
    /// lexeme is the string representation of the token.
    lexeme: []const u8,
    /// line is the source code line number where the token
    /// came from.
    line: usize,
};

/// Scanner scans source code for recognizable
/// tokens which are later converted into bytecode
/// instructions through parsing.
pub const Scanner = struct {
    /// source is the source code to be scanned.
    source: []const u8,
    /// start is the position where the scanner started scanning the current token
    /// in the source code.
    start: usize,
    /// current is where the scanner is currently.
    current: usize,

    const Self = @This();

    /// new creates a new scanner using the provided
    /// source code.
    pub fn new(sourceCode: []const u8) Scanner {
        return .{
            .source = sourceCode,
            .start = 0,
            .current = 0,
        };
    }

    /// scanToken generates the next token from where it left off.
    ///
    /// Parameters:
    ///     - self: the scanner instance.
    ///
    /// Returns:
    ///     - Token: The newly generated token.
    pub fn scanToken(self: *Self) Token {
        _ = self;
        @panic("TODO: Finish scanToken implementation in the Scanner.");
    }
};
