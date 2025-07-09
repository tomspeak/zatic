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
    Paragraph,
    Heading,
    Quote,
    Text,
    Emphasis,
    Strong,
    HorizontalRule,
};

const Node = struct {
    kind: NodeKind,
    content: ?[]const u8 = null,
    children: std.ArrayList(Node),
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
            .children = std.ArrayList(Node).init(allocator),
        };

        for (self.tokens) |t| {
            std.debug.print("{s}\t{s}\t{any}..{any}\n", .{ t.tag.symbol(), t.tag.lexeme() orelse "", t.loc.start, t.loc.end });

            switch (t.tag) {
                .hashtag => {
                    // TODO: we need to check that the next token is a string literal, and fail if its not
                    const slice = self.buf[t.loc.start..t.loc.end];
                    try root.children.append(Node{
                        .kind = .Heading,
                        .content = slice,
                        .children = std.ArrayList(Node).init(allocator),
                    });
                },
                .quote => {
                    const slice = self.buf[t.loc.start..t.loc.end];
                    try root.children.append(Node{
                        .kind = .Quote,
                        .content = slice,
                        .children = std.ArrayList(Node).init(allocator),
                    });
                },
                .string_literal => {
                    const slice = self.buf[t.loc.start..t.loc.end];
                    try root.children.append(Node{
                        .kind = .Paragraph,
                        .content = slice,
                        .children = std.ArrayList(Node).init(allocator),
                    });
                },
                .horizontal_rule => {
                    try root.children.append(Node{
                        .kind = .HorizontalRule,
                        .content = null,
                        .children = std.ArrayList(Node).init(allocator),
                    });
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

    fn peek(by: u2, tokens: []const u8) ?Token {
        return if (by < tokens.len) tokens[by] else null;
    }
};

fn renderHtml(node: Node) !void {
    switch (node.kind) {
        .Document => {
            for (node.children.items) |child| {
                std.debug.print("{any} {s}\n", .{ child.kind, child.content.? });
            }
        },
        else => {},
        // .Heading => try writer.print("<h1>{s}</h1>\n", .{node.content.?}),
        // .Paragraph => try writer.print("<p>{s}</p>\n", .{node.content.?}),
        // .Quote => try writer.print("<blockquote>{s}</blockquote>\n", .{node.content.?}),
        // .HorizontalRule => try writer.print("<hr />\n", .{}),
        // else => {},
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
    _ = try renderHtml(ast);
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
