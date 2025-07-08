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
    content: []u8,
    html: []u8,
};

// Parsed features:
//  Title + subtitles (# ## ### ####)
//  paragraphs
//  bold, Italic
//  URLs []()
//  Block quotes >
//  Footnotes (TBD)
//  Images
//  Horizontal lines ---

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
        multiline_string_literal_line,
        hashtag,
        quote,
        asterisk,
        underline,
        eof,

        pub fn lexeme(tag: Tag) ?[]const u8 {
            return switch (tag) {
                .invalid,
                .string_literal,
                .multiline_string_literal_line,
                .eof,
                => null,

                .quote => ">",
                .hashtag => "#",
                .underline => "_",
                .asterisk => "*",
            };
        }

        pub fn symbol(tag: Tag) []const u8 {
            return tag.lexeme() orelse switch (tag) {
                .invalid => "invalid token",
                .string_literal, .multiline_string_literal_line => "a string literal",
                .eof => "EOF",
                else => unreachable,
            };
        }
    };
};

pub const Tokenizer = struct {
    buffer: []const u8,
    index: usize,

    /// For debugging purposes.
    pub fn dump(self: *Tokenizer, token: *const Token) void {
        std.debug.print("{s} \"{s}\"\n", .{ @tagName(token.tag), self.buffer[token.loc.start..token.loc.end] });
    }

    pub fn init(buffer: []const u8) Tokenizer {
        // Skip the UTF-8 BOM if present.
        return .{
            .buffer = buffer,
            .index = 0,
        };
    }

    const State = enum { start, expect_newline, identifier, string_literal, multiline_string_literal_line, asterisk, hashtag, bold, italic, underline, invalid };

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
                '>' => {
                    result.tag = .quote;
                    self.index += 1;
                },
                // '*' => continue :state .asterisk,
                // '_' => continue :state .italic,
                else => {
                    result.tag = .string_literal;
                    result.loc.start = self.index;
                    continue :state .string_literal;
                },
                // else => continue :state .invalid,
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
                    '\n', '\r' => {},
                    '*' => {
                        // how do we break out of here?
                    },
                    // '\\' => continue :state .string_literal_backslash,
                    // 0x01...0x09, 0x0b...0x1f, 0x7f => {
                    //     continue :state .invalid;
                    // },
                    else => continue :state .string_literal,
                }
            },

            else => {},
        }

        result.loc.end = self.index;
        return result;
    }
};

pub fn parse(allocator: Allocator, file_path: []const u8) !void {
    const buf = try std.fs.cwd().readFileAlloc(allocator, file_path, 4096);
    defer allocator.free(buf);

    var post = Post{
        .content = buf,
        .config = undefined,
        .html = undefined,
    };

    const fm_index = try parse_frontmatter(&post, buf);
    const content = buf[fm_index..];

    // std.debug.print("\nclean content:{s}", .{content});

    _ = try parse_content(&post, content);
    // init Post object

    // parse the front matter into Post.config

    // parse the remaining contents
}

fn parse_content(post: *Post, buf: []const u8) !void {
    var tokenizer = Tokenizer.init(buf);
    std.debug.print("{s}", .{buf});
    // var tokens: []Token = undefined;

    while (true) {
        var t = tokenizer.next();
        std.debug.print("{s}: {any} : {any}|{any} = {s}\n", .{ t.tag.symbol(), t.tag.lexeme(), t.loc.start, t.loc.end, buf[t.loc.start..t.loc.end] });

        if (t.tag == .eof or t.tag == .invalid) {
            break;
        }
    }

    _ = post;
    @panic("todo");
}

pub fn parse_frontmatter(post: *Post, buf: []u8) !usize {
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
