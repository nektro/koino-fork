const std = @import("std");
const builtin = @import("builtin");
const ArrayList = std.array_list.Managed;
const assert = std.debug.assert;

const koino = @import("./koino.zig");

const Parser = koino.parser.Parser;
const Options = koino.Options;
const nodes = koino.nodes;
const html = koino.html;

const MAX_BUFFER_SIZE = 64 * 1024;
const MAX_CONTENT_SIZE = 1024 * 1024 * 1024;

const extensions = blk: {
    var exts: []const []const u8 = &[_][]const u8{};
    for (@typeInfo(Options.Extensions).@"struct".fields) |field| {
        exts = exts ++ [_][]const u8{field.name};
    }
    break :blk exts;
};

const extensionsFriendly = blk: {
    var extsFriendly: []const u8 = &[_]u8{};
    var first = true;
    for (extensions) |extension| {
        if (first) {
            first = false;
        } else {
            extsFriendly = extsFriendly ++ ",";
        }
        extsFriendly = extsFriendly ++ extension;
    }
    break :blk extsFriendly;
};

fn enableExtension(extension: []const u8, options: *Options) !void {
    inline for (extensions) |valid_extension| {
        if (std.mem.eql(u8, valid_extension, extension)) {
            @field(options.extensions, valid_extension) = true;
            return;
        }
    }
    std.log.err("unknown extension: {s}\n", .{extension});
    std.process.exit(1);
}

/// Uses a GeneralPurposeAllocator for scratch work instead of an ArenaAllocator to aid in locating memory leaks.
/// Result HTML is allocated by std.testing.allocator.
pub fn testMarkdownToHtml(options: Options, markdown: []const u8) ![]u8 {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    var doc = try koino.parse(gpa.allocator(), markdown, options);
    defer doc.deinit();

    var result = std.Io.Writer.Allocating.init(std.testing.allocator);
    errdefer result.deinit();
    try html.print(&result.writer, gpa.allocator(), options, doc);
    return result.toOwnedSlice();
}

test {
    std.testing.refAllDecls(@This());
}
