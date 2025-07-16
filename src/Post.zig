const std = @import("std");

const Post = @This();

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

config: PostConfig,
html: ?[]u8,

pub fn init() Post {
    return .{
        .config = undefined,
        .html = null,
    };
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
