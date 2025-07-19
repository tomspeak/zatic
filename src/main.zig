const std = @import("std");
const builtin = @import("builtin");

const Posts = @import("Posts.zig");
const Post = @import("Post.zig");
const ZtmlParser = @import("ztml/Parser.zig");
const Context = @import("Context.zig");

pub const std_options: std.Options = .{
    .log_level = .info,
};

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const gpa, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var posts = try Posts.init(gpa, "site/posts/");
    defer posts.deinit(gpa);

    var global_context = try Context.structToContext(gpa, Context.GlobalCtx, &Context.GlobalCtx.instance);
    defer global_context.deinit();

    const post_layout_buf = try std.fs.cwd().readFileAlloc(gpa, "site/posts/layout.ztml", 1024 * 5);
    defer gpa.free(post_layout_buf);

    for (posts.list.items) |post| {
        var post_context = try Context.structToContext(gpa, Post, &post);
        defer post_context.deinit();

        var merged_context = try Context.mergeContexts(gpa, &[_]std.StringHashMap(ZtmlParser.Value){ global_context, post_context });
        defer merged_context.deinit();

        const processed_html = try ZtmlParser.parse(gpa, post_layout_buf, &merged_context);
        defer gpa.free(processed_html);
        std.debug.print("{s}\n", .{processed_html});
    }

    var test_context = try Context.structToContext(gpa, Context.GlobalCtx, &Context.GlobalCtx.instance);
    defer test_context.deinit();

    // const x = try ZtmlParser.parse(gpa, "hello {{ v site_title }} world", &test_context);
    // std.debug.print("{s}\n", .{x});
    // defer gpa.free(x);
}

test {
    @import("std").testing.refAllDecls(@This());
}
