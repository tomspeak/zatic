// TODO:
// 3. better debug output that can be toggled on/off
// 7. handle directory of posts using Threads
// 8. basic impl of injecting markdown html into template
const std = @import("std");
const Allocator = std.mem.Allocator;

const Frontmatter = @import("frontmatter.zig");
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");
const Token = @import("Token.zig");
const Post = @import("../Post.zig");

pub fn parse(allocator: Allocator, post: *Post, content: [:0]u8) !void {
    const fm_index = try Frontmatter.parse(allocator, post, content);
    const contentSansFrontmatter = content[fm_index..];

    var lexer = Lexer.init(contentSansFrontmatter);
    var tokens = try lexer.parse(allocator);
    defer tokens.deinit(allocator);

    var parser = Parser.init(contentSansFrontmatter, tokens.items);
    var parsed = try parser.parse(allocator);
    defer parsed.deinit(allocator);

    var buf: [1024 * 32]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try Parser.write(stream.writer(), parsed);

    post.html = try allocator.dupe(u8, buf[0..stream.pos]);
}
// test "basic tokenizer" {
//     const allocator = std.testing.allocator;
//     const content: [:0]const u8 =
//         \\# hello
//         \\how are *you*?
//     ;
//     const tokens = try parse_content(allocator, content);
//     defer allocator.free(tokens);
//
//     const expected_tags = [_]Token.TokenType{ .hashtag, .string_literal, .new_line, .string_literal, .asterisk, .string_literal, .asterisk, .string_literal, .eof };
//
//     var actual_tags: [9]Token.TokenType = undefined;
//     for (tokens, 0..) |tok, i| {
//         tok.dump();
//         actual_tags[i] = tok.tag;
//     }
//
//     try std.testing.expectEqualSlices(Token.TokenType, &expected_tags, &actual_tags);
// }
