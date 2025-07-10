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

// Parsed features:
//  URLs []()
//  Footnotes (TBD)
//  Images

const Token = struct {
    tag: Tag,
    loc: Loc,

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
        underline,
        horizontal_rule,
        eof,

        pub fn lexeme(tag: Tag) ?[]const u8 {
            return switch (tag) {
                .invalid,
                .string_literal,
                .eof,
                => null,

                .quote => ">",
                .hashtag => "#",
                .underline => "_",
                .asterisk => "*",
                .horizontal_rule => "-",
            };
        }

        pub fn symbol(tag: Tag) []const u8 {
            return tag.lexeme() orelse switch (tag) {
                .invalid => "invalid token",
                .string_literal => "a string literal",
                .eof => "EOF",
                else => unreachable,
            };
        }
    };
};

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    index: usize,

    /// For debugging purposes.
    pub fn dump(self: *Tokenizer, token: *const Token) void {
        std.debug.print("{s} \"{s}\"\n", .{ @tagName(token.tag), self.buffer[token.loc.start..token.loc.end] });
    }

    pub fn init(buffer: [:0]const u8) Tokenizer {
        // Skip the UTF-8 BOM if present.
        return .{
            .buffer = buffer,
            .index = 0,
        };
    }

    const State = enum { start, string_literal, hashtag, horizontal_rule, invalid };

    /// After this returns invalid, it will reset on the next newline, returning tokens starting from there.
    /// An eof token will always be returned at the end.
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
                ' ', '\n', '\t', '\r' => {
                    self.index += 1;
                    result.loc.start = self.index;
                    continue :state .start;
                },
                '#' => {
                    result.tag = .hashtag;
                    result.loc.start = self.index;
                    continue :state .hashtag;
                },
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
                // '_' => continue :state .italic,
                else => {
                    result.tag = .string_literal;
                    result.loc.start = self.index;
                    continue :state .string_literal;
                },
            },

            .invalid => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => if (self.index == self.buffer.len) {
                        result.tag = .invalid;
                    },
                    '\n' => result.tag = .invalid,
                    else => continue :state .invalid,
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
                            continue :state .invalid;
                        } else {
                            result.tag = .invalid;
                        }
                    },
                    '\n', '\r', '*' => {},
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
        Heading1: std.ArrayListUnmanaged(Node),
        Heading2: std.ArrayListUnmanaged(Node),
        Heading3: std.ArrayListUnmanaged(Node),
        Heading4: std.ArrayListUnmanaged(Node),
        Heading5: std.ArrayListUnmanaged(Node),
        Heading6: std.ArrayListUnmanaged(Node),
        Emphasis: std.ArrayListUnmanaged(Node),
        Strong: std.ArrayListUnmanaged(Node),
        Quote: []const u8,
        Paragraph: []const u8,
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
            .data = .{ .Document = std.ArrayListUnmanaged(Node){} },
        };

        while (self.index < self.tokens.len - 1) : (self.index += 1) {
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

                    const nt = peek(1, self.tokens) orelse @panic("heading must be followed by a token, but got null");
                    if (nt.tag != Token.Tag.string_literal) {
                        @panic("header must be followed by a string literal");
                    }

                    // Build child: Text node
                    const text_slice = self.buf[nt.loc.start..nt.loc.end];
                    var heading_children = std.ArrayListUnmanaged(Node){};
                    try heading_children.append(allocator, Node{
                        .kind = .Text,
                        .data = .{ .Text = text_slice },
                    });

                    // Build heading node with text as child
                    try root.data.Document.append(allocator, Node{
                        .kind = kind,
                        .data = switch (kind) {
                            .Heading1 => .{ .Heading1 = heading_children },
                            .Heading2 => .{ .Heading2 = heading_children },
                            .Heading3 => .{ .Heading3 = heading_children },
                            .Heading4 => .{ .Heading4 = heading_children },
                            .Heading5 => .{ .Heading5 = heading_children },
                            .Heading6 => .{ .Heading6 = heading_children },
                            else => unreachable,
                        },
                    });

                    self.eat_token();
                },
                .quote => {
                    const content = self.buf[t.loc.start..t.loc.end];
                    try root.data.Document.append(allocator, Node{ .kind = .Quote, .data = .{ .Quote = content } });
                },
                .string_literal => {
                    const content = self.buf[t.loc.start..t.loc.end];
                    try root.data.Document.append(allocator, Node{ .kind = .Paragraph, .data = .{ .Paragraph = content } });
                },
                .horizontal_rule => {
                    try root.data.Document.append(allocator, Node{ .kind = .HorizontalRule, .data = .{ .HorizontalRule = {} } });
                },
                else => {},
            }
        }

        return root;
    }

    fn next(self: *Self) Token {
        self.index += 1;
        return self.tokens[self.index];
    }

    pub fn peek(by: u2, tokens: []const Token) ?Token {
        return if (by < tokens.len) tokens[by] else null;
    }

    fn eat_token(self: *Self) void {
        self.index += 1;
    }
};

fn renderHtml(writer: anytype, node: Node) !void {
    switch (node.kind) {
        .Document => {
            const children = node.data.Document;
            for (children.items) |child| {
                try renderHtml(writer, child);
            }
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

            try writer.print("<h{}>", .{level});
            const children = switch (node.kind) {
                .Heading1 => node.data.Heading1,
                .Heading2 => node.data.Heading2,
                .Heading3 => node.data.Heading3,
                .Heading4 => node.data.Heading4,
                .Heading5 => node.data.Heading5,
                .Heading6 => node.data.Heading6,
                else => unreachable,
            };
            for (children.items) |child| {
                try renderHtml(writer, child);
            }
            try writer.print("</h{}>\n", .{level});
        },
        .Paragraph => {
            const content = node.data.Paragraph;
            try writer.print("<p>{s}</p>\n", .{content});
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
        else => {},
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
