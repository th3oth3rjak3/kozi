//! The scanner module contains functions related to producing
//! tokens from source code.

const std = @import("std");
const expect = std.testing.expect;

pub const Error = error{
    UnexpectedCharacter,
    UnterminatedString,
    InvalidNumber,
};

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
    /// line is the current line in the source code.
    line: usize,

    const Self = @This();

    /// new creates a new scanner using the provided
    /// source code.
    pub fn new(sourceCode: []const u8) Scanner {
        return .{
            .source = sourceCode,
            .start = 0,
            .current = 0,
            .line = 1,
        };
    }

    /// scanToken generates the next token from where it left off.
    ///
    /// Parameters:
    ///     - self: the scanner instance.
    ///
    /// Returns:
    ///     - Token: The newly generated token.
    pub fn scanToken(self: *Self) !Token {
        self.skipWhitespace();

        if (self.isAtEnd()) {
            return self.makeToken(TokenType.EOF);
        }

        self.start = self.current;

        const ch = self.peek();
        self.advance();

        if (isAlpha(ch)) {
            return self.identifier();
        }
        if (isDigit(ch)) {
            return self.number();
        }

        switch (ch) {
            '(' => return self.makeToken(TokenType.LeftParen),
            ')' => return self.makeToken(TokenType.RightParen),
            '{' => return self.makeToken(TokenType.LeftBrace),
            '}' => return self.makeToken(TokenType.RightBrace),
            '[' => return self.makeToken(TokenType.LeftBracket),
            ']' => return self.makeToken(TokenType.RightBracket),
            ',' => return self.makeToken(TokenType.Minus),
            '.' => return self.makeToken(TokenType.Period),
            ';' => return self.makeToken(TokenType.Semicolon),
            '+' => {
                if (self.peek() == '=') {
                    self.advance();
                    return self.makeToken(TokenType.PlusEqual);
                } else {
                    return self.makeToken(TokenType.Plus);
                }
            },
            '-' => {
                if (self.peek() == '=') {
                    self.advance();
                    return self.makeToken(TokenType.MinusEqual);
                } else {
                    return self.makeToken(TokenType.Minus);
                }
            },
            '*' => {
                if (self.peek() == '=') {
                    self.advance();
                    return self.makeToken(TokenType.StarEqual);
                } else {
                    return self.makeToken(TokenType.Star);
                }
            },
            '/' => {
                if (self.peek() == '=') {
                    self.advance();
                    return self.makeToken(TokenType.SlashEqual);
                } else {
                    return self.makeToken(TokenType.Slash);
                }
            },
            '!' => {
                if (self.peek() == '=') {
                    self.advance();
                    return self.makeToken(TokenType.BangEqual);
                } else {
                    return self.makeToken(TokenType.Bang);
                }
            },
            '=' => {
                if (self.peek() == '=') {
                    self.advance();
                    return self.makeToken(TokenType.EqualEqual);
                } else {
                    return self.makeToken(TokenType.Equal);
                }
            },
            '>' => {
                if (self.peek() == '=') {
                    self.advance();
                    return self.makeToken(TokenType.GreaterEqual);
                } else {
                    return self.makeToken(TokenType.Greater);
                }
            },
            '<' => {
                if (self.peek() == '=') {
                    self.advance();
                    return self.makeToken(TokenType.LessEqual);
                } else {
                    return self.makeToken(TokenType.Less);
                }
            },
            '"' => return try self.string(),
            else => return self.handleCharacterError("Unexpected token '{c}'.", .{ch}),
        }
    }

    /// handleCharacterError generates an error when a character is unexpected.
    fn handleCharacterError(self: *Self, comptime message: []const u8, args: anytype) !Token {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("[line {d}] Error: ", .{self.line});
        try stderr.print(message, args);
        try stderr.print("\n", .{});
        return error.UnexpectedCharacter;
    }

    /// makeToken creates a token of the specified type.
    fn makeToken(self: *Self, tokenType: TokenType) Token {
        const lexeme = self.source[self.start..self.current];
        return .{
            .lexeme = lexeme,
            .line = self.line,
            .tokenType = tokenType,
        };
    }

    /// makeStringToken creates a token specifically for TokenType.String
    /// in order to strip off the surrounding quotes.
    fn makeStringToken(self: *Self) Token {
        const lexeme = self.source[(self.start + 1)..(self.current - 1)];
        return .{
            .lexeme = lexeme,
            .line = self.line,
            .tokenType = TokenType.String,
        };
    }

    /// skipWhitespace causes the scanner to move past any whitespace characters
    /// because they aren't considered significant in this language.
    fn skipWhitespace(self: *Self) void {
        while (!self.isAtEnd()) {
            const ch = self.peek();
            switch (ch) {
                ' ', '\t', '\r' => {
                    self.advance();
                },
                '\n' => {
                    self.advance();
                    self.line += 1;
                },
                '/' => {
                    if (self.peekNext() == '/') {
                        self.advance();
                        while (!self.isAtEnd() and self.peek() != '\n') {
                            self.advance();
                        }
                    } else {
                        break;
                    }
                },
                else => break,
            }
        }
    }

    /// advance increments the current index by 1.
    fn advance(self: *Self) void {
        self.current += 1;
    }

    /// peek gets the character at the current position.
    fn peek(self: *const Self) u8 {
        if (self.isAtEnd()) {
            return 0;
        }

        return self.source[self.current];
    }

    /// peekNext peeks at the character just beyond the current position.
    fn peekNext(self: *Self) u8 {
        if (self.current + 1 >= self.source.len) {
            return 0;
        }

        return self.source[self.current + 1];
    }

    /// isAtEnd returns true when the current position of the scanner
    /// has reached the end of the source code.
    fn isAtEnd(self: *const Self) bool {
        return self.current >= self.source.len;
    }

    /// string creates a string token at the current position.
    fn string(self: *Self) !Token {
        while (!self.isAtEnd() and self.peek() != '"') {
            self.advance();
        }

        // must have run out of source code.
        if (self.peek() != '"') {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("[line {}] Error: Unterminated string.", .{self.line});
            return error.UnterminatedString;
        }
        // skip over the closing quote.
        self.advance();

        return self.makeStringToken();
    }

    /// number creates a number token.
    fn number(self: *Self) !Token {
        while (!self.isAtEnd() and Scanner.isDigit(self.peek())) {
            self.advance();
        }

        if (self.peek() != '.') {
            return self.makeToken(TokenType.Number);
        }

        if (!Scanner.isDigit(self.peekNext())) {
            // we assume that we have a period but no trailing numbers
            // which is invalid syntax.
            return error.InvalidNumber;
        }

        // Advance over the period.
        self.advance();
        while (!self.isAtEnd() and Scanner.isDigit(self.peek())) {
            self.advance();
        }

        return self.makeToken(TokenType.Number);
    }

    /// identifier handles creation of all other identifier tokens.
    fn identifier(self: *Self) Token {
        while (!self.isAtEnd() and (Scanner.isAlpha(self.peek()) or Scanner.isDigit(self.peek()))) {
            self.advance();
        }

        const tokenType = self.identifierType();
        return self.makeToken(tokenType);
    }

    /// identifierType looks up if the identifier is a reserved word or a user specified
    /// identifier for a variable name and produces the correct TokenType.
    fn identifierType(self: *Self) TokenType {
        if (ReservedWords.get(self.source[self.start..self.current])) |reserved| {
            return reserved;
        }

        return TokenType.Identifier;
    }

    /// isDigit checks a character to see if it is between
    /// '0' and '9'.
    fn isDigit(ch: u8) bool {
        return '0' <= ch and ch <= '9';
    }

    /// isAlpha checks a chacter to see if it's valid for an identifier name.
    fn isAlpha(ch: u8) bool {
        return switch (ch) {
            'a'...'z', 'A'...'Z', '_' => true,
            else => false,
        };
    }
};

const ReservedWords = std.StaticStringMap(TokenType).initComptime(.{
    .{"and", TokenType.And},
    .{"class", TokenType.Class},
    .{"else", TokenType.Else},
    .{"false", TokenType.False},
    .{"for", TokenType.For},
    .{"fun", TokenType.Fun},
    .{"if", TokenType.If},
    .{"nil", TokenType.Nil},
    .{"or", TokenType.Or},
    .{"print", TokenType.Print},
    .{"return", TokenType.Return},
    .{"super", TokenType.Super},
    .{"this", TokenType.This},
    .{"true", TokenType.True},
    .{"let", TokenType.Let},
    .{"while", TokenType.While},
});

test "is at end checks source length" {
    const source = "hello world";
    var scanner = Scanner.new(source);
    try expect(!scanner.isAtEnd());

    scanner.current = source.len;
    try expect(scanner.isAtEnd());
}

test "scanner peeks at characters" {
    var scanner = Scanner.new("hello world");
    try expect(scanner.peek() == 'h');

    scanner.current = 4;
    try expect(scanner.peek() == 'o');

    scanner.current = 100;
    try expect(scanner.peek() == 0);
}

test "scanner peeks at the next character" {
    var scanner = Scanner.new("hello world");
    try expect(scanner.peekNext() == 'e');

    scanner.current = 4;
    try expect(scanner.peekNext() == ' ');

    scanner.current = 100;
    try expect(scanner.peekNext() == 0);
}

test "skipWhitespace should skip whitespace characters" {
    var scanner = Scanner.new("  hello");
    scanner.skipWhitespace();
    try expect(scanner.current == 2);

    scanner = Scanner.new("\nworld.");
    try expect(scanner.line == 1);
    scanner.skipWhitespace();
    try expect(scanner.line == 2);

    scanner = Scanner.new("// a comment which should be skipped\n(");
    scanner.skipWhitespace();
    try expect(scanner.line == 2);
    try expect(scanner.source[scanner.current] == '(');
}

test "scanToken should create TokenType.LeftParen" {
    var scanner = Scanner.new("(");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.LeftParen);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "(", token.lexeme));
}

test "scanToken should create TokenType.RightParen" {
    var scanner = Scanner.new(")");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.RightParen);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, ")", token.lexeme));
}

test "scanToken should create TokenType.LeftBrace" {
    var scanner = Scanner.new("{");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.LeftBrace);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "{", token.lexeme));
}

test "scanToken should create TokenType.RightBrace" {
    var scanner = Scanner.new("}");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.RightBrace);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "}", token.lexeme));
}

test "scanToken should create TokenType.LeftBracket" {
    var scanner = Scanner.new("[");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.LeftBracket);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "[", token.lexeme));
}

test "scanToken should create TokenType.RightBracket" {
    var scanner = Scanner.new("]");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.RightBracket);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "]", token.lexeme));
}

test "scanToken should create TokenType.Plus" {
    var scanner = Scanner.new("+");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.Plus);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "+", token.lexeme));
}

test "scanToken should create TokenType.PlusEqual" {
    var scanner = Scanner.new("+=");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.PlusEqual);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "+=", token.lexeme));
}

test "scanToken should create TokenType.Minus" {
    var scanner = Scanner.new("-");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.Minus);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "-", token.lexeme));
}

test "scanToken should create TokenType.MinusEqual" {
    var scanner = Scanner.new("-=");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.MinusEqual);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "-=", token.lexeme));
}

test "scanToken should create TokenType.Star" {
    var scanner = Scanner.new("*");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.Star);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "*", token.lexeme));
}

test "scanToken should create TokenType.StarEqual" {
    var scanner = Scanner.new("*=");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.StarEqual);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "*=", token.lexeme));
}

test "scanToken should create TokenType.Slash" {
    var scanner = Scanner.new("/");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.Slash);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "/", token.lexeme));
}

test "scanToken should create TokenType.SlashEqual" {
    var scanner = Scanner.new("/=");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.SlashEqual);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "/=", token.lexeme));
}

test "scanToken should create TokenType.Greater" {
    var scanner = Scanner.new(">");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.Greater);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, ">", token.lexeme));
}

test "scanToken should create TokenType.GreaterEqual" {
    var scanner = Scanner.new(">=");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.GreaterEqual);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, ">=", token.lexeme));
}

test "scanToken should create TokenType.Less" {
    var scanner = Scanner.new("<");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.Less);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "<", token.lexeme));
}

test "scanToken should create TokenType.LessEqual" {
    var scanner = Scanner.new("<=");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.LessEqual);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "<=", token.lexeme));
}

test "scanToken should create TokenType.Bang" {
    var scanner = Scanner.new("!");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.Bang);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "!", token.lexeme));
}

test "scanToken should create TokenType.BangEqual" {
    var scanner = Scanner.new("!=");
    const token = try scanner.scanToken();

    try expect(token.tokenType == TokenType.BangEqual);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "!=", token.lexeme));
}

test "scanToken should handle unknown character errors" {
    var scanner = Scanner.new("@");
    const result = scanner.scanToken();
    if (result) |_| {
        try expect(false);
    } else |err| {
        try expect(err == error.UnexpectedCharacter);
    }
}

test "isDigit should handle all numeric digits" {
    const digits: [10]u8 = .{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' };
    for (digits) |d| {
        try expect(Scanner.isDigit(d));
    }

    const nonDigits: [10]u8 = .{ 'n', 'o', 't', ' ', 'a', 'd', 'i', 'g', 'i', 't' };
    for (nonDigits) |n| {
        try expect(!Scanner.isDigit(n));
    }
}

test "isAlplha should handle all accepted alpha characters" {

    // 65 - 90 represents ASCII uppercase letters.
    for (65..91) |a| {
        try expect(Scanner.isAlpha(@intCast(a)));
    }

    // 97 - 122 represents ASCII lowercase letters.
    for (97..123) |a| {
        try expect(Scanner.isAlpha(@intCast(a)));
    }

    try expect(Scanner.isAlpha('_'));

    // non-alpha
    for (0..65) |n| {
        try expect(!Scanner.isAlpha(@intCast(n)));
    }

    for (91..95) |n| {
        try expect(!Scanner.isAlpha(@intCast(n)));
    }

    try expect(!Scanner.isAlpha(96));

    for (123..256) |n| {
        try expect(!Scanner.isAlpha(@intCast(n)));
    }
}

test "number function should scan numbers" {
    var scanner = Scanner.new("123");
    var token = try scanner.scanToken();
    try expect(std.mem.eql(u8, token.lexeme, "123"));
    try expect(token.line == 1);
    try expect(token.tokenType == TokenType.Number);

    scanner = Scanner.new("123.0");
    token = try scanner.scanToken();
    try expect(std.mem.eql(u8, token.lexeme, "123.0"));
    try expect(token.line == 1);
    try expect(token.tokenType == TokenType.Number);

    scanner = Scanner.new("123.456 other");
    token = try scanner.scanToken();
    try expect(std.mem.eql(u8, token.lexeme, "123.456"));
    try expect(token.line == 1);
    try expect(token.tokenType == TokenType.Number);

    scanner = Scanner.new("123."); // invalid number
    if (scanner.scanToken()) |_| {
        try expect(false);
    } else |err| {
        try expect(err == error.InvalidNumber);
    }
}

test "string function should scan single line strings" {
    var scanner = Scanner.new("\"I am a string.\"");
    const token = try scanner.scanToken();
    try expect(std.mem.eql(u8, "I am a string.", token.lexeme));
    try expect(token.line == 1);
    try expect(token.tokenType == TokenType.String);
}

test "identifier function should handle keywords and other identifiers" {
    var scanner = Scanner.new("and");
    var token = try scanner.scanToken();
    try expect(token.tokenType == TokenType.And);

    scanner = Scanner.new("class");
    token = try scanner.scanToken();
    try expect(token.tokenType == TokenType.Class);

    scanner = Scanner.new("else");
    token = try scanner.scanToken();
    try expect(token.tokenType == TokenType.Else);

    scanner = Scanner.new("false");
    token = try scanner.scanToken();
    try expect(token.tokenType == TokenType.False);

    scanner = Scanner.new("for");
    token = try scanner.scanToken();
    try expect(token.tokenType == TokenType.For);

    scanner = Scanner.new("fun");
    token = try scanner.scanToken();
    try expect(token.tokenType == TokenType.Fun);

    scanner = Scanner.new("if");
    token = try scanner.scanToken();
    try expect(token.tokenType == TokenType.If);

    scanner = Scanner.new("nil");
    token = try scanner.scanToken();
    try expect(token.tokenType == TokenType.Nil);

    scanner = Scanner.new("or");
    token = try scanner.scanToken();
    try expect(token.tokenType == TokenType.Or);

    scanner = Scanner.new("print");
    token = try scanner.scanToken();
    try expect(token.tokenType == TokenType.Print);

    scanner = Scanner.new("return");
    token = try scanner.scanToken();
    try expect(token.tokenType == TokenType.Return);

    scanner = Scanner.new("super");
    token = try scanner.scanToken();
    try expect(token.tokenType == TokenType.Super);

    scanner = Scanner.new("this");
    token = try scanner.scanToken();
    try expect(token.tokenType == TokenType.This);

    scanner = Scanner.new("true");
    token = try scanner.scanToken();
    try expect(token.tokenType == TokenType.True);

    scanner = Scanner.new("let");
    token = try scanner.scanToken();
    try expect(token.tokenType == TokenType.Let);

    scanner = Scanner.new("while");
    token = try scanner.scanToken();
    try expect(token.tokenType == TokenType.While);

    scanner = Scanner.new("myThing123");
    token = try scanner.scanToken();
    try expect(token.tokenType == TokenType.Identifier);
    try expect(std.mem.eql(u8, token.lexeme, "myThing123"));
}