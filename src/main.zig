const std = @import("std");
const md = @import("markdown.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    try md.parse(alloc, "site/posts/test.md");
}
