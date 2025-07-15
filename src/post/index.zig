const std = @import("std");
const Thread = std.Thread;

const Markdown = @import("../markdown/markdown.zig");

pub const PostConfig = struct {
    url: ?[]u8,
    date: ?[]u8,
    title: ?[]u8,
    description: ?[]u8,
    published: bool,

    fn deinit(self: *PostConfig, allocator: std.mem.Allocator) void {
        if (self.url) |x| {
            allocator.free(x);
            self.url = null;
        }
        if (self.date) |x| {
            allocator.free(x);
            self.date = null;
        }
        if (self.title) |x| {
            allocator.free(x);
            self.title = null;
        }
        if (self.description) |x| {
            allocator.free(x);
            self.description = null;
        }
    }
};
pub const ConfigOptions = enum { url, date, title, description, published, unknown };

pub const Post = @This();

config: PostConfig,
html: []u8,

pub fn new() Post {
    return .{
        .config = undefined,
        .html = undefined,
    };
}

pub fn init(allocator: std.mem.Allocator, dir_path: []const u8) ![]Post {
    const cwd = std.fs.cwd();

    var dir = try cwd.openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var paths = std.ArrayListUnmanaged([]u8).empty;
    defer paths.deinit(allocator);
    while (try walker.next()) |entry| {
        if (!std.mem.endsWith(u8, entry.path, ".md")) continue;

        const full_path = try std.fs.path.join(allocator, &.{ dir_path, entry.path });
        defer allocator.free(full_path);

        const path_copy = try allocator.dupe(u8, full_path);
        try paths.append(allocator, path_copy);
    }

    var posts = std.ArrayListUnmanaged(Post).empty;
    defer {
        posts.deinit(allocator);
        for (paths.items) |p| {
            allocator.free(p);
        }
    }
    for (paths.items) |p| {
        const buf = try std.fs.cwd().readFileAllocOptions(allocator, p, 1024 * 32, null, @alignOf(u8), 0);
        defer allocator.free(buf);

        var post = Post.new();
        try Markdown.parse(allocator, &post, buf);

        try posts.append(allocator, post);
    }

    return posts.toOwnedSlice(allocator);
}

pub fn deinit(self: *Post, allocator: std.mem.Allocator) void {
    allocator.free(self.html);
    self.config.deinit(allocator);
}

pub fn debug(self: *Post) void {
    std.debug.print("\n===Config===\nurl={s}\tdate={s}\ttitle={s}\tdescription={s}\tpublished={any}\n===/Config===\n{s}\n", .{
        optStr(self.config.url),
        optStr(self.config.date),
        optStr(self.config.title),
        optStr(self.config.description),
        self.config.published,
        self.html,
    });
}

fn optStr(opt: ?[]const u8) []const u8 {
    return opt orelse "<null>";
}
