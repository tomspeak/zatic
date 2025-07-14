const std = @import("std");

const Token = @This();

ttype: TokenType,
loc: Loc,

pub fn dump(self: *const Token) void {
    std.debug.print("ttype: {s} start: {d} end: {d}\n", .{ @tagName(self.ttype), self.loc.start, self.loc.end });
}

pub const TokenType = enum {
    invalid,
    string_literal,
    hashtag,
    quote,
    asterisk,
    underscore,
    horizontal_rule,
    new_line,
    eof,

    pub fn lexeme(ttype: TokenType) ?[]const u8 {
        return switch (ttype) {
            .invalid,
            .string_literal,
            .eof,
            .new_line,
            => null,

            .quote => ">",
            .hashtag => "#",
            .underscore => "_",
            .asterisk => "*",
            .horizontal_rule => "-",
        };
    }

    pub fn symbol(ttype: TokenType) []const u8 {
        return ttype.lexeme() orelse switch (ttype) {
            .invalid => "invalid token",
            .string_literal => "a string literal",
            .eof => "EOF",
            .new_line => "\\n",
            else => unreachable,
        };
    }
};

pub const Loc = struct {
    start: u16,
    end: u16,
};
