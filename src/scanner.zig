//! The scanner module contains functions related to producing
//! tokens from source code.

const std = @import("std");
const expect = std.testing.expect;
const unicode = std.unicode;

pub const ScanError = struct {
    kind: ErrorKind,
    line: usize,
    column: usize,
    message: []const u8,
    codepoint: ?u21 = null,

    pub const ErrorKind = error{
        UnexpectedCharacter,
        UnterminatedString,
        InvalidNumber,
        InvalidUtf8,
    };

    pub fn format(self: ScanError, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: std.io.AnyWriter) !void {
        _ = fmt;
        _ = options;

        try writer.print("[line {d}:{d}] Error: {s}", .{ self.line, self.column, self.message });
        if (self.codepoint) |cp| {
            if (cp <= 127) {
                try writer.print(" ('{c}')", .{@as(u8, @intCast(cp))});
            } else {
                try writer.print(" (U+{X:0>4})", .{cp});
            }
        }
    }
};

/// ScanResult is a union that represents either a successful token or an error.
pub const ScanResult = union(enum) {
    token: Token,
    err: ScanError,

    pub fn newToken(token: Token) ScanResult {
        return ScanResult{ .token = token };
    }

    pub fn newError(err: ScanError) ScanResult {
        return ScanResult{ .err = err };
    }

    pub fn isOk(self: ScanResult) bool {
        return switch (self) {
            .token => true,
            .err => false,
        };
    }

    pub fn isErr(self: ScanResult) bool {
        return !self.isOk();
    }

    pub fn unwrap(self: ScanResult) Token {
        return switch (self) {
            .token => |token| token,
            .err => |err| std.debug.panic("Called unwrap on error: {}", .{err}),
        };
    }

    pub fn unwrapErr(self: ScanResult) ScanError {
        return switch (self) {
            .token => std.debug.panic("Called unwrapErr on token", .{}),
            .err => |err| err,
        };
    }
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
    /// column is the source code column number where the token
    /// came from.
    column: usize,
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
    /// column is the current column in the source code.
    column: usize,
    /// lineStart tracks the byte position where the current line starts
    lineStart: usize,

    const Self = @This();

    /// new creates a new scanner using the provided
    /// source code.
    pub fn new(sourceCode: []const u8) Scanner {
        return .{
            .source = sourceCode,
            .start = 0,
            .current = 0,
            .line = 1,
            .column = 1,
            .lineStart = 0,
        };
    }

    /// scanToken generates the next token from where it left off.
    ///
    /// Parameters:
    ///     - self: the scanner instance.
    ///
    /// Returns:
    ///     - Token: The newly generated token.
    pub fn scanToken(self: *Self) ScanResult {
        self.skipWhitespace();

        if (self.isAtEnd()) {
            const token = self.makeTokenWithColumn(TokenType.EOF, self.start);
            return ScanResult.newToken(token);
        }

        self.start = self.current;
        const startColumn = self.column;

        const codePoint = self.peekCodepoint() catch {
            return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 sequence", null);
        };

        self.advanceCodepoint() catch {
            return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 sequence", null);
        };

        if (isAlphaUnicode(codePoint)) {
            return self.identifier();
        }
        if (isDigit(codePoint)) {
            return self.number();
        }

        if (codePoint <= 127) {
            const ch = @as(u8, @intCast(codePoint));
            switch (ch) {
                '(' => return ScanResult.newToken(self.makeTokenWithColumn(TokenType.LeftParen, startColumn)),
                ')' => return ScanResult.newToken(self.makeTokenWithColumn(TokenType.RightParen, startColumn)),
                '{' => return ScanResult.newToken(self.makeTokenWithColumn(
                    TokenType.LeftBrace,
                    startColumn
                )),
                '}' => return ScanResult.newToken(self.makeTokenWithColumn(TokenType.RightBrace, startColumn)),
                '[' => return ScanResult.newToken(self.makeTokenWithColumn(TokenType.LeftBracket, startColumn)),
                ']' => return ScanResult.newToken(self.makeTokenWithColumn(TokenType.RightBracket, startColumn)),
                ',' => return ScanResult.newToken(self.makeTokenWithColumn(TokenType.Comma, startColumn)),
                '.' => return ScanResult.newToken(self.makeTokenWithColumn(TokenType.Period, startColumn)),
                ';' => return ScanResult.newToken(self.makeTokenWithColumn(TokenType.Semicolon, startColumn)),
                '+' => {
                    const nextCp = self.peekCodepoint() catch 0;
                    if (nextCp == '=') {
                        self.advanceCodepoint() catch {
                            return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 sequence", null);
                        };
                        return ScanResult.newToken(self.makeTokenWithColumn(TokenType.PlusEqual, startColumn));
                    } else {
                        return ScanResult.newToken(self.makeTokenWithColumn(TokenType.Plus, startColumn));
                    }
                },
                '-' => {
                    const nextCp = self.peekCodepoint() catch 0;
                    if (nextCp == '=') {
                        self.advanceCodepoint() catch {
                            return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 sequence", null);
                        };
                        return ScanResult.newToken(self.makeTokenWithColumn(TokenType.MinusEqual, startColumn));
                    } else {
                        return ScanResult.newToken(self.makeTokenWithColumn(TokenType.Minus, startColumn));
                    }
                },
                '*' => {
                    const nextCp = self.peekCodepoint() catch 0;
                    if (nextCp == '=') {
                        self.advanceCodepoint() catch {
                            return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 sequence", null);
                        };
                        return ScanResult.newToken(self.makeTokenWithColumn(TokenType.StarEqual, startColumn));
                    } else {
                        return ScanResult.newToken(self.makeTokenWithColumn(TokenType.Star, startColumn));
                    }
                },
                '/' => {
                    const nextCp = self.peekCodepoint() catch 0;
                    if (nextCp == '=') {
                        self.advanceCodepoint() catch {
                            return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 sequence", null);
                        };
                        return ScanResult.newToken(self.makeTokenWithColumn(TokenType.SlashEqual, startColumn));
                    } else {
                        return ScanResult.newToken(self.makeTokenWithColumn(TokenType.Slash, startColumn));
                    }
                },
                '!' => {
                    const nextCp = self.peekCodepoint() catch 0;
                    if (nextCp == '=') {
                        self.advanceCodepoint() catch {
                            return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 sequence", null);
                        };
                        return ScanResult.newToken(self.makeTokenWithColumn(TokenType.BangEqual, startColumn));
                    } else {
                        return ScanResult.newToken(self.makeTokenWithColumn(TokenType.Bang, startColumn));
                    }
                },
                '=' => {
                    const nextCp = self.peekCodepoint() catch 0;
                    if (nextCp == '=') {
                        self.advanceCodepoint() catch {
                            return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 sequence", null);
                        };
                        return ScanResult.newToken(self.makeTokenWithColumn(TokenType.EqualEqual, startColumn));
                    } else {
                        return ScanResult.newToken(self.makeTokenWithColumn(TokenType.Equal, startColumn));
                    }
                },
                '>' => {
                    const nextCp = self.peekCodepoint() catch 0;
                    if (nextCp == '=') {
                        self.advanceCodepoint() catch {
                            return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 sequence", null);
                        };
                        return ScanResult.newToken(self.makeTokenWithColumn(TokenType.GreaterEqual, startColumn));
                    } else {
                        return ScanResult.newToken(self.makeTokenWithColumn(TokenType.Greater, startColumn));
                    }
                },
                '<' => {
                    const nextCp = self.peekCodepoint() catch 0;
                    if (nextCp == '=') {
                        self.advanceCodepoint() catch {
                            return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 sequence", null);
                        };
                        return ScanResult.newToken(self.makeTokenWithColumn(TokenType.LessEqual, startColumn));
                    } else {
                        return ScanResult.newToken(self.makeTokenWithColumn(TokenType.Less, startColumn));
                    }
                },
                '"' => return self.string(),
                else => return self.makeError(ScanError.ErrorKind.UnexpectedCharacter, "Unexpected character", codePoint),
            }
        } else {
            return self.makeError(ScanError.ErrorKind.UnexpectedCharacter, "Unexpected Unicode character", codePoint);
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

    /// makeError generates a new error variant when scanning fails.
    fn makeError(self: *Self, kind: ScanError.ErrorKind, message: []const u8, codePoint: ?u21) ScanResult {
        return ScanResult.newError(ScanError{
            .kind = kind,
            .line = self.line,
            .column = self.column,
            .message = message,
            .codepoint = codePoint,
        });
    }

    /// makeTokenWithColumn creates a token with explicit column positioning.
    fn makeTokenWithColumn(self: *Self, tokenType: TokenType, column: usize) Token {
        const lexeme = self.source[self.start..self.current];
        return .{
            .lexeme = lexeme,
            .line = self.line,
            .column = column,
            .tokenType = tokenType,
        };
    }

    /// makeStringToken creates a token specifically for TokenType.String
    /// in order to strip off the surrounding quotes.
    fn makeStringToken(self: *Self, startColumn: usize) Token {
        const lexeme = self.source[(self.start + 1)..(self.current - 1)];
        return .{
            .lexeme = lexeme,
            .line = self.line,
            .column = startColumn,
            .tokenType = TokenType.String,
        };
    }

    /// skipWhitespace causes the scanner to move past any whitespace characters
    /// because they aren't considered significant in this language.
    fn skipWhitespace(self: *Self) void {
        while (!self.isAtEnd()) {
            const codePoint = self.peekCodepoint() catch break;
            if (codePoint <= 127) {
                const ch: u8 = @intCast(codePoint);
                switch (ch) {
                    ' ', '\t', '\r' => {
                        self.advanceCodepoint() catch break;
                    },
                    '\n' => {
                        self.advanceCodepoint() catch break;
                        self.line += 1;
                    },
                    '/' => {
                        const nextCp = self.peekNextCodepoint() catch break;
                        if (nextCp == '/') {
                            _ = self.advanceCodepoint() catch break; // consume first '/'
                            while (!self.isAtEnd()) {
                                const commentCp = self.peekCodepoint() catch break;
                                if (commentCp == '\n') break;
                                _ = self.advanceCodepoint() catch break;
                            }
                        } else {
                            break;
                        }
                    },
                    else => break,
                }
            } else if (isWhitespaceUnicode(codePoint)) {
                // Handle Unicode whitespace
                _ = self.advanceCodepoint() catch break;
            } else {
                break;
            }
        }
    }

    /// isAlphaUnicode checks if a codepoint is valid for an identifier name using Unicode categories.
    fn isAlphaUnicode(codepoint: u21) bool {
        // ASCII fast path
        if (codepoint <= 127) {
            const ch = @as(u8, @intCast(codepoint));
            return switch (ch) {
                'a'...'z', 'A'...'Z', '_' => true,
                else => false,
            };
        }

        // Unicode identifier start characters according to Unicode standard
        // This is a simplified version - in production you'd want full Unicode category support
        return switch (codepoint) {
            // Latin Extended-A
            0x00C0...0x00D6, 0x00D8...0x00F6, 0x00F8...0x00FF => true,
            // Latin Extended-B
            0x0100...0x017F => true,
            // Greek and Coptic
            0x0370...0x03FF => true,
            // Cyrillic
            0x0400...0x04FF => true,
            // Hebrew
            0x0590...0x05FF => true,
            // Arabic
            0x0600...0x06FF => true,
            // CJK Unified Ideographs (basic range)
            0x4E00...0x9FFF => true,
            // Hiragana
            0x3040...0x309F => true,
            // Katakana
            0x30A0...0x30FF => true,
            else => false,
        };
    }

    /// isWhitespaceUnicode checks if a codepoint is Unicode whitespace.
    fn isWhitespaceUnicode(codepoint: u21) bool {
        return switch (codepoint) {
            // Unicode whitespace characters
            0x0009, // CHARACTER TABULATION
            0x000A, // LINE FEED
            0x000B, // LINE TABULATION
            0x000C, // FORM FEED
            0x000D, // CARRIAGE RETURN
            0x0020, // SPACE
            0x0085, // NEXT LINE
            0x00A0, // NO-BREAK SPACE
            0x1680, // OGHAM SPACE MARK
            0x2000...0x200A, // EN QUAD through HAIR SPACE
            0x2028, // LINE SEPARATOR
            0x2029, // PARAGRAPH SEPARATOR
            0x202F, // NARROW NO-BREAK SPACE
            0x205F, // MEDIUM MATHEMATICAL SPACE
            0x3000, // IDEOGRAPHIC SPACE
            => true,
            else => false,
        };
    }

    /// advanceCodepoint increments the current index by the length of the next codepoint.
    fn advanceCodepoint(self: *Self) !void {
        if (self.isAtEnd()) return;

        const len = try unicode.utf8ByteSequenceLength(self.source[self.current]);
        if (self.current + @as(usize, len) > self.source.len) {
            return error.InvalidUtf8;
        }

        self.current += @as(usize, len);
        self.column += 1;
    }

    /// peekCodepoint gets the Unicode codepoint at the current position.
    fn peekCodepoint(self: *const Self) !u21 {
        if (self.isAtEnd()) {
            return 0;
        }

        const len = try unicode.utf8ByteSequenceLength(self.source[self.current]);
        if (self.current + len > self.source.len) {
            return error.InvalidUtf8;
        }

        return try unicode.utf8Decode(self.source[self.current .. self.current + len]);
    }

    /// peekNextCodepoint peeks at the codepoint just beyond the current position.
    fn peekNextCodepoint(self: *Self) !u21 {
        if (self.isAtEnd()) return 0;

        const len = try unicode.utf8ByteSequenceLength(self.source[self.current]);
        if (self.current + len >= self.source.len) {
            return 0;
        }

        const next_pos = self.current + len;
        const next_len = try unicode.utf8ByteSequenceLength(self.source[next_pos]);
        if (next_pos + next_len > self.source.len) {
            return error.InvalidUtf8;
        }

        return try unicode.utf8Decode(self.source[next_pos .. next_pos + next_len]);
    }

    /// isAtEnd returns true when the current position of the scanner
    /// has reached the end of the source code.
    fn isAtEnd(self: *const Self) bool {
        return self.current >= self.source.len;
    }

    /// string creates a string token at the current position with Unicode support.
    fn string(self: *Self) ScanResult {
        const startColumn = self.column - 1; // Account for opening quote

        while (!self.isAtEnd()) {
            const codepoint = self.peekCodepoint() catch {
                return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 in string literal", null);
            };

            if (codepoint == '"') break;

            if (codepoint == '\n') {
                self.line += 1;
                self.lineStart = self.current;
                self.column = 1;
            }

            self.advanceCodepoint() catch {
                return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 in string literal", null);
            };
        }

        // must have run out of source code.
        if (self.isAtEnd()) {
            return self.makeError(ScanError.ErrorKind.UnterminatedString, "Unterminated string literal", null);
        }

        const closingQuote = self.peekCodepoint() catch {
            return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 at end of string", null);
        };

        if (closingQuote != '"') {
            return self.makeError(ScanError.ErrorKind.UnterminatedString, "Unterminated string literal", null);
        }

        // skip over the closing quote.
        self.advanceCodepoint() catch {
            return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 after string", null);
        };

        return ScanResult.newToken(self.makeStringToken(startColumn));
    }

    /// number creates a number token.
    fn number(self: *Self) ScanResult {
        while (!self.isAtEnd()) {
            const codepoint = self.peekCodepoint() catch {
                return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 in number literal", null);
            };

            if (!isDigit(codepoint)) break;

            self.advanceCodepoint() catch {
                return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 in number literal", null);
            };
        }

        const periodCp = self.peekCodepoint() catch 0;
        if (periodCp != '.') {
            return ScanResult.newToken(self.makeTokenWithColumn(TokenType.Number, self.column));
        }

        const nextCp = self.peekNextCodepoint() catch 0;
        if (!isDigit(nextCp)) {
            // we assume that we have a period but no trailing numbers
            // which is invalid syntax.
            return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid number format", periodCp);
        }

        // Advance over the period.
        self.advanceCodepoint() catch {
            return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 in decimal number", null);
        };

        while (!self.isAtEnd()) {
            const codepoint = self.peekCodepoint() catch {
                return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 in decimal number", null);
            };

            if (!isDigit(codepoint)) break;

            self.advanceCodepoint() catch {
                return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 in decimal number", null);
            };
        }

        return ScanResult.newToken(self.makeTokenWithColumn(TokenType.Number, self.column));
    }

    /// identifier handles creation of all other identifier tokens.
    fn identifier(self: *Self) ScanResult {
        while (!self.isAtEnd()) {
            const codePoint = self.peekCodepoint() catch {
                return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 sequence", null);
            };
            if (isAlphaUnicode(codePoint) or isDigit(codePoint)) {
                self.advanceCodepoint() catch {
                    return self.makeError(ScanError.ErrorKind.InvalidUtf8, "Invalid UTF-8 sequence", null);
                };
            } else {
                break;
            }
        }

        const tokenType = self.identifierType();
        const token = self.makeTokenWithColumn(tokenType, self.start);
        return ScanResult.newToken(token);
    }

    /// identifierType looks up if the identifier is a reserved word or a user specified
    /// identifier for a variable name and produces the correct TokenType.
    fn identifierType(self: *Self) TokenType {
        if (ReservedWords.get(self.source[self.start..self.current])) |reserved| {
            return reserved;
        }

        return TokenType.Identifier;
    }

    /// isDigit checks a codepoint to see if it is between '0' and '9'.
    fn isDigit(codepoint: u21) bool {
        return '0' <= codepoint and codepoint <= '9';
    }
};

const ReservedWords = std.StaticStringMap(TokenType).initComptime(.{
    .{ "and", TokenType.And },
    .{ "class", TokenType.Class },
    .{ "else", TokenType.Else },
    .{ "false", TokenType.False },
    .{ "for", TokenType.For },
    .{ "fun", TokenType.Fun },
    .{ "if", TokenType.If },
    .{ "nil", TokenType.Nil },
    .{ "or", TokenType.Or },
    .{ "print", TokenType.Print },
    .{ "return", TokenType.Return },
    .{ "super", TokenType.Super },
    .{ "this", TokenType.This },
    .{ "true", TokenType.True },
    .{ "let", TokenType.Let },
    .{ "while", TokenType.While },
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
    try expect(try scanner.peekCodepoint() == 'h');

    scanner.current = 4;
    try expect(try scanner.peekCodepoint() == 'o');

    scanner.current = 100;
    try expect(try scanner.peekCodepoint() == 0);
}

test "scanner peeks at the next character" {
    var scanner = Scanner.new("hello world");
    try expect(try scanner.peekNextCodepoint() == 'e');

    scanner.current = 4;
    try expect(try scanner.peekNextCodepoint() == ' ');

    scanner.current = 100;
    try expect(try scanner.peekNextCodepoint() == 0);
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
    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(token.tokenType == TokenType.LeftParen);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "(", token.lexeme));
}

test "scanToken should create TokenType.RightParen" {
    var scanner = Scanner.new(")");
    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(token.tokenType == TokenType.RightParen);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, ")", token.lexeme));
}

test "scanToken should create TokenType.LeftBrace" {
    var scanner = Scanner.new("{");
    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(token.tokenType == TokenType.LeftBrace);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "{", token.lexeme));
}

test "scanToken should create TokenType.RightBrace" {
    var scanner = Scanner.new("}");
    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(token.tokenType == TokenType.RightBrace);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "}", token.lexeme));
}

test "scanToken should create TokenType.LeftBracket" {
    var scanner = Scanner.new("[");
    const result = scanner.scanToken();
    const token = result.unwrap();

    try expect(token.tokenType == TokenType.LeftBracket);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "[", token.lexeme));
}

test "scanToken should create TokenType.RightBracket" {
    var scanner = Scanner.new("]");
    const result = scanner.scanToken();
    const token = result.unwrap();

    try expect(token.tokenType == TokenType.RightBracket);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "]", token.lexeme));
}

test "scanToken should create TokenType.Comma" {
    var scanner = Scanner.new(",");
    const result = scanner.scanToken();
    const token = result.unwrap();

    try expect(token.tokenType == TokenType.Comma);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, ",", token.lexeme));
}

test "scanToken should create TokenType.Period" {
    var scanner = Scanner.new(".");
    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(token.tokenType == TokenType.Period);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, ".", token.lexeme));
}

test "scanToken should create TokenType.Semicolon" {
    var scanner = Scanner.new(";");
    const result = scanner.scanToken();
    const token = result.unwrap();

    try expect(token.tokenType == TokenType.Semicolon);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, ";", token.lexeme));
}

test "scanToken should create TokenType.Plus" {
    var scanner = Scanner.new("+");
    const result = scanner.scanToken();
    const token = result.unwrap();

    try expect(token.tokenType == TokenType.Plus);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "+", token.lexeme));
}

test "scanToken should create TokenType.PlusEqual" {
    var scanner = Scanner.new("+=");
    const result = scanner.scanToken();
    const token = result.unwrap();

    try expect(token.tokenType == TokenType.PlusEqual);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "+=", token.lexeme));
}

test "scanToken should create TokenType.Minus" {
    var scanner = Scanner.new("-");
    const result = scanner.scanToken();
    const token = result.unwrap();

    try expect(token.tokenType == TokenType.Minus);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "-", token.lexeme));
}

test "scanToken should create TokenType.MinusEqual" {
    var scanner = Scanner.new("-=");
    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(token.tokenType == TokenType.MinusEqual);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "-=", token.lexeme));
}

test "scanToken should create TokenType.Star" {
    var scanner = Scanner.new("*");
    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(token.tokenType == TokenType.Star);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "*", token.lexeme));
}

test "scanToken should create TokenType.StarEqual" {
    var scanner = Scanner.new("*=");
    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(token.tokenType == TokenType.StarEqual);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "*=", token.lexeme));
}

test "scanToken should create TokenType.Slash" {
    var scanner = Scanner.new("/");
    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(token.tokenType == TokenType.Slash);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "/", token.lexeme));
}

test "scanToken should create TokenType.SlashEqual" {
    var scanner = Scanner.new("/=");
    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(token.tokenType == TokenType.SlashEqual);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "/=", token.lexeme));
}

test "scanToken should create TokenType.Greater" {
    var scanner = Scanner.new(">");
    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(token.tokenType == TokenType.Greater);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, ">", token.lexeme));
}

test "scanToken should create TokenType.GreaterEqual" {
    var scanner = Scanner.new(">=");
    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(token.tokenType == TokenType.GreaterEqual);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, ">=", token.lexeme));
}

test "scanToken should create TokenType.Less" {
    var scanner = Scanner.new("<");
    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(token.tokenType == TokenType.Less);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "<", token.lexeme));
}

test "scanToken should create TokenType.LessEqual" {
    var scanner = Scanner.new("<=");
    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(token.tokenType == TokenType.LessEqual);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "<=", token.lexeme));
}

test "scanToken should create TokenType.Bang" {
    var scanner = Scanner.new("!");
    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(token.tokenType == TokenType.Bang);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "!", token.lexeme));
}

test "scanToken should create TokenType.BangEqual" {
    var scanner = Scanner.new("!=");
    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(token.tokenType == TokenType.BangEqual);
    try expect(token.line == 1);
    try expect(std.mem.eql(u8, "!=", token.lexeme));
}

test "scanToken should handle unknown character errors" {
    var scanner = Scanner.new("@");
    const result = scanner.scanToken();
    const err = result.unwrapErr();
    try expect(err.kind == ScanError.ErrorKind.UnexpectedCharacter);
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
        try expect(Scanner.isAlphaUnicode(@intCast(a)));
    }

    // 97 - 122 represents ASCII lowercase letters.
    for (97..123) |a| {
        try expect(Scanner.isAlphaUnicode(@intCast(a)));
    }

    try expect(Scanner.isAlphaUnicode('_'));

    // non-alpha
    for (0..65) |n| {
        try expect(!Scanner.isAlphaUnicode(@intCast(n)));
    }

    for (91..95) |n| {
        try expect(!Scanner.isAlphaUnicode(@intCast(n)));
    }

    try expect(!Scanner.isAlphaUnicode(96));

    for (123..128) |n| {
        try expect(!Scanner.isAlphaUnicode(@intCast(n)));
    }
}

test "number function should scan numbers" {
    var scanner = Scanner.new("123");
    var result = scanner.scanToken();
    var token = result.unwrap();
    try expect(std.mem.eql(u8, token.lexeme, "123"));
    try expect(token.line == 1);
    try expect(token.tokenType == TokenType.Number);

    scanner = Scanner.new("123.0");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(std.mem.eql(u8, token.lexeme, "123.0"));
    try expect(token.line == 1);
    try expect(token.tokenType == TokenType.Number);

    scanner = Scanner.new("123.456 other");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(std.mem.eql(u8, token.lexeme, "123.456"));
    try expect(token.line == 1);
    try expect(token.tokenType == TokenType.Number);

    scanner = Scanner.new("123."); // invalid number
    result = scanner.scanToken();
    try expect(result.isErr());
}

test "string function should scan single line strings" {
    var scanner = Scanner.new("\"I am a string.\"");
    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(std.mem.eql(u8, "I am a string.", token.lexeme));
    try expect(token.line == 1);
    try expect(token.tokenType == TokenType.String);
}

test "identifier function should handle keywords and other identifiers" {
    var scanner = Scanner.new("and");
    var result = scanner.scanToken();
    var token = result.unwrap();
    try expect(token.tokenType == TokenType.And);

    scanner = Scanner.new("class");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(token.tokenType == TokenType.Class);

    scanner = Scanner.new("else");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(token.tokenType == TokenType.Else);

    scanner = Scanner.new("false");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(token.tokenType == TokenType.False);

    scanner = Scanner.new("for");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(token.tokenType == TokenType.For);

    scanner = Scanner.new("fun");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(token.tokenType == TokenType.Fun);

    scanner = Scanner.new("if");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(token.tokenType == TokenType.If);

    scanner = Scanner.new("nil");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(token.tokenType == TokenType.Nil);

    scanner = Scanner.new("or");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(token.tokenType == TokenType.Or);

    scanner = Scanner.new("print");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(token.tokenType == TokenType.Print);

    scanner = Scanner.new("return");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(token.tokenType == TokenType.Return);

    scanner = Scanner.new("super");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(token.tokenType == TokenType.Super);

    scanner = Scanner.new("this");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(token.tokenType == TokenType.This);

    scanner = Scanner.new("true");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(token.tokenType == TokenType.True);

    scanner = Scanner.new("let");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(token.tokenType == TokenType.Let);

    scanner = Scanner.new("while");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(token.tokenType == TokenType.While);

    scanner = Scanner.new("myThing123");
    result = scanner.scanToken();
    token = result.unwrap();
    try expect(token.tokenType == TokenType.Identifier);
    try expect(std.mem.eql(u8, token.lexeme, "myThing123"));
}

// Tests for Unicode support
test "unicode identifier scanning" {
    const source = "变量 = 42; // Chinese variable name";
    var scanner = Scanner.new(source);

    const result1 = scanner.scanToken();
    const token1 = result1.unwrap();
    try expect(token1.tokenType == TokenType.Identifier);
    try expect(std.mem.eql(u8, token1.lexeme, "变量"));

    const result2 = scanner.scanToken();
    const token2 = result2.unwrap();
    try expect(token2.tokenType == TokenType.Equal);

    const result3 = scanner.scanToken();
    const token3 = result3.unwrap();
    try expect(token3.tokenType == TokenType.Number);
    try expect(std.mem.eql(u8, token3.lexeme, "42"));
}

test "unicode string literals" {
    const source = "\"Hello, 世界! 🌍\"";
    var scanner = Scanner.new(source);

    const result = scanner.scanToken();
    const token = result.unwrap();
    try expect(token.tokenType == TokenType.String);
    try expect(std.mem.eql(u8, token.lexeme, "Hello, 世界! 🌍"));
}

test "unicode whitespace handling" {
    const source = "let\u{2000}x\u{3000}=\u{00A0}42"; // Various Unicode spaces
    var scanner = Scanner.new(source);

    const result1 = scanner.scanToken();
    try expect(result1.unwrap().tokenType == TokenType.Let);

    const result2 = scanner.scanToken();
    try expect(result2.unwrap().tokenType == TokenType.Identifier);
    try expect(std.mem.eql(u8, result2.unwrap().lexeme, "x"));

    const result3 = scanner.scanToken();
    try expect(result3.unwrap().tokenType == TokenType.Equal);
}

// Tests for ScanResult pattern
test "scan result success" {
    const source = "let x = 42;";
    var scanner = Scanner.new(source);

    const result1 = scanner.scanToken();
    try expect(result1.isOk());
    try expect(result1.unwrap().tokenType == TokenType.Let);

    const result2 = scanner.scanToken();
    try expect(result2.isOk());
    try expect(result2.unwrap().tokenType == TokenType.Identifier);
}

test "scan result error handling" {
    const source = "let x = @;"; // @ is unexpected
    var scanner = Scanner.new(source);

    // Skip to the error
    _ = scanner.scanToken(); // let
    _ = scanner.scanToken(); // x
    _ = scanner.scanToken(); // =

    const result = scanner.scanToken(); // @
    try expect(result.isErr());

    const err = result.unwrapErr();
    try expect(err.kind == ScanError.ErrorKind.UnexpectedCharacter);
    try expect(err.codepoint.? == '@');
}

test "unicode identifier scanning with result" {
    const source = "变量 = 42;";
    var scanner = Scanner.new(source);

    const result1 = scanner.scanToken();
    try expect(result1.isOk());
    const token1 = result1.unwrap();
    try expect(token1.tokenType == TokenType.Identifier);
    try expect(std.mem.eql(u8, token1.lexeme, "变量"));

    const result2 = scanner.scanToken();
    try expect(result2.isOk());
    try expect(result2.unwrap().tokenType == TokenType.Equal);
}

test "unterminated string error" {
    const source = "\"Hello, world";
    var scanner = Scanner.new(source);

    const result = scanner.scanToken();
    try expect(result.isErr());

    const err = result.unwrapErr();
    try expect(err.kind == ScanError.ErrorKind.UnterminatedString);
}

test "error formatting" {
    var buffer: [256]u8 = undefined;
    const err = ScanError{
        .kind = ScanError.ErrorKind.UnexpectedCharacter,
        .line = 5,
        .column = 10,
        .message = "Unexpected character",
        .codepoint = '@',
    };

    const formatted = try std.fmt.bufPrint(buffer[0..], "{}", .{err});
    try expect(std.mem.indexOf(u8, formatted, "[line 5:10]") != null);
    try expect(std.mem.indexOf(u8, formatted, "('@')") != null);
}