const std = @import("std");

const Post = @import("../post/index.zig");

pub fn parse(allocator: std.mem.Allocator, post: *Post, buf: []u8) !usize {
    const delim = "=!!!=";

    const pos = std.mem.indexOf(u8, buf, delim) orelse return error.NoFrontMatterFound;
    const fm = buf[0..pos];

    var config: Post.PostConfig = .{
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
        const opt = std.meta.stringToEnum(Post.ConfigOptions, k) orelse .unknown;

        switch (opt) {
            .url => config.url = try allocator.dupe(u8, v),
            .date => config.date = try allocator.dupe(u8, v),
            .title => config.title = try allocator.dupe(u8, v),
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
