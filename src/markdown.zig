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

const Token = union(enum) {
    heading: struct {
        level: u8,
        text: []const u8,
    },
    paragraph: struct {
        text: []const u8,
    },
    bold: struct {
        text: []const u8,
    },

    pub fn print(self: Token) void {
        switch (self) {
            .heading => |h| std.debug.print("heading (level {}): {s}\n", .{ h.level, h.text }),
            .paragraph => |p| std.debug.print("paragraph: {s}\n", .{p.text}),
            .bold => |b| std.debug.print("bold: {s}\n", .{b.text}),
        }
    }
};

const Tokenizer = struct {
    buf: []const u8,
    index: usize,

    pub fn init(buf: []const u8) Tokenizer {
        return .{ .buf = buf, .index = 0 };
    }

    const State = enum { start, heading, invalid };

    pub fn next(self: *Tokenizer) ?Token {
        const result: ?Token = null;

        state: switch (State.start) {
            .invalid => {
                @panic("encountered invalid state parsing markdown content");
            },
            .start => switch (self.buf[self.index]) {
                0 => {
                    if (self.index == self.buf.len) {
                        return result;
                    } else {
                        @panic("encountered suspected EOF at an invalid position");
                    }
                },
                ' ', '\n', '\t', '\r' => {
                    self.index += 1;
                    continue :state .start;
                },
                '#' => {
                    continue :state .heading;
                },
                else => continue :state .invalid,
            },
            .heading => {
                self.index += 1;
                // loop until we reach a non-#, count level
                return .{ .heading = .{ .level = 1, .text = "hard coded heading" } };
            },
        }

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
    // var tokens: []Token = undefined;

    while (tokenizer.next()) |token| {
        token.print();
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
