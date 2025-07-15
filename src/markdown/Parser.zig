const std = @import("std");
const Allocator = std.mem.Allocator;

const Token = @import("Token.zig");

const Parser = @This();

buf: [:0]const u8,
tokens: []Token,
index: usize,
line: u16,
errors: std.ArrayListUnmanaged([]const u8),

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
    Url,
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
        Url: struct {
            text: []const u8,
            href: []const u8,
        },
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
    return .{ .buf = buf, .tokens = tokens, .index = 0, .line = 0, .errors = std.ArrayListUnmanaged([]const u8).empty };
}

pub fn deinit(self: *Parser, allocator: Allocator) !void {
    for (self.errors.items) |msg| {
        allocator.free(msg);
    }

    self.errors.deinit(allocator);
}

pub fn parse(self: *Parser, allocator: Allocator) !Node {
    std.debug.print("==== parsing ==== \n", .{});
    var root = Node{
        .kind = .Document,
        .data = .{ .Document = std.ArrayListUnmanaged(Node).empty },
    };

    // TODO: consider while (token != eof) : (self.nextToken()) over index
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

                try self.assertPeek(1, .string_literal);
                const nt = self.next();

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

                self.eat();
            },
            .quote => {
                try self.assertPeek(1, .string_literal);
                const nt = self.next();
                const content = self.buf[nt.loc.start..nt.loc.end];
                try root.data.Document.append(allocator, Node{ .kind = .Quote, .data = .{ .Quote = content } });

                self.eat();
            },
            .horizontal_rule => {
                try root.data.Document.append(allocator, Node{ .kind = .HorizontalRule, .data = .{ .HorizontalRule = {} } });
                self.eat();
            },
            .new_line => {
                self.line += 1;
                self.eat();
            },
            .string_literal => {
                const p = try self.parseParagraph(allocator);
                try root.data.Document.append(allocator, p);
            },
            else => {
                var buf: [128]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "line={d}\tcol={d}\nunsupported TokenType: {s}", .{ self.line, self.index, t.ttype.symbol() }) catch unreachable;
                @panic(msg);
            },
        }
    }

    return root;
}

fn parseParagraph(self: *Parser, allocator: Allocator) !Node {
    var children = std.ArrayListUnmanaged(Node).empty;

    while (self.index < self.tokens.len) {
        const t = self.tokens[self.index];

        if (self.is(.eof)) {
            self.eat();
            break;
        }

        switch (t.ttype) {
            .new_line => {
                self.line += 1;
                self.eat();
                break;
            },
            .asterisk => {
                try self.assertPeek(1, .asterisk);
                var nt = self.next();

                try self.assertPeek(1, .string_literal);
                nt = self.next();

                const content = self.buf[nt.loc.start..nt.loc.end];
                try children.append(allocator, Node{ .kind = .Strong, .data = .{ .Strong = content } });

                try self.assertPeek(1, .asterisk);
                self.eat();
                try self.assertPeek(1, .asterisk);
                self.eat();

                self.eat();
            },
            .underscore => {
                try self.assertPeek(1, .string_literal);
                var nt = self.next();

                const content = self.buf[nt.loc.start..nt.loc.end];
                try children.append(allocator, Node{ .kind = NodeKind.Emphasis, .data = .{ .Emphasis = content } });

                try self.assertPeek(1, .underscore);
                nt = self.next();

                self.eat();
            },
            .lbracket => {
                try self.assertPeek(1, .string_literal);
                const text = self.next();

                try self.assertPeek(1, .rbracket);
                self.eat();

                try self.assertPeek(1, .lparen);
                self.eat();

                try self.assertPeek(1, .string_literal);
                const href = self.next();

                try self.assertPeek(1, .rparen);
                self.eat();

                try children.append(allocator, Node{ .kind = NodeKind.Url, .data = .{ .Url = .{ .href = self.buf[href.loc.start..href.loc.end], .text = self.buf[text.loc.start..text.loc.end] } } });

                self.eat();
            },
            .string_literal => {
                const content = self.buf[t.loc.start..t.loc.end];
                try children.append(allocator, Node{ .kind = .Text, .data = .{ .Text = content } });
                self.eat();
            },
            else => {
                var buf: [128]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "line={d}\tcol={d}\nparseParagraph - unsupported TokenType: {s}", .{ self.line, self.index, t.ttype.symbol() }) catch unreachable;
                @panic(msg);
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

fn is(self: *Parser, ttype: Token.TokenType) bool {
    return self.tokens[self.index].ttype == ttype;
}

fn assertPeek(self: *Parser, offset: usize, ttype: Token.TokenType) !void {
    const i = self.index + offset;
    if (i > self.tokens.len) {
        return error.PeakedPastEOF;
    }

    const t = self.tokens[i];

    if (t.ttype != ttype) {
        try std.io.getStdErr().writer().print(
            "line={d}\tcol={d}\nerror: expected peek token to be TokenType.{s}={c}, got TokenType.{s}={c} instead.\n",
            .{ self.line, self.index, @tagName(ttype), self.buf[self.tokens[self.index].loc.start..self.tokens[self.index].loc.end], @tagName(t.ttype), self.buf[t.loc.start..t.loc.end] },
        );
        return error.MismatchedPeek;
    }
}

fn eat(self: *Parser) void {
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
        .Url => {
            const url = node.data.Url.href;
            const text = node.data.Url.text;

            try writer.print("<a href=\"{s}\">{s}</a>", .{ url, text });
        },
    }
}
