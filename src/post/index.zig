const std = @import("std");

const Markdown = @import("../markdown/markdown.zig");

pub const PostConfig = struct {
    url: []u8,
    date: []u8,
    title: []u8,
    published: bool,

    fn deinit(self: *PostConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.date);
        allocator.free(self.title);
    }
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
    self.config.deinit(allocator);
}

pub fn debug(self: *Post) void {
    std.debug.print("\n===Config===\nurl={s}\tdate={s}\ttitle={s}\tpublished={any}\n===/Config===\n{s}\n", .{ self.config.url, self.config.date, self.config.title, self.config.published, self.html });
}
