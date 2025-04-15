//! lexer reads source code and produces tokens used to generate an ast.

const std = @import("std");
const t = @import("token.zig");

pub const LexError = error{
    TooManyPeriods,
};

/// Lexer is a lexical analyzer used to tokenize source code.
pub const Lexer = struct {
    /// input is the input source code to be analyzed.
    input: []const u8,
    /// position is the current position in the input and
    /// points to the current character under examination.
    position: usize,
    /// readPosition is the position after the current character (position + 1)
    readPosition: usize,
    /// character is the current character under examination.
    character: u8,
    /// lineNumber is the current line of the file that the lexer is on.
    lineNumber: usize,
    /// charPosition is the current x coordinate of the character in the current line.
    charPosition: usize,
    /// fileName is the name of the current file being lexed.
    fileName: []const u8,

    const Self = @This();

    /// init creates a new Lexer.
    ///
    /// Parameters:
    ///  - source: The input source code to be analyzed.
    ///
    /// Returns:
    ///  - Lexer: A new lexer.
    pub fn init(allocator: *std.mem.Allocator, source: []const u8, fileName: []const u8) !*Lexer {
        const lexer = try allocator.create(Lexer);
        lexer.* = Lexer{
            .input = source,
            .position = 0,
            .readPosition = 0,
            .character = 0,
            .lineNumber = 1,
            .charPosition = 0,
            .fileName = fileName,
        };

        lexer.readChar();

        return lexer;
    }

    /// nextToken reads the next token from the source code.
    pub fn nextToken(self: *Self) !t.Token {
        var token: t.Token = .{
            .tokenType = .Illegal,
            .literal = "",
            .charPosition = self.charPosition,
            .lineNumber = self.lineNumber,
            .fileName = self.fileName,
        };

        self.skipWhitespace();
        switch (self.character) {
            '"' => {
                token.tokenType = .String;
                token.literal = self.readString();
            },
            '=' => {
                if (self.peekChar() == '=') {
                    self.readChar();
                    token.tokenType = .EqualEqual;
                    token.literal = "==";
                } else {
                    token = try self.newToken(.Assign, 1);
                }
            },
            '+' => {
                token = try self.newToken(.Plus, 1);
            },
            '-' => {
                token = try self.newToken(.Minus, 1);
            },
            '!' => {
                if (self.peekChar() == '=') {
                    self.readChar();
                    token.tokenType = .BangEqual;
                    token.literal = "!=";
                } else {
                    token = try self.newToken(.Bang, 1);
                }
            },
            '/' => {
                token = try self.newToken(.Slash, 1);
            },
            '*' => {
                token = try self.newToken(.Asterisk, 1);
            },
            '<' => {
                if (self.peekChar() == '=') {
                    self.readChar();
                    token.tokenType = .LessEqual;
                    token.literal = "<=";
                } else {
                    token = try self.newToken(.Less, 1);
                }
            },
            '>' => {
                if (self.peekChar() == '=') {
                    self.readChar();
                    token.tokenType = .GreaterEqual;
                    token.literal = ">=";
                } else {
                    token = try self.newToken(.Greater, 1);
                }
            },
            ';' => {
                token = try self.newToken(.Semicolon, 1);
            },
            ',' => {
                token = try self.newToken(.Comma, 1);
            },
            '(' => {
                token = try self.newToken(.LeftParen, 1);
            },
            ')' => {
                token = try self.newToken(.RightParen, 1);
            },
            '{' => {
                token = try self.newToken(.LeftCurlyBrace, 1);
            },
            '}' => {
                token = try self.newToken(.RightCurlyBrace, 1);
            },
            '[' => {
                token = try self.newToken(.LeftSquareBracket, 1);
            },
            ']' => {
                token = try self.newToken(.RightSquareBracket, 1);
            },
            ':' => {
                token = try self.newToken(.Colon, 1);
            },
            0 => {
                token.literal = "";
                token.tokenType = .Eof;
            },
            else => {
                if (isLetter(self.character)) {
                    const lit = self.readIdentifier();
                    const ttype = t.lookupIdent(lit);
                    return t.Token{
                        .charPosition = self.charPosition,
                        .fileName = self.fileName,
                        .lineNumber = self.lineNumber,
                        .literal = lit,
                        .tokenType = ttype,
                    };
                } else if (isDigit(self.character)) {
                    const lit = try self.readNumber();
                    return t.Token{
                        .charPosition = self.charPosition,
                        .fileName = self.fileName,
                        .lineNumber = self.lineNumber,
                        .literal = lit,
                        .tokenType = .Number,
                    };
                } else {
                    token = try self.newToken(.Illegal, 1);
                }
            },
        }

        self.readChar();

        return token;
    }

    /// skipWhitespace moves the current lexer position over whitespace characters
    /// because whitespace is insignificant in this language.
    fn skipWhitespace(self: *Self) void {
        const whitespace = [_]u8{ ' ', '\r', '\t', '\n' };
        while (true) {
            const idx = std.mem.indexOfScalar(u8, &whitespace, self.character);
            if (idx) |_| {
                self.readChar();
            } else {
                break;
            }
        }
    }

    pub fn readChar(self: *Self) void {
        std.debug.assert(self.readPosition <= self.input.len + 1); // +1 for EOF

        if (self.readPosition >= self.input.len) {
            self.character = 0; // EOF
        } else {
            self.character = self.input[self.readPosition];
        }

        if (self.character == '\n') {
            self.lineNumber += 1;
            self.charPosition = 1;
        } else {
            self.charPosition += 1;
        }

        // Update positions
        self.position = self.readPosition;
        self.readPosition += 1;
    }

    /// peekChar reads the next character to help with multi-character tokens.
    fn peekChar(self: *Self) u8 {
        if (self.readPosition >= self.input.len) {
            return 0;
        }

        return self.input[self.readPosition];
    }

    /// readAsString reads the number of characters required from source as a string.
    fn readAsString(self: *Self, num: usize) []const u8 {
        const start = self.position;
        const end = start + num;

        if (end > self.input.len) {
            std.debug.print("Attempted to read beyond input! start={}, end={}, input.len={}\n", .{ start, end, self.input.len });
            return self.input[start..self.input.len];
        }

        return self.input[start..end];
    }

    /// readString reads a string from the source.
    ///
    /// Returns:
    ///  - []const u8: The string value from the source.
    fn readString(self: *Self) []const u8 {
        const position = self.position + 1;
        while (true) {
            self.readChar();
            if (self.character == '"' or self.character == 0) {
                break;
            }
        }

        return self.input[position..self.position];
    }

    /// readIdentifier reads an identifier from the source code.
    ///
    /// Returns:
    ///  - []const u8: the identifier name.
    fn readIdentifier(self: *Self) []const u8 {
        const position = self.position;
        var isFirst = true;
        while (isValidIdentifier(self.character, isFirst)) {
            self.readChar();
            isFirst = false;
            if (self.character == 0) break;
        }

        return self.input[position..self.position];
    }

    /// readNumber reads a number from the input source code.
    ///
    /// Returns:
    ///  - LexError: returned when parsing the number goes poorly.
    ///  - []const u8: The number as a string.
    fn readNumber(self: *Self) LexError![]const u8 {
        const position = self.position;
        var periodCount: u8 = 0;
        while (isDigit(self.character) or self.character == '.') {
            if (self.character == '.') {
                periodCount += 1;
            }
            self.readChar();
        }

        if (periodCount > 1) {
            return LexError.TooManyPeriods;
        }
        return self.input[position..self.position];
    }

    /// newToken creates a new token of the given token type.
    ///
    /// Parameters:
    ///  - tokenType: The type of token to make.
    ///  - num: The number of characters to read.
    ///
    /// Returns:
    ///  - !t.Token: A new token or an error.
    fn newToken(self: *Self, tokenType: t.TokenType, num: usize) !t.Token {
        const s = self.readAsString(num);
        const tok = t.Token{
            .tokenType = tokenType,
            .literal = s,
            .charPosition = self.charPosition,
            .lineNumber = self.lineNumber,
            .fileName = self.fileName,
        };

        return tok;
    }
};

/// isLetter checks to see if the input character is a letter character.
///
/// Parameters:
///  - char: The character to validate.
///
/// Returns:
///  - bool: True when an ascii character a-z or A-Z, otherwise false.
fn isLetter(char: u8) bool {
    return ('a' <= char and char <= 'z') or ('A' <= char and char <= 'Z');
}

/// isDigit checks to see if the input character is a numeric character.
///
/// Parameters:
///  - char: The character to validate.
///
/// Returns:
///  - bool: True when 0 - 9, otherwise false.
fn isDigit(char: u8) bool {
    return ('0' <= char and char <= '9');
}

/// isValidSpecialCharacter checks to see if the input character is one of the allowed special characters
/// for use as an identifier.
///
/// Parameters:
///  - char: the character to validate.
///
/// Returns:
///  - bool: True when valid, otherwise false.
fn isValidSpecialCharacter(char: u8) bool {
    const validSpecialCharacters = [_]u8{
        '_',
    };
    return std.mem.indexOfScalar(u8, &validSpecialCharacters, char) != null;
}

fn isValidIdentifier(char: u8, isFirst: bool) bool {
    if (isFirst) {
        // Can't start with number.
        return isLetter(char) or isValidSpecialCharacter(char);
    }
    return isLetter(char) or isDigit(char) or isValidSpecialCharacter(char);
}
