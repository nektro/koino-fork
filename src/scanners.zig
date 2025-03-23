const std = @import("std");
const testing = std.testing;
const Regex = @import("libpcre").Regex;

const Error = error{OutOfMemory};

const MemoizedRegexes = struct {
    atxHeadingStart: ?Regex = null,
    thematicBreak: ?Regex = null,
    setextHeadingLine: ?Regex = null,
    autolinkUri: ?Regex = null,
    autolinkEmail: ?Regex = null,
    openCodeFence: ?Regex = null,
    closeCodeFence: ?Regex = null,
    htmlBlockStart1: ?Regex = null,
    htmlBlockStart4: ?Regex = null,
    htmlBlockStart6: ?Regex = null,
    htmlBlockStart7: ?Regex = null,
    htmlTag: ?Regex = null,
    spacechars: ?Regex = null,
    linkTitle: ?Regex = null,
    dangerousUrl: ?Regex = null,
    tableStart: ?Regex = null,
    tableCell: ?Regex = null,
    tableCellEnd: ?Regex = null,
    tableRowEnd: ?Regex = null,

    removeAnchorizeRejectedChars: ?Regex = null,
};

var memoized = MemoizedRegexes{};

// pub fn deinitRegexes() void {
//     inline for (@typeInfo(MemoizedRegexes).Struct.fields) |field| {
//         if (@field(memoized, field.name)) |re| {
//             re.deinit();
//             @field(memoized, field.name) = null;
//         }
//     }
// }

fn acquire(comptime name: []const u8, regex: [:0]const u8) Error!Regex {
    const field_name = comptime if (std.mem.lastIndexOf(u8, name, ".")) |i|
        name[i + 1 ..]
    else
        name;

    if (@field(memoized, field_name)) |re| {
        return re;
    }
    @field(memoized, field_name) = Regex.compile(regex, .{ .Utf8 = true }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => unreachable,
    };
    return @field(memoized, field_name).?;
}

fn search(re: Regex, line: []const u8) ?usize {
    if (re.matches(line, .{ .Anchored = true }) catch null) |cap| {
        return cap.end;
    }
    return null;
}

pub fn unwrap(value: Error!?usize, out: *usize) Error!bool {
    if (value) |maybe_val| {
        if (maybe_val) |val| {
            out.* = val;
            return true;
        }
        return false;
    } else |err| {
        return err;
    }
}

var searchFirstCaptureBuffer: [1024]u8 = [_]u8{undefined} ** 1024;
var searchFirstCaptureBufferAllocator = std.heap.FixedBufferAllocator.init(&searchFirstCaptureBuffer);

fn searchFirstCapture(re: Regex, line: []const u8) Error!?usize {
    searchFirstCaptureBufferAllocator.reset();
    const result = re.captures(searchFirstCaptureBufferAllocator.allocator(), line, .{ .Anchored = true }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    if (result) |caps| {
        var i: usize = 1;
        while (i < caps.len) : (i += 1) {
            if (caps[i]) |cap| {
                return cap.end;
            }
        }
        @panic("no matching capture group");
    }
    return null;
}

pub fn atxHeadingStart(line: []const u8) Error!?usize {
    if (line[0] != '#') {
        return null;
    }
    const re = try acquire(@src().fn_name, "#{1,6}[ \t\r\n]");
    return search(re, line);
}

pub fn thematicBreak(line: []const u8) Error!?usize {
    if (line[0] != '*' and line[0] != '-' and line[0] != '_') {
        return null;
    }
    const re = try acquire(@src().fn_name, "(?:(?:\\*[ \t]*){3,}|(?:_[ \t]*){3,}|(?:-[ \t]*){3,})[ \t]*[\r\n]");
    return search(re, line);
}

pub const SetextChar = enum {
    Equals,
    Hyphen,
};

pub fn setextHeadingLine(line: []const u8, sc: *SetextChar) Error!bool {
    const re = try acquire(@src().fn_name, "(?:=+|-+)[ \t]*[\r\n]");
    if ((line[0] == '=' or line[0] == '-') and search(re, line) != null) {
        sc.* = if (line[0] == '=') .Equals else .Hyphen;
        return true;
    }
    return false;
}

const scheme = "[A-Za-z][A-Za-z0-9.+-]{1,31}";

pub fn autolinkUri(line: []const u8) Error!?usize {
    const re = try acquire(@src().fn_name, scheme ++ ":[^\\x00-\\x20<>]*>");
    return search(re, line);
}

pub fn autolinkEmail(line: []const u8) Error!?usize {
    const re = try acquire(@src().fn_name,
        \\[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*>
    );
    return search(re, line);
}

pub fn openCodeFence(line: []const u8) Error!?usize {
    if (line[0] != '`' and line[0] != '~')
        return null;

    const re = try acquire(@src().fn_name, "(?:(`{3,})[^`\r\n\\x00]*|(~{3,})[^\r\n\\x00]*)[\r\n]");
    return searchFirstCapture(re, line);
}

pub fn closeCodeFence(line: []const u8) Error!?usize {
    if (line[0] != '`' and line[0] != '~')
        return null;

    const re = try acquire(@src().fn_name, "(`{3,}|~{3,})[\t ]*[\r\n]");
    return searchFirstCapture(re, line);
}

pub fn htmlBlockEnd1(line: []const u8) bool {
    return std.ascii.indexOfIgnoreCase(line, "</script>") != null or
        std.ascii.indexOfIgnoreCase(line, "</pre>") != null or
        std.ascii.indexOfIgnoreCase(line, "</style>") != null;
}

pub fn htmlBlockEnd2(line: []const u8) bool {
    return std.mem.indexOf(u8, line, "-->") != null;
}

pub fn htmlBlockEnd3(line: []const u8) bool {
    return std.mem.indexOf(u8, line, "?>") != null;
}

pub fn htmlBlockEnd4(line: []const u8) bool {
    return std.mem.indexOfScalar(u8, line, '>') != null;
}

pub fn htmlBlockEnd5(line: []const u8) bool {
    return std.mem.indexOf(u8, line, "]]>") != null;
}

pub fn htmlBlockStart(line: []const u8, sc: *usize) Error!bool {
    if (line[0] != '<')
        return false;

    const re1 = try acquire("htmlBlockStart1", "<(?i:script|pre|style)[ \t\\x0b\\x0c\r\n>]");
    const re4 = try acquire("htmlBlockStart4", "<![A-Z]");
    const re6 = try acquire("htmlBlockStart6", "</?(?i:address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h1|h2|h3|h4|h5|h6|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|section|source|title|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)(?:[ \t\\x0b\\x0c\r\n>]|/>)");

    if (search(re1, line) != null) {
        sc.* = 1;
    } else if (std.mem.startsWith(u8, line, "<!--")) {
        sc.* = 2;
    } else if (std.mem.startsWith(u8, line, "<?")) {
        sc.* = 3;
    } else if (search(re4, line) != null) {
        sc.* = 4;
    } else if (std.mem.startsWith(u8, line, "<![CDATA[")) {
        sc.* = 5;
    } else if (search(re6, line) != null) {
        sc.* = 6;
    } else {
        return false;
    }
    return true;
}

const space_char = "[ \t\\x0b\\x0c\r\n]";
const tag_name = "(?:[A-Za-z][A-Za-z0-9-]*)";
const close_tag = "(?:/" ++ tag_name ++ space_char ++ "*>)";
const attribute_name = "(?:[a-zA_Z_:][a-zA-Z0-9:._-]*)";
const attribute_value = "(?:(?:[^ \t\r\n\\x0b\\x0c\"'=<>`\\x00]+)|(?:'[^\\x00']*')|(?:\"[^\\x00\"]*\"))";
const attribute_value_spec = "(?:" ++ space_char ++ "*=" ++ space_char ++ "*" ++ attribute_value ++ ")";
const attribute = "(?:" ++ space_char ++ "+" ++ attribute_name ++ attribute_value_spec ++ "?)";
const open_tag = "(?:" ++ tag_name ++ attribute ++ "*" ++ space_char ++ "*/?>)";

pub fn htmlBlockStart7(line: []const u8, sc: *usize) Error!bool {
    const re = try acquire(@src().fn_name, "<(?:" ++ open_tag ++ "|" ++ close_tag ++ ")[\t\\x0c ]*[\r\n]");
    if (search(re, line) != null) {
        sc.* = 7;
        return true;
    }
    return false;
}

const html_comment = "(?:!---->|(?:!---?[^\\x00>-](?:-?[^\\x00-])*-->))";
const processing_instruction = "(?:\\?(?:[^?>\\x00]+|\\?[^>\\x00]|>)*\\?>)";
const declaration = "(?:![A-Z]+" ++ space_char ++ "+[^>\\x00]*>)";
const cdata = "(?:!\\[CDATA\\[(?:[^\\]\\x00]+|\\][^\\]\\x00]|\\]\\][^>\\x00])*]]>)";

pub fn htmlTag(line: []const u8) Error!?usize {
    const re = try acquire(@src().fn_name, "(?:" ++ open_tag ++ "|" ++ close_tag ++ "|" ++ html_comment ++ "|" ++ processing_instruction ++ "|" ++ declaration ++ "|" ++ cdata ++ ")");
    return search(re, line);
}

pub fn spacechars(line: []const u8) Error!?usize {
    const re = try acquire(@src().fn_name, space_char ++ "+");
    return search(re, line);
}

const link_title = "(?:\"(?:\\\\.|[^\"\\x00])*\"|'(?:\\\\.|[^'\\x00])*'|\\((?:\\\\.|[^()\\x00])*\\))";

pub fn linkTitle(line: []const u8) Error!?usize {
    const re = try acquire(@src().fn_name, link_title);
    return search(re, line);
}

const dangerous_url = "(?:data:(?!png|gif|jpeg|webp)|javascript:|vbscript:|file:)";

pub fn dangerousUrl(line: []const u8) Error!?usize {
    const re = try acquire(@src().fn_name, dangerous_url);
    return search(re, line);
}

const table_spacechar = "[ \t\\x0b\\x0c]";
const table_newline = "(?:\r?\n)";
const table_marker = "(?:" ++ table_spacechar ++ "*:?-+:?" ++ table_spacechar ++ "*)";
const table_cell = "(?:(\\\\.|[^|\r\n])*)";

pub fn tableStart(line: []const u8) Error!?usize {
    const re = try acquire(@src().fn_name, "\\|?" ++ table_marker ++ "(?:\\|" ++ table_marker ++ ")*\\|?" ++ table_spacechar ++ "*" ++ table_newline);
    return search(re, line);
}

pub fn tableCell(line: []const u8) Error!?usize {
    const re = try acquire(@src().fn_name, table_cell);
    return search(re, line);
}

pub fn tableCellEnd(line: []const u8) Error!?usize {
    const re = try acquire(@src().fn_name, "\\|" ++ table_spacechar ++ "*" ++ table_newline ++ "?");
    return search(re, line);
}

pub fn tableRowEnd(line: []const u8) Error!?usize {
    const re = try acquire(@src().fn_name, table_spacechar ++ "*" ++ table_newline);
    return search(re, line);
}

pub fn removeAnchorizeRejectedChars(allocator: std.mem.Allocator, src: []const u8) Error![]u8 {
    const re = try acquire(@src().fn_name, "[^\\p{L}\\p{M}\\p{N}\\p{Pc} -]");

    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    var org: usize = 0;

    while (re.matches(src[org..], .{}) catch null) |cap| {
        try output.appendSlice(src[org .. org + cap.start]);
        org += cap.end;
        if (org >= src.len) break;
    }

    try output.appendSlice(src[org..]);

    return output.toOwnedSlice();
}
