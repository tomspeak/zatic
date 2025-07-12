const std = @import("std");
const Allocator = std.mem.Allocator;

const PostConfig = struct {
    url: []const u8,
    date: []const u8,
    title: []const u8,
    published: bool,
};
const ConfigOptions = enum { url, date, title, published, unknown };

const Post = struct {
    config: PostConfig,
    content: [:0]u8,
    html: []u8,
};

const Token = struct {
    tag: Tag,
    loc: Loc,

    pub fn dump(self: *const Token) void {
        std.debug.print("tag: {s} start: {d} end: {d}\n", .{ @tagName(self.tag), self.loc.start, self.loc.end });
    }

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const Tag = enum {
        invalid,
        string_literal,
        hashtag,
        quote,
        asterisk,
        underscore,
        horizontal_rule,
        new_line,
        eof,

        pub fn lexeme(tag: Tag) ?[]const u8 {
            return switch (tag) {
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

        pub fn symbol(tag: Tag) []const u8 {
            return tag.lexeme() orelse switch (tag) {
                .invalid => "invalid token",
                .string_literal => "a string literal",
                .eof => "EOF",
                .new_line => "\\n",
                else => unreachable,
            };
        }
    };
};

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    index: usize,

    pub fn dump(self: *Tokenizer, token: *const Token) void {
        std.debug.print("{s} \"{s}\"\n", .{ @tagName(token.tag), self.buffer[token.loc.start..token.loc.end] });
    }

    pub fn init(buffer: [:0]const u8) Tokenizer {
        return .{
            .buffer = buffer,
            .index = 0,
        };
    }

    const State = enum { start, string_literal, hashtag, horizontal_rule, invalid, new_line };

    pub fn next(self: *Tokenizer) Token {
        var result: Token = .{
            .tag = undefined,
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
                            .tag = .eof,
                            .loc = .{
                                .start = self.index,
                                .end = self.index,
                            },
                        };
                    } else {
                        continue :state .invalid;
                    }
                },
                ' ', '\t' => {
                    self.index += 1;
                    result.loc.start = self.index;
                    continue :state .start;
                },
                '\n', '\r' => {
                    result.tag = .new_line;
                    result.loc.start = self.index;
                    continue :state .new_line;
                },
                '#' => {
                    result.tag = .hashtag;
                    result.loc.start = self.index;
                    continue :state .hashtag;
                },
                // TODO: parsing bug, need to check that it's 3 --- in a row
                '-' => {
                    result.tag = .horizontal_rule;
                    result.loc.start = self.index;
                    continue :state .horizontal_rule;
                },
                '>' => {
                    result.tag = .quote;
                    self.index += 1;
                },
                '*' => {
                    result.tag = .asterisk;
                    self.index += 1;
                },
                '_' => {
                    result.tag = .underscore;
                    self.index += 1;
                },
                else => {
                    result.tag = .string_literal;
                    result.loc.start = self.index;
                    continue :state .string_literal;
                },
            },

            .invalid => {
                std.debug.print("stepping into invalid sequence\n", .{});
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => if (self.index == self.buffer.len) {
                        std.debug.print("==== failed at invalid switch, deemed to be 0 and end of file ===", .{});
                        result.tag = .invalid;
                    },
                    else => {
                        std.debug.print("==== failed at invalid ELSE: {any}\n", .{self.buffer[self.index]});
                        continue :state .invalid;
                    },
                }
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
                            std.debug.print("string literal invalid state, but we are not at EOF\n", .{});
                            continue :state .invalid;
                        }
                    },
                    '*', '_' => {},
                    '\n', '\r' => {},
                    else => continue :state .string_literal,
                }
            },
        }

        result.loc.end = self.index;
        return result;
    }
};

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

const Node = struct {
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
};

const Parser = struct {
    buf: [:0]const u8,
    tokens: []Token,
    index: usize,

    const Self = @This();

    pub fn init(buf: [:0]const u8, tokens: []Token) Self {
        return .{ .buf = buf, .tokens = tokens, .index = 0 };
    }

    pub fn parse(self: *Self, allocator: Allocator) !Node {
        std.debug.print("==== parsing ==== \n", .{});
        var root = Node{
            .kind = .Document,
            .data = .{ .Document = std.ArrayListUnmanaged(Node).empty },
        };

        while (self.index < self.tokens.len - 1) {
            const t = self.tokens[self.index];

            std.debug.print("{s}\t{s}\t{any}..{any}\n", .{ t.tag.symbol(), t.tag.lexeme() orelse "", t.loc.start, t.loc.end });

            switch (t.tag) {
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
                    if (nt.tag != Token.Tag.string_literal) {
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

                    self.eat_token();
                },
                .quote => {
                    const nt = self.peek(1) orelse @panic("quote must be followed by a token, but got null");
                    if (nt.tag != Token.Tag.string_literal) {
                        @panic("quote must be followed by a string literal");
                    }
                    const content = self.buf[nt.loc.start..nt.loc.end];
                    try root.data.Document.append(allocator, Node{ .kind = .Quote, .data = .{ .Quote = content } });

                    self.eat_token();
                },
                .string_literal => {
                    const p = try self.parse_paragraph(allocator);
                    try root.data.Document.append(allocator, p);
                    // const content = self.buf[t.loc.start..t.loc.end];
                    // try root.data.Document.append(allocator, Node{ .kind = .Paragraph, .data = .{ .Paragraph = content } });
                    // self.eat_token();
                },
                .horizontal_rule => {
                    try root.data.Document.append(allocator, Node{ .kind = .HorizontalRule, .data = .{ .HorizontalRule = {} } });
                    self.eat_token();
                },
                .new_line => {
                    self.eat_token();
                },
                else => {
                    @panic("unhandled AST item");
                },
            }
        }

        return root;
    }

    fn parse_paragraph(self: *Self, allocator: Allocator) !Node {
        var children = std.ArrayListUnmanaged(Node).empty;

        while (self.index < self.tokens.len) {
            const t = self.tokens[self.index];

            if (t.tag == Token.Tag.eof) {
                self.eat_token();
                break;
            }

            switch (t.tag) {
                .new_line => {
                    self.eat_token();
                    break;
                },
                .string_literal => {
                    const content = self.buf[t.loc.start..t.loc.end];
                    try children.append(allocator, Node{ .kind = .Text, .data = .{ .Text = content } });
                    self.eat_token();
                },
                .asterisk => {
                    var nt = self.next();
                    if (nt.tag != Token.Tag.asterisk) {
                        @panic("asterisk must be double-asterisk");
                    }

                    nt = self.next();
                    if (nt.tag != Token.Tag.string_literal) {
                        @panic("double-asterisk must be followed by a string literal");
                    }

                    const content = self.buf[nt.loc.start..nt.loc.end];
                    try children.append(allocator, Node{ .kind = .Strong, .data = .{ .Strong = content } });

                    self.eat_token();
                    self.eat_until_not(Token.Tag.asterisk);
                },
                .underscore => {
                    var nt = self.next();
                    if (nt.tag != Token.Tag.string_literal) {
                        @panic("underscore must be followed by a string literal");
                    }

                    const content = self.buf[nt.loc.start..nt.loc.end];
                    try children.append(allocator, Node{ .kind = NodeKind.Emphasis, .data = .{ .Emphasis = content } });

                    nt = self.next();
                    if (nt.tag != Token.Tag.underscore) {
                        @panic("_{content} must be followed by a closing _");
                    }
                    self.eat_until_not(Token.Tag.underscore);
                },
                else => {
                    @panic("what is this case? maybe we just break insted");
                },
            }
        }

        return Node{
            .kind = .Paragraph,
            .data = .{ .Paragraph = children },
        };
    }

    fn next(self: *Self) Token {
        self.index += 1;
        return self.tokens[self.index];
    }

    fn peek(self: *Self, offset: usize) ?Token {
        const i = self.index + offset;
        return if (i < self.tokens.len) self.tokens[i] else null;
    }

    fn eat_token(self: *Self) void {
        self.index += 1;
    }

    fn eat_until_not(self: *Self, token: Token.Tag) void {
        while (self.tokens[self.index].tag == token) {
            self.index += 1;
        }
    }
};

fn renderHtml(writer: anytype, node: Node) !void {
    switch (node.kind) {
        .Document => {
            const children = node.data.Document;
            try writer.print("<div>", .{});
            for (children.items) |child| {
                try renderHtml(writer, child);
            }
            try writer.print("</div>", .{});
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
            try writer.print("<strong>{s}</strong>\n", .{content});
        },
        .Emphasis => {
            const content = node.data.Emphasis;
            try writer.print("<i>{s}</i>\n", .{content});
        },
        .Paragraph => {
            const children = node.data.Paragraph;
            try writer.print("<p>", .{});
            for (children.items) |child| {
                try renderHtml(writer, child);
            }
            try writer.print("</p>\n", .{});
        },
        .Quote => {
            const content = node.data.Quote;
            try writer.print("<blockquote>{s}</blockquote>\n", .{content});
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

pub fn parse(allocator: Allocator, file_path: []const u8) !void {
    const buf = try std.fs.cwd().readFileAllocOptions(allocator, file_path, 4096, null, @alignOf(u8), 0);
    defer allocator.free(buf);

    var post = Post{
        .content = buf,
        .config = undefined,
        .html = undefined,
    };

    const fm_index = try parse_frontmatter_into_config(&post, buf);
    const content = buf[fm_index..];

    const tokens = try parse_content(allocator, content);

    var parser = Parser.init(content, tokens);
    const ast = try parser.parse(allocator);
    const stdout = std.io.getStdOut().writer();
    _ = try renderHtml(stdout, ast);
}

fn parse_content(allocator: Allocator, buf: [:0]const u8) ![]Token {
    var tokenizer = Tokenizer.init(buf);
    var tokens = std.ArrayList(Token).init(allocator);

    while (true) {
        const t = tokenizer.next();

        std.debug.print("{s}: {any} : {any}|{any} = {s}\n", .{ t.tag.symbol(), t.tag.lexeme(), t.loc.start, t.loc.end, buf[t.loc.start..t.loc.end] });
        try tokens.append(t);

        if (t.tag == .eof or t.tag == .invalid) {
            break;
        }
    }

    return tokens.toOwnedSlice();
}

pub fn parse_frontmatter_into_config(post: *Post, buf: []u8) !usize {
    const delim = "=!!!=";

    const pos = std.mem.indexOf(u8, buf, delim) orelse return error.NoFrontMatterFound;
    const fm = buf[0..pos];

    var config: PostConfig = .{
        .url = undefined,
        .date = undefined,
        .title = undefined,
        .published = undefined,
    };

    var lines = std.mem.splitScalar(u8, fm, '\n');
    while (lines.next()) |l| {
        var kv = std.mem.splitScalar(u8, l, ':');
        const k = std.mem.trim(u8, kv.next() orelse continue, " \t");
        const v = std.mem.trim(u8, kv.next() orelse continue, " \t");
        const opt = std.meta.stringToEnum(ConfigOptions, k) orelse .unknown;

        switch (opt) {
            .url => config.url = v,
            .date => config.date = v,
            .title => config.title = v,
            .published => config.published = eql(v, "true"),
            .unknown => {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("error: unknown frontmatter key {s}\n", .{k});
                @panic("passed unknown frontmatter key");
            },
        }
    }

    post.*.config = config;

    return pos + delim.len;
}

inline fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

test "basic tokenizer" {
    const allocator = std.testing.allocator;
    const content: [:0]const u8 =
        \\# hello
        \\how are *you*?
    ;
    const tokens = try parse_content(allocator, content);
    defer allocator.free(tokens);

    const expected_tags = [_]Token.Tag{ .hashtag, .string_literal, .new_line, .string_literal, .asterisk, .string_literal, .asterisk, .string_literal, .eof };

    var actual_tags: [9]Token.Tag = undefined;
    for (tokens, 0..) |tok, i| {
        tok.dump();
        actual_tags[i] = tok.tag;
    }

    try std.testing.expectEqualSlices(Token.Tag, &expected_tags, &actual_tags);
}
