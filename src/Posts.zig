const std = @import("std");
const Thread = std.Thread;

const Markdown = @import("markdown/markdown.zig");
const Post = @import("Post.zig");

const Posts = @This();

list: std.ArrayListUnmanaged(Post) = .empty,

pub fn init(allocator: std.mem.Allocator, dir_path: []const u8) !Posts {
    var self: Posts = .{};
    errdefer self.deinit(allocator);

    const cwd = std.fs.cwd();
    var dir = try cwd.openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (!std.mem.endsWith(u8, entry.path, ".md")) continue;

        const full_path = try std.fs.path.join(allocator, &.{ dir_path, entry.path });
        defer allocator.free(full_path);

        const buf = try std.fs.cwd().readFileAllocOptions(allocator, full_path, 1024 * 32, null, @alignOf(u8), 0);
        defer allocator.free(buf);

        var post = Post.init();
        errdefer post.deinit(allocator);
        try Markdown.parse(allocator, &post, buf);

        try self.list.append(allocator, post);
    }

    return self;
}

pub fn deinit(self: *Posts, allocator: std.mem.Allocator) void {
    for (self.list.items) |*post| {
        post.deinit(allocator);
    }
    self.list.deinit(allocator);
}
