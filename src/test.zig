const std = @import("std");
const koino = @import("koino");
const Options = koino.Options;
const html = koino.html;
const nodes = koino.nodes;
const Parser = koino.parser.Parser;

/// Performs work using internalAllocator, and writes the result to a Writer.
fn markdownToHtmlInternal(writer: anytype, internalAllocator: std.mem.Allocator, options: Options, markdown: []const u8) !void {
    var doc = try parse(internalAllocator, options, markdown);
    defer doc.deinit();

    try html.print(writer, internalAllocator, options, doc);
}

/// Parses Markdown into an AST.  Use `deinit()' on the returned document to free memory.
pub fn parse(internalAllocator: std.mem.Allocator, options: Options, markdown: []const u8) !*nodes.AstNode {
    var p = try Parser.init(internalAllocator, options);
    defer p.deinit();
    try p.feed(markdown);
    return try p.finish();
}

/// Performs work with an ArenaAllocator backed by the page allocator, and allocates the result HTML with resultAllocator.
pub fn markdownToHtml(resultAllocator: std.mem.Allocator, options: Options, markdown: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(resultAllocator);
    errdefer result.deinit();
    try markdownToHtmlWriter(result.writer(), options, markdown);
    return result.toOwnedSlice();
}

/// Performs work with an ArenaAllocator backed by the page allocator, and writes the result to a Writer.
pub fn markdownToHtmlWriter(writer: anytype, options: Options, markdown: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try markdownToHtmlInternal(writer, arena.allocator(), options, markdown);
}

/// Uses a GeneralPurposeAllocator for scratch work instead of an ArenaAllocator to aid in locating memory leaks.
/// Result HTML is allocated by std.testing.allocator.
pub fn testMarkdownToHtml(options: Options, markdown: []const u8) ![]u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var doc = try parse(gpa.allocator(), options, markdown);
    defer doc.deinit();

    var result = std.ArrayList(u8).init(std.testing.allocator);
    errdefer result.deinit();
    try html.print(result.writer(), gpa.allocator(), options, doc);
    return result.toOwnedSlice();
}
