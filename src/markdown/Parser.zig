const std = @import("std");
const Allocator = std.mem.Allocator;

const Token = @import("Token.zig");

const Parser = @This();

buf: [:0]const u8,
tokens: []Token,
index: usize,

const NodeKind = enum {
    Document,
    Heading1,
    Heading2,
    Heading3,
    Heading4,
    Heading5,
    Heading6,
    Emphasis,
    Strong,
    Quote,
    Paragraph,
    HorizontalRule,
    Text,
};

pub const Node = struct {
    kind: NodeKind,
    data: union(NodeKind) {
        Document: std.ArrayListUnmanaged(Node),
        Heading1: []const u8,
        Heading2: []const u8,
        Heading3: []const u8,
        Heading4: []const u8,
        Heading5: []const u8,
        Heading6: []const u8,
        Emphasis: []const u8,
        Strong: []const u8,
        Quote: []const u8,
        Paragraph: std.ArrayListUnmanaged(Node),
        HorizontalRule: void,
        Text: []const u8,
    },

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        switch (self.kind) {
            .Document => {
                for (self.data.Document.items) |*child| {
                    child.deinit(allocator);
                }
                self.data.Document.deinit(allocator);
            },
            .Paragraph => {
                for (self.data.Paragraph.items) |*child| {
                    child.deinit(allocator);
                }
                self.data.Paragraph.deinit(allocator);
            },
            // all other node types just borrow input slices, no heap allocation to clean up
            else => {},
        }
    }
};

pub fn init(buf: [:0]const u8, tokens: []Token) Parser {
    return .{ .buf = buf, .tokens = tokens, .index = 0 };
}

pub fn parse(self: *Parser, allocator: Allocator) !Node {
    std.debug.print("==== parsing ==== \n", .{});
    var root = Node{
        .kind = .Document,
        .data = .{ .Document = std.ArrayListUnmanaged(Node).empty },
    };

    while (self.index < self.tokens.len - 1) {
        const t = self.tokens[self.index];

        std.debug.print("{s}\t{s}\t{any}..{any}\n", .{ t.ttype.symbol(), t.ttype.lexeme() orelse "", t.loc.start, t.loc.end });

        switch (t.ttype) {
            .hashtag => {
                const heading_len = self.buf[t.loc.start..t.loc.end].len;
                const kind: NodeKind = switch (heading_len) {
                    1 => .Heading1,
                    2 => .Heading2,
                    3 => .Heading3,
                    4 => .Heading4,
                    5 => .Heading5,
                    6 => .Heading6,
                    else => unreachable,
                };

                const nt = self.next();
                if (nt.ttype != Token.TokenType.string_literal) {
                    @panic("header must be followed by a string literal");
                }

                const content = self.buf[nt.loc.start..nt.loc.end];

                try root.data.Document.append(allocator, Node{
                    .kind = kind,
                    .data = switch (kind) {
                        .Heading1 => .{ .Heading1 = content },
                        .Heading2 => .{ .Heading2 = content },
                        .Heading3 => .{ .Heading3 = content },
                        .Heading4 => .{ .Heading4 = content },
                        .Heading5 => .{ .Heading5 = content },
                        .Heading6 => .{ .Heading6 = content },
                        else => unreachable,
                    },
                });

                self.eatToken();
            },
            .quote => {
                const nt = self.peek(1) orelse @panic("quote must be followed by a token, but got null");
                if (nt.ttype != Token.TokenType.string_literal) {
                    @panic("quote must be followed by a string literal");
                }
                const content = self.buf[nt.loc.start..nt.loc.end];
                try root.data.Document.append(allocator, Node{ .kind = .Quote, .data = .{ .Quote = content } });

                self.eatToken();
            },
            .string_literal => {
                const p = try self.parseParagraph(allocator);
                try root.data.Document.append(allocator, p);
            },
            .horizontal_rule => {
                try root.data.Document.append(allocator, Node{ .kind = .HorizontalRule, .data = .{ .HorizontalRule = {} } });
                self.eatToken();
            },
            .new_line => {
                self.eatToken();
            },
            else => {
                @panic("unhandled AST item");
            },
        }
    }

    return root;
}

fn parseParagraph(self: *Parser, allocator: Allocator) !Node {
    var children = std.ArrayListUnmanaged(Node).empty;

    while (self.index < self.tokens.len) {
        const t = self.tokens[self.index];

        if (t.ttype == Token.TokenType.eof) {
            self.eatToken();
            break;
        }

        switch (t.ttype) {
            .new_line => {
                self.eatToken();
                break;
            },
            .string_literal => {
                const content = self.buf[t.loc.start..t.loc.end];
                try children.append(allocator, Node{ .kind = .Text, .data = .{ .Text = content } });
                self.eatToken();
            },
            .asterisk => {
                var nt = self.next();
                if (nt.ttype != Token.TokenType.asterisk) {
                    @panic("asterisk must be double-asterisk");
                }

                nt = self.next();
                if (nt.ttype != Token.TokenType.string_literal) {
                    @panic("double-asterisk must be followed by a string literal");
                }

                const content = self.buf[nt.loc.start..nt.loc.end];
                try children.append(allocator, Node{ .kind = .Strong, .data = .{ .Strong = content } });

                self.eatToken();
                self.eatUntilNot(Token.TokenType.asterisk);
            },
            .underscore => {
                var nt = self.next();
                if (nt.ttype != Token.TokenType.string_literal) {
                    @panic("underscore must be followed by a string literal");
                }

                const content = self.buf[nt.loc.start..nt.loc.end];
                try children.append(allocator, Node{ .kind = NodeKind.Emphasis, .data = .{ .Emphasis = content } });

                nt = self.next();
                if (nt.ttype != Token.TokenType.underscore) {
                    @panic("_{content} must be followed by a closing _");
                }
                self.eatUntilNot(Token.TokenType.underscore);
            },
            else => {
                @panic("what is this case? maybe we just break instead");
            },
        }
    }

    return Node{
        .kind = .Paragraph,
        .data = .{ .Paragraph = children },
    };
}

fn next(self: *Parser) Token {
    self.index += 1;
    return self.tokens[self.index];
}

fn peek(self: *Parser, offset: usize) ?Token {
    const i = self.index + offset;
    return if (i < self.tokens.len) self.tokens[i] else null;
}

fn eatToken(self: *Parser) void {
    self.index += 1;
}

fn eatUntilNot(self: *Parser, token: Token.TokenType) void {
    while (self.tokens[self.index].ttype == token) {
        self.index += 1;
    }
}

pub fn write(writer: anytype, node: Parser.Node) !void {
    switch (node.kind) {
        .Document => {
            const children = node.data.Document;
            try writer.print("<div>\n", .{});
            for (children.items) |child| {
                try write(writer, child);
            }
            try writer.print("</div>\n", .{});
        },
        .Heading1, .Heading2, .Heading3, .Heading4, .Heading5, .Heading6 => {
            const level: u3 = switch (node.kind) {
                .Heading1 => 1,
                .Heading2 => 2,
                .Heading3 => 3,
                .Heading4 => 4,
                .Heading5 => 5,
                .Heading6 => 6,
                else => unreachable,
            };

            const content = switch (node.kind) {
                .Heading1 => node.data.Heading1,
                .Heading2 => node.data.Heading2,
                .Heading3 => node.data.Heading3,
                .Heading4 => node.data.Heading4,
                .Heading5 => node.data.Heading5,
                .Heading6 => node.data.Heading6,
                else => unreachable,
            };
            try writer.print("<h{}>{s}</h{}>\n", .{ level, content, level });
        },
        .Strong => {
            const content = node.data.Strong;
            try writer.print("<strong>{s}</strong>", .{content});
        },
        .Emphasis => {
            const content = node.data.Emphasis;
            try writer.print("<i>{s}</i>", .{content});
        },
        .Paragraph => {
            const children = node.data.Paragraph;
            try writer.print("<p>", .{});
            for (children.items) |child| {
                try write(writer, child);
            }
            try writer.print("</p>\n", .{});
        },
        .Quote => {
            const content = node.data.Quote;
            try writer.print("<blockquote>{s}</blockquote>", .{content});
        },
        .HorizontalRule => {
            try writer.print("<hr />\n", .{});
        },
        .Text => {
            const content = node.data.Text;
            try writer.print("{s}", .{content});
        },
    }
}
