const std = @import("std");

const Token = @import("Token.zig");

const Lexer = @This();

buffer: [:0]const u8,
index: u16,

pub fn dump(self: *Lexer, token: *const Token) void {
    std.debug.print("{s} \"{s}\"\n", .{ @tagName(token.tag), self.buffer[token.loc.start..token.loc.end] });
}

pub fn init(buffer: [:0]const u8) Lexer {
    return .{
        .buffer = buffer,
        .index = 0,
    };
}

pub fn parse(self: *Lexer, allocator: std.mem.Allocator) !std.ArrayListUnmanaged(Token) {
    var tokens = std.ArrayListUnmanaged(Token).empty;

    while (true) {
        const t = self.next();
        try tokens.append(allocator, t);

        if (t.ttype == .eof or t.ttype == .invalid) {
            break;
        }
    }

    return tokens;
}

const State = enum { start, string_literal, hashtag, horizontal_rule, new_line };

fn next(self: *Lexer) Token {
    var result: Token = .{
        .ttype = undefined,
        .loc = .{
            .start = self.index,
            .end = undefined,
        },
    };

    state: switch (State.start) {
        .start => switch (self.buffer[self.index]) {
            0 => {
                if (self.index == self.buffer.len) {
                    return .{
                        .ttype = .eof,
                        .loc = .{
                            .start = self.index,
                            .end = self.index,
                        },
                    };
                }
            },
            ' ', '\t' => {
                result.ttype = .string_literal;
                result.loc.start = self.index;
                continue :state .string_literal;
            },
            '\n', '\r' => {
                result.ttype = .new_line;
                result.loc.start = self.index;
                continue :state .new_line;
            },
            '#' => {
                result.ttype = .hashtag;
                result.loc.start = self.index;
                continue :state .hashtag;
            },
            // TODO: parsing bug, need to check that it's 3 --- in a row
            '-' => {
                result.ttype = .horizontal_rule;
                result.loc.start = self.index;
                continue :state .horizontal_rule;
            },
            '>' => {
                result.ttype = .quote;
                self.index += 1;
            },
            '*' => {
                result.ttype = .asterisk;
                self.index += 1;
            },
            '_' => {
                result.ttype = .underscore;
                self.index += 1;
            },
            '[' => {
                result.ttype = .lbracket;
                self.index += 1;
            },
            ']' => {
                result.ttype = .rbracket;
                self.index += 1;
            },
            '(' => {
                result.ttype = .lparen;
                self.index += 1;
            },
            ')' => {
                result.ttype = .rparen;
                self.index += 1;
            },
            else => {
                result.ttype = .string_literal;
                result.loc.start = self.index;
                continue :state .string_literal;
            },
        },

        .new_line => {
            self.index += 1;
            switch (self.buffer[self.index]) {
                '\n', '\r' => {
                    continue :state .new_line;
                },
                else => {},
            }
        },

        .hashtag => {
            self.index += 1;
            switch (self.buffer[self.index]) {
                '#' => continue :state .hashtag,
                else => {},
            }
        },

        .horizontal_rule => {
            self.index += 1;
            switch (self.buffer[self.index]) {
                '-' => continue :state .horizontal_rule,
                else => {},
            }
        },

        .string_literal => {
            self.index += 1;
            switch (self.buffer[self.index]) {
                0 => {
                    if (self.index != self.buffer.len) {
                        @panic("string literal invalid state, but we are not at EOF");
                    }
                },
                '*', '_', '[', ']', '(', ')' => {},
                '\n', '\r' => {},
                else => continue :state .string_literal,
            }
        },
    }

    result.loc.end = self.index;
    return result;
}
