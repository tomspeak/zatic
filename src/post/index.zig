const std = @import("std");

const Markdown = @import("../markdown/markdown.zig");

pub const PostConfig = struct {
    url: []const u8,
    date: []const u8,
    title: []const u8,
    published: bool,
};
pub const ConfigOptions = enum { url, date, title, published, unknown };

pub const Post = @This();

config: PostConfig,
html: []u8,

pub fn new() Post {
    return .{
        .config = undefined,
        .html = undefined,
    };
}

pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !Post {
    const buf = try std.fs.cwd().readFileAllocOptions(allocator, file_path, 4096, null, @alignOf(u8), 0);
    defer allocator.free(buf);

    var post = Post.new();
    // TODO: handle errors
    try Markdown.parse(allocator, &post, buf);

    return post;
}

pub fn deinit(self: *Post, allocator: std.mem.Allocator) void {
    allocator.free(self.html);
}

pub fn debug(self: *Post) void {
    std.debug.print("\n{s}\n", .{self.html});
}
