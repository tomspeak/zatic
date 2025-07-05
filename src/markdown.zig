const std = @import("std");
const Allocator = std.mem.Allocator;

const PostConfig = struct {
    url: []const u8,
    date: []const u8,
    title: []const u8,
    published: bool,
};

const Post = struct {
    config: PostConfig,
    content: []u8,
    html: []u8,
};

// Parsed features:
//  Title + subtitles (# ## ### ####)
//  Paragraphs
//  Bold, Italic
//  URLs []()
//  Block quotes >
//  Footnotes (TBD)
//  Images
//  Horizontal lines ---

// Create a tokenizer that will go through each byte of buf and assign meaning
// have 2 stages: frontmatter and content stage

// Frontmatter:
//  start ~~~, end ~~~
//  key: value (string, bool)

const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const Tag = enum {
        invalid,
        identifier,
        string_literal,
        colon,
        frontmatter_start,
        frontmatter_end,

        block_quote,
        paragraph,
        heading1,
        heading2,
        heading3,
        heading4,
        bold,
        italic,
    };
};

const Tokenizer = struct {
    buf: [:0]const u8,
    idx: usize,

    pub fn init(buf: [:0]const u8) Tokenizer {
        return .{ .buf = buf, .index = 0 };
    }

    const State = enum {
        frontmatter,
        content,
        identifier,
        string_literal,
    };

    // pub fn next(self: Tokenizer) Token {
    //     var result: Token = .{ .tag = undefined, .local = .{ .start = self.idx, .end = undefined } };
    //
    //     state: switch (State.frontmatter) {
    //         .frontmatter => {},
    //     }
    // }
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

    std.debug.print("\nclean content:{s}", .{content});

    _ = try parse_content(&post, buf);
    // init Post object

    // parse the front matter into Post.config

    // parse the remaining contents
}

fn parse_content(post: *Post, buf: []const u8) !void {
    _ = post;
    _ = buf;
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

        switch (match_config_key(k)) {
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

    _ = post;

    std.debug.print("{any}\n", .{config});

    return pos + delim.len;
}

inline fn match_config_key(k: []const u8) enum { url, date, title, published, unknown } {
    if (eql(k, "url")) return .url;
    if (eql(k, "date")) return .date;
    if (eql(k, "title")) return .title;
    if (eql(k, "published")) return .published;
    return .unknown;
}

inline fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
