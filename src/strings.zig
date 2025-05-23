const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const ascii = std.ascii;

const nodes = @import("nodes.zig");
const htmlentities = @import("htmlentities");
const icu = @import("icu");

pub fn isLineEndChar(ch: u8) bool {
    return switch (ch) {
        '\n', '\r' => true,
        else => false,
    };
}

pub fn isSpaceOrTab(ch: u8) bool {
    return switch (ch) {
        ' ', '\t' => true,
        else => false,
    };
}

pub fn isBlank(s: []const u8) bool {
    for (s) |c| {
        switch (c) {
            '\n', '\r' => return true,
            ' ', '\t' => {},
            else => return false,
        }
    }
    return true;
}

const SPACES = "\t\n\x0b\x0c\r ";

pub fn ltrim(s: []const u8) []const u8 {
    return mem.trimLeft(u8, s, SPACES);
}

pub fn rtrim(s: []const u8) []const u8 {
    return mem.trimRight(u8, s, SPACES);
}

pub fn trim(s: []const u8) []const u8 {
    return mem.trim(u8, s, SPACES);
}

pub fn trimIt(al: *std.ArrayList(u8)) void {
    const trimmed = trim(al.items);
    if (al.items.ptr == trimmed.ptr and al.items.len == trimmed.len) return;
    std.mem.copyForwards(u8, al.items, trimmed);
    al.items.len = trimmed.len;
}

pub fn chopTrailingHashtags(s: []const u8) []const u8 {
    var r = rtrim(s);
    if (r.len == 0) return r;

    const orig_n = r.len - 1;
    var n = orig_n;
    while (r[n] == '#') : (n -= 1) {
        if (n == 0) return r;
    }

    if (n != orig_n and isSpaceOrTab(r[n])) {
        return rtrim(r[0..n]);
    } else {
        return r;
    }
}

pub fn normalizeCode(allocator: mem.Allocator, s: []const u8) mem.Allocator.Error![]u8 {
    var code = try std.ArrayList(u8).initCapacity(allocator, s.len);
    errdefer code.deinit();

    var i: usize = 0;
    var contains_nonspace = false;

    while (i < s.len) {
        switch (s[i]) {
            '\r' => {
                if (i + 1 == s.len or s[i + 1] != '\n') {
                    try code.append(' ');
                }
            },
            '\n' => {
                try code.append(' ');
            },
            else => try code.append(s[i]),
        }
        if (s[i] != ' ') {
            contains_nonspace = true;
        }
        i += 1;
    }

    if (contains_nonspace and code.items.len != 0 and code.items[0] == ' ' and code.items[code.items.len - 1] == ' ') {
        _ = code.orderedRemove(0);
        _ = code.pop();
    }

    return code.toOwnedSlice();
}

pub fn removeTrailingBlankLines(line: *std.ArrayList(u8)) void {
    var i = line.items.len - 1;
    while (true) : (i -= 1) {
        const c = line.items[i];

        if (c != ' ' and c != '\t' and !isLineEndChar(c)) {
            break;
        }

        if (i == 0) {
            line.items.len = 0;
            return;
        }
    }

    while (i < line.items.len) : (i += 1) {
        if (!isLineEndChar(line.items[i])) continue;
        line.items.len = i;
        break;
    }
}

pub fn isPunct(char: u8) bool {
    return switch (char) {
        '!', '\"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/', ':', ';', '<', '=', '>', '?', '@', '[', '\\', ']', '^', '_', '`', '{', '|', '}', '~' => true,
        else => false,
    };
}

fn encodeUtf8Into(in_cp: u21, al: *std.ArrayList(u8)) !void {
    // utf8Encode throws:
    // - Utf8CannotEncodeSurrogateHalf, which we guard against that by
    //   rewriting 0xd800..0xe0000 to 0xfffd.
    // - CodepointTooLarge, which we guard against by rewriting 0x110000+
    //   to 0xfffd.
    var cp = in_cp;
    if (cp == 0 or (cp >= 0xd800 and cp <= 0xdfff) or cp >= 0x110000) {
        cp = 0xFFFD;
    }
    var sequence = [4]u8{ 0, 0, 0, 0 };
    const len = std.unicode.utf8Encode(cp, &sequence) catch unreachable;
    try al.appendSlice(sequence[0..len]);
}

const ENTITY_MIN_LENGTH: u8 = 2;
const ENTITY_MAX_LENGTH: u8 = 32;

pub fn unescapeInto(text: []const u8, out: *std.ArrayList(u8)) !?usize {
    if (text.len >= 3 and text[0] == '#') {
        var codepoint: u32 = 0;
        var i: usize = 0;

        const num_digits = block: {
            if (ascii.isDigit(text[1])) {
                i = 1;
                while (i < text.len and ascii.isDigit(text[i])) {
                    codepoint = (codepoint * 10) + (@as(u32, text[i]) - '0');
                    codepoint = @min(codepoint, 0x11_0000);
                    i += 1;
                }
                break :block i - 1;
            } else if (text[1] == 'x' or text[1] == 'X') {
                i = 2;
                while (i < text.len and ascii.isHex(text[i])) {
                    codepoint = (codepoint * 16) + (@as(u32, text[i]) | 32) % 39 - 9;
                    codepoint = @min(codepoint, 0x11_0000);
                    i += 1;
                }
                break :block i - 2;
            }
            break :block 0;
        };

        if (num_digits >= 1 and num_digits <= 8 and i < text.len and text[i] == ';') {
            try encodeUtf8Into(@truncate(codepoint), out);
            return i + 1;
        }
    }

    const size = @min(text.len, ENTITY_MAX_LENGTH);
    var i = ENTITY_MIN_LENGTH;
    while (i < size) : (i += 1) {
        if (text[i] == ' ')
            return null;
        if (text[i] == ';') {
            var key = [_]u8{'&'} ++ [_]u8{';'} ** (ENTITY_MAX_LENGTH + 1);
            std.mem.copyForwards(u8, key[1..], text[0..i]);

            if (htmlentities.lookup(key[0 .. i + 2])) |item| {
                try out.appendSlice(item.characters);
                return i + 1;
            }
        }
    }

    return null;
}

fn unescapeHtmlInto(html: []const u8, out: *std.ArrayList(u8)) !void {
    const size = html.len;
    var i: usize = 0;

    while (i < size) {
        const org = i;

        while (i < size and html[i] != '&') : (i += 1) {}

        if (i > org) {
            if (org == 0 and i >= size) {
                try out.appendSlice(html);
                return;
            }

            try out.appendSlice(html[org..i]);
        }

        if (i >= size)
            return;

        i += 1;

        if (try unescapeInto(html[i..], out)) |unescaped_size| {
            i += unescaped_size;
        } else {
            try out.append('&');
        }
    }
}

pub fn unescapeHtml(allocator: mem.Allocator, html: []const u8) ![]u8 {
    var al = std.ArrayList(u8).init(allocator);
    errdefer al.deinit();
    try unescapeHtmlInto(html, &al);
    return al.toOwnedSlice();
}

pub fn cleanAutolink(allocator: mem.Allocator, url: []const u8, kind: nodes.AutolinkType) ![]u8 {
    const trimmed = trim(url);
    if (trimmed.len == 0)
        return &[_]u8{};

    var buf = try std.ArrayList(u8).initCapacity(allocator, trimmed.len);
    errdefer buf.deinit();
    if (kind == .Email)
        try buf.appendSlice("mailto:");

    try unescapeHtmlInto(trimmed, &buf);
    return buf.toOwnedSlice();
}

fn unescape(allocator: mem.Allocator, s: []const u8) ![]u8 {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, s.len);
    errdefer buffer.deinit();
    var r: usize = 0;

    while (r < s.len) : (r += 1) {
        if (s[r] == '\\' and r + 1 < s.len and isPunct(s[r + 1]))
            r += 1;
        try buffer.append(s[r]);
    }
    return buffer.toOwnedSlice();
}

pub fn cleanUrl(allocator: mem.Allocator, url: []const u8) ![]u8 {
    const trimmed = trim(url);
    if (trimmed.len == 0)
        return &[_]u8{};

    const b = try unescapeHtml(allocator, trimmed);
    defer allocator.free(b);
    return unescape(allocator, b);
}

pub fn cleanTitle(allocator: mem.Allocator, title: []const u8) ![]u8 {
    if (title.len == 0)
        return &[_]u8{};

    const first = title[0];
    const last = title[title.len - 1];
    const b = if ((first == '\'' and last == '\'') or (first == '(' and last == ')') or (first == '"' and last == '"'))
        try unescapeHtml(allocator, title[1 .. title.len - 1])
    else
        try unescapeHtml(allocator, title);
    defer allocator.free(b);
    return unescape(allocator, b);
}

pub fn normalizeLabel(allocator: mem.Allocator, s: []const u8) ![]u8 {
    const trimmed = trim(s);
    var buffer = try std.ArrayList(u8).initCapacity(allocator, trimmed.len);
    errdefer buffer.deinit();
    var last_was_whitespace = false;

    var view = std.unicode.Utf8View.initUnchecked(trimmed);
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| {
        if (icu.hasProperty(cp, .White_Space)) {
            if (!last_was_whitespace) {
                last_was_whitespace = true;
                try buffer.append(' ');
            }
        } else {
            last_was_whitespace = false;
            const lower = icu.toLower(cp) orelse cp;
            try encodeUtf8Into(@intCast(lower), &buffer);
        }
    }
    return buffer.toOwnedSlice();
}

pub fn toLower(allocator: mem.Allocator, s: []const u8) ![]u8 {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, s.len);
    errdefer buffer.deinit();
    var view = try std.unicode.Utf8View.init(s);
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| {
        const rune: u32 = cp;
        const lower = icu.toLower(rune) orelse rune;
        try encodeUtf8Into(@intCast(lower), &buffer);
    }
    return buffer.toOwnedSlice();
}

pub fn createMap(chars: []const u8) [256]bool {
    var arr = [_]bool{false} ** 256;
    for (chars) |c| {
        arr[c] = true;
    }
    return arr;
}
