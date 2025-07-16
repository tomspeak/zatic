const std = @import("std");
const trim = std.mem.trim;
const splitScalar = std.mem.splitScalar;

const Post = @import("../Post.zig");

const delim = "+++";

pub fn parse(allocator: std.mem.Allocator, post: *Post, buf: []u8) !usize {
    if (!std.mem.startsWith(u8, buf, delim)) {
        return error.MissingStartDelimiter;
    }
    const start_index = delim.len;
    const end_index = std.mem.indexOfPos(u8, buf, start_index, delim) orelse return error.MissingEndDelimiter;
    const content = buf[start_index..end_index];

    var config: Post.PostConfig = .{
        .url = null,
        .date = null,
        .title = null,
        .description = null,
        .published = false,
    };

    var lines = splitScalar(u8, content, '\n');
    while (lines.next()) |l| {
        var kv = splitScalar(u8, l, ':');
        const k = trim(u8, kv.next() orelse continue, " \t");
        const v = trim(u8, kv.next() orelse continue, " \t");
        const opt = std.meta.stringToEnum(Post.ConfigOptions, k) orelse .unknown;

        switch (opt) {
            .url => config.url = try allocator.dupe(u8, v),
            .date => config.date = try allocator.dupe(u8, v),
            .title => config.title = try allocator.dupe(u8, v),
            .description => config.description = try allocator.dupe(u8, v),
            .published => config.published = eql(v, "true"),
            .unknown => {
                var s: [64]u8 = undefined;
                const msg = std.fmt.bufPrint(&s, "panic: unknown frontmatter key: '{s}'\tvalue: {s}", .{ k, v }) catch "panic: failed alloc in formatter config error";
                @panic(msg);
            },
        }
    }

    post.*.config = config;

    // index of final '+' delim
    return end_index + delim.len + 1;
}

inline fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
