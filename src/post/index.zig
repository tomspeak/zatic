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
        if (self.url) |x| allocator.free(x);
        if (self.title) |x| allocator.free(x);
        if (self.date) |x| allocator.free(x);
        if (self.description) |x| allocator.free(x);
    }
};
pub const ConfigOptions = enum { url, date, title, description, published, unknown };

pub const Post = @This();

config: PostConfig,
html: ?[]u8,

pub fn new() Post {
    return .{
        .config = undefined,
        .html = null,
    };
}

pub fn init(gpa: std.mem.Allocator, dir_path: []const u8) ![]Post {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const aa = arena.allocator();

    var cwd = std.fs.cwd();

    var dir = try cwd.openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(aa);
    defer walker.deinit();

    var paths = std.ArrayListUnmanaged([]const u8).empty;
    defer paths.deinit(aa);
    while (try walker.next()) |entry| {
        if (!std.mem.endsWith(u8, entry.path, ".md")) continue;

        const full_path = try std.fs.path.join(aa, &.{ dir_path, entry.path });
        try paths.append(aa, full_path);
    }

    var posts = std.ArrayListUnmanaged(Post).empty;
    defer posts.deinit(gpa);
    for (paths.items) |p| {
        const buf = try std.fs.cwd().readFileAllocOptions(gpa, p, 1024 * 32, null, @alignOf(u8), 0);

        var post = Post.new();
        try Markdown.parse(gpa, &post, buf);

        try posts.append(gpa, post);
        gpa.free(buf);
    }

    return posts.toOwnedSlice(gpa);
}

pub fn deinit(self: *Post, allocator: std.mem.Allocator) void {
    if (self.html) |x| allocator.free(x);
    self.config.deinit(allocator);
}

pub fn debug(self: *Post) void {
    std.debug.print("\n===Config===\nurl={s}\tdate={s}\ttitle={s}\tdescription={s}\tpublished={any}\n===/Config===\n{s}\n", .{
        optStr(self.config.url),
        optStr(self.config.date),
        optStr(self.config.title),
        optStr(self.config.description),
        self.config.published,
        optStr(self.html),
    });
}

fn optStr(opt: ?[]const u8) []const u8 {
    return opt orelse "<null>";
}
