const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

const clap = @import("clap");
const koino = @import("koino");

const Parser = koino.parser.Parser;
const Options = koino.Options;
const nodes = koino.nodes;
const html = koino.html;

const main = @import("./test.zig");

test "escaping works as expected" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var formatter = koino.html.makeHtmlFormatter(buffer.writer(), std.testing.allocator, .{});
    defer formatter.deinit();

    try formatter.escape("<hello & goodbye>");
    try std.testing.expectEqualStrings("&lt;hello &amp; goodbye&gt;", buffer.items);
}

test "lowercase anchor generation" {
    var formatter = koino.html.makeHtmlFormatter(std.io.null_writer, std.testing.allocator, .{});
    defer formatter.deinit();

    try std.testing.expectEqualStrings("yés", try formatter.anchorize("YÉS"));
}

fn expectMarkdownHTML(options: Options, markdown: []const u8, html_: []const u8) !void {
    const output = try main.testMarkdownToHtml(options, markdown);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings(html_, output);
}

test "convert simple emphases" {
    if (true) return error.SkipZigTest;
    try expectMarkdownHTML(.{},
        \\hello, _world_ __world__ ___world___ *_world_* **_world_** *__world__*
        \\
        \\this is `yummy`
        \\
    ,
        \\<p>hello, <em>world</em> <strong>world</strong> <em><strong>world</strong></em> <em><em>world</em></em> <strong><em>world</em></strong> <em><strong>world</strong></em></p>
        \\<p>this is <code>yummy</code></p>
        \\
    );
}
test "smart quotes" {
    try expectMarkdownHTML(.{ .parse = .{ .smart = true } }, "\"Hey,\" she said. \"What's 'up'?\"\n", "<p>“Hey,” she said. “What’s ‘up’?”</p>\n");
}
test "handles EOF without EOL" {
    try expectMarkdownHTML(.{}, "hello", "<p>hello</p>\n");
}
test "accepts multiple lines" {
    try expectMarkdownHTML(.{}, "hello\nthere\n", "<p>hello\nthere</p>\n");
    try expectMarkdownHTML(.{ .render = .{ .hard_breaks = true } }, "hello\nthere\n", "<p>hello<br />\nthere</p>\n");
}
test "smart hyphens" {
    try expectMarkdownHTML(.{ .parse = .{ .smart = true } }, "hyphen - en -- em --- four ---- five ----- six ------ seven -------\n", "<p>hyphen - en – em — four –– five —– six —— seven —––</p>\n");
}
test "handles tabs" {
    try expectMarkdownHTML(.{}, "\tfoo\tbaz\t\tbim\n", "<pre><code>foo\tbaz\t\tbim\n</code></pre>\n");
    try expectMarkdownHTML(.{}, "  \tfoo\tbaz\t\tbim\n", "<pre><code>foo\tbaz\t\tbim\n</code></pre>\n");
    try expectMarkdownHTML(.{}, "  - foo\n\n\tbar\n", "<ul>\n<li>\n<p>foo</p>\n<p>bar</p>\n</li>\n</ul>\n");
    try expectMarkdownHTML(.{}, "#\tFoo\n", "<h1>Foo</h1>\n");
    try expectMarkdownHTML(.{}, "*\t*\t*\t\n", "<hr />\n");
}
test "escapes" {
    try expectMarkdownHTML(.{}, "\\## foo\n", "<p>## foo</p>\n");
}
test "setext heading override pointy" {
    try expectMarkdownHTML(.{}, "<a title=\"a lot\n---\nof dashes\"/>\n", "<h2>&lt;a title=&quot;a lot</h2>\n<p>of dashes&quot;/&gt;</p>\n");
}
test "fenced code blocks" {
    try expectMarkdownHTML(.{}, "```\n<\n >\n```\n", "<pre><code>&lt;\n &gt;\n</code></pre>\n");
    try expectMarkdownHTML(.{}, "````\naaa\n```\n``````\n", "<pre><code>aaa\n```\n</code></pre>\n");
}
test "html blocks" {
    try expectMarkdownHTML(.{ .render = .{ .unsafe = true } },
        \\_world_.
        \\</pre>
    ,
        \\<p><em>world</em>.
        \\</pre></p>
        \\
    );

    try expectMarkdownHTML(.{ .render = .{ .unsafe = true } },
        \\<table><tr><td>
        \\<pre>
        \\**Hello**,
        \\
        \\_world_.
        \\</pre>
        \\</td></tr></table>
    ,
        \\<table><tr><td>
        \\<pre>
        \\**Hello**,
        \\<p><em>world</em>.
        \\</pre></p>
        \\</td></tr></table>
        \\
    );

    try expectMarkdownHTML(.{ .render = .{ .unsafe = true } },
        \\<DIV CLASS="foo">
        \\
        \\*Markdown*
        \\
        \\</DIV>
    ,
        \\<DIV CLASS="foo">
        \\<p><em>Markdown</em></p>
        \\</DIV>
        \\
    );

    try expectMarkdownHTML(.{ .render = .{ .unsafe = true } },
        \\<pre language="haskell"><code>
        \\import Text.HTML.TagSoup
        \\
        \\main :: IO ()
        \\main = print $ parseTags tags
        \\</code></pre>
        \\okay
        \\
    ,
        \\<pre language="haskell"><code>
        \\import Text.HTML.TagSoup
        \\
        \\main :: IO ()
        \\main = print $ parseTags tags
        \\</code></pre>
        \\<p>okay</p>
        \\
    );
}
test "links" {
    try expectMarkdownHTML(.{}, "[foo](/url)\n", "<p><a href=\"/url\">foo</a></p>\n");
    try expectMarkdownHTML(.{}, "[foo](/url \"title\")\n", "<p><a href=\"/url\" title=\"title\">foo</a></p>\n");
}
test "link reference definitions" {
    try expectMarkdownHTML(.{}, "[foo]: /url \"title\"\n\n[foo]\n", "<p><a href=\"/url\" title=\"title\">foo</a></p>\n");
    try expectMarkdownHTML(.{}, "[foo]: /url\\bar\\*baz \"foo\\\"bar\\baz\"\n\n[foo]\n", "<p><a href=\"/url%5Cbar*baz\" title=\"foo&quot;bar\\baz\">foo</a></p>\n");
}
test "tables" {
    try expectMarkdownHTML(.{ .extensions = .{ .table = true } },
        \\| foo | bar |
        \\| --- | --- |
        \\| baz | bim |
        \\
    ,
        \\<table>
        \\<thead>
        \\<tr>
        \\<th>foo</th>
        \\<th>bar</th>
        \\</tr>
        \\</thead>
        \\<tbody>
        \\<tr>
        \\<td>baz</td>
        \\<td>bim</td>
        \\</tr>
        \\</tbody>
        \\</table>
        \\
    );
}
test "strikethroughs" {
    try expectMarkdownHTML(.{ .extensions = .{ .strikethrough = true } }, "Hello ~world~ there.\n", "<p>Hello <del>world</del> there.</p>\n");
}
test "images" {
    try expectMarkdownHTML(.{}, "[![moon](moon.jpg)](/uri)\n", "<p><a href=\"/uri\"><img src=\"moon.jpg\" alt=\"moon\" /></a></p>\n");
}
test "autolink" {
    try expectMarkdownHTML(.{ .extensions = .{ .autolink = true } }, "www.commonmark.org\n", "<p><a href=\"http://www.commonmark.org\">www.commonmark.org</a></p>\n");
    try expectMarkdownHTML(.{ .extensions = .{ .autolink = true } }, "http://commonmark.org\n", "<p><a href=\"http://commonmark.org\">http://commonmark.org</a></p>\n");
    try expectMarkdownHTML(.{ .extensions = .{ .autolink = true } }, "foo@bar.baz\n", "<p><a href=\"mailto:foo@bar.baz\">foo@bar.baz</a></p>\n");
}
test "header anchors" {
    try expectMarkdownHTML(.{ .render = .{ .header_anchors = true } },
        \\# Hi.
        \\## Hi 1.
        \\### Hi.
        \\#### Hello.
        \\##### Hi.
        \\###### Hello.
        \\# Isn't it grand?
        \\
    ,
        \\<h1><a href="#hi" id="hi"></a>Hi.</h1>
        \\<h2><a href="#hi-1" id="hi-1"></a>Hi 1.</h2>
        \\<h3><a href="#hi-2" id="hi-2"></a>Hi.</h3>
        \\<h4><a href="#hello" id="hello"></a>Hello.</h4>
        \\<h5><a href="#hi-3" id="hi-3"></a>Hi.</h5>
        \\<h6><a href="#hello-1" id="hello-1"></a>Hello.</h6>
        \\<h1><a href="#isnt-it-grand" id="isnt-it-grand"></a>Isn't it grand?</h1>
        \\
    );
}

test "thematicBreak" {
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.thematicBreak("hello"));
    try std.testing.expectEqual(@as(?usize, 4), try koino.scanners.thematicBreak("***\n"));
    try std.testing.expectEqual(@as(?usize, 21), try koino.scanners.thematicBreak("-          -   -    \r"));
    try std.testing.expectEqual(@as(?usize, 21), try koino.scanners.thematicBreak("-          -   -    \r\nxyz"));
}

test "autolinkUri" {
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.autolinkUri("www.google.com>"));
    try std.testing.expectEqual(@as(?usize, 23), try koino.scanners.autolinkUri("https://www.google.com>"));
    try std.testing.expectEqual(@as(?usize, 7), try koino.scanners.autolinkUri("a+b-c:>"));
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.autolinkUri("a+b-c:"));
}

test "autolinkEmail" {
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.autolinkEmail("abc>"));
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.autolinkEmail("abc.def>"));
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.autolinkEmail("abc@def"));
    try std.testing.expectEqual(@as(?usize, 8), try koino.scanners.autolinkEmail("abc@def>"));
    try std.testing.expectEqual(@as(?usize, 16), try koino.scanners.autolinkEmail("abc+123!?@96--1>"));
}

test "openCodeFence" {
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.openCodeFence("```m"));
    try std.testing.expectEqual(@as(?usize, 3), try koino.scanners.openCodeFence("```m\n"));
    try std.testing.expectEqual(@as(?usize, 6), try koino.scanners.openCodeFence("~~~~~~m\n"));
}

test "closeCodeFence" {
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.closeCodeFence("```m"));
    try std.testing.expectEqual(@as(?usize, 3), try koino.scanners.closeCodeFence("```\n"));
    try std.testing.expectEqual(@as(?usize, 6), try koino.scanners.closeCodeFence("~~~~~~\r\n"));
}

test "htmlBlockEnd1" {
    try std.testing.expect(koino.scanners.htmlBlockEnd1(" xyz </script> "));
    try std.testing.expect(koino.scanners.htmlBlockEnd1(" xyz </SCRIPT> "));
    try std.testing.expect(!koino.scanners.htmlBlockEnd1(" xyz </ script> "));
}

test "htmlBlockStart" {
    var sc: usize = undefined;

    try std.testing.expect(!try koino.scanners.htmlBlockStart("<xyz", &sc));
    try std.testing.expect(try koino.scanners.htmlBlockStart("<Script\r", &sc));
    try std.testing.expectEqual(@as(usize, 1), sc);
    try std.testing.expect(try koino.scanners.htmlBlockStart("<pre>", &sc));
    try std.testing.expectEqual(@as(usize, 1), sc);
    try std.testing.expect(try koino.scanners.htmlBlockStart("<!-- h", &sc));
    try std.testing.expectEqual(@as(usize, 2), sc);
    try std.testing.expect(try koino.scanners.htmlBlockStart("<?m", &sc));
    try std.testing.expectEqual(@as(usize, 3), sc);
    try std.testing.expect(try koino.scanners.htmlBlockStart("<!Q", &sc));
    try std.testing.expectEqual(@as(usize, 4), sc);
    try std.testing.expect(try koino.scanners.htmlBlockStart("<![CDATA[\n", &sc));
    try std.testing.expectEqual(@as(usize, 5), sc);
    try std.testing.expect(try koino.scanners.htmlBlockStart("</ul>", &sc));
    try std.testing.expectEqual(@as(usize, 6), sc);
    try std.testing.expect(try koino.scanners.htmlBlockStart("<figcaption/>", &sc));
    try std.testing.expectEqual(@as(usize, 6), sc);
    try std.testing.expect(!try koino.scanners.htmlBlockStart("<xhtml>", &sc));
}

test "htmlBlockStart7" {
    var sc: usize = 1;
    try std.testing.expect(!try koino.scanners.htmlBlockStart7("<a", &sc));
    try std.testing.expect(try koino.scanners.htmlBlockStart7("<a>  \n", &sc));
    try std.testing.expectEqual(@as(usize, 7), sc);
    try std.testing.expect(try koino.scanners.htmlBlockStart7("<b2/>\r", &sc));
    try std.testing.expect(try koino.scanners.htmlBlockStart7("<b2\ndata=\"foo\" >\t\x0c\n", &sc));
    try std.testing.expect(try koino.scanners.htmlBlockStart7("<a foo=\"bar\" bam = 'baz <em>\"</em>'\n_boolean zoop:33=zoop:33 />\n", &sc));
    try std.testing.expect(!try koino.scanners.htmlBlockStart7("<a h*#ref=\"hi\">\n", &sc));
}

test "htmlTag" {
    try std.testing.expectEqual(@as(?usize, 6), try koino.scanners.htmlTag("!---->"));
    try std.testing.expectEqual(@as(?usize, 9), try koino.scanners.htmlTag("!--x-y-->"));
    try std.testing.expectEqual(@as(?usize, 5), try koino.scanners.htmlTag("?zy?>"));
    try std.testing.expectEqual(@as(?usize, 6), try koino.scanners.htmlTag("?z?y?>"));
    try std.testing.expectEqual(@as(?usize, 14), try koino.scanners.htmlTag("!ABCD aoea@#&>"));
    try std.testing.expectEqual(@as(?usize, 11), try koino.scanners.htmlTag("![CDATA[]]>"));
    try std.testing.expectEqual(@as(?usize, 20), try koino.scanners.htmlTag("![CDATA[a b\n c d ]]>"));
    try std.testing.expectEqual(@as(?usize, 23), try koino.scanners.htmlTag("![CDATA[\r]abc]].>\n]>]]>"));
}

test "linkTitle" {
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.linkTitle("\"xyz"));
    try std.testing.expectEqual(@as(?usize, 5), try koino.scanners.linkTitle("\"xyz\""));
    try std.testing.expectEqual(@as(?usize, 7), try koino.scanners.linkTitle("\"x\\\"yz\""));
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.linkTitle("'xyz"));
    try std.testing.expectEqual(@as(?usize, 5), try koino.scanners.linkTitle("'xyz'"));
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.linkTitle("(xyz"));
    try std.testing.expectEqual(@as(?usize, 5), try koino.scanners.linkTitle("(xyz)"));
}

test "dangerousUrl" {
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.dangerousUrl("http://thing"));
    try std.testing.expectEqual(@as(?usize, 5), try koino.scanners.dangerousUrl("data:xyz"));
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.dangerousUrl("data:png"));
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.dangerousUrl("data:webp"));
    try std.testing.expectEqual(@as(?usize, 5), try koino.scanners.dangerousUrl("data:a"));
    try std.testing.expectEqual(@as(?usize, 11), try koino.scanners.dangerousUrl("javascript:"));
}

test "tableStart" {
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.tableStart("  \r\n"));
    try std.testing.expectEqual(@as(?usize, 7), try koino.scanners.tableStart(" -- |\r\n"));
    try std.testing.expectEqual(@as(?usize, 14), try koino.scanners.tableStart("| :-- | -- |\r\n"));
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.tableStart("| -:- | -- |\r\n"));
}

test "tableCell" {
    try std.testing.expectEqual(@as(?usize, 3), try koino.scanners.tableCell("abc|def"));
    try std.testing.expectEqual(@as(?usize, 8), try koino.scanners.tableCell("abc\\|def"));
    try std.testing.expectEqual(@as(?usize, 5), try koino.scanners.tableCell("abc\\\\|def"));
}

test "tableCellEnd" {
    try std.testing.expectEqual(@as(?usize, 1), try koino.scanners.tableCellEnd("|"));
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.tableCellEnd(" |"));
    try std.testing.expectEqual(@as(?usize, 1), try koino.scanners.tableCellEnd("|a"));
    try std.testing.expectEqual(@as(?usize, 3), try koino.scanners.tableCellEnd("|  \r"));
    try std.testing.expectEqual(@as(?usize, 4), try koino.scanners.tableCellEnd("|  \n"));
    try std.testing.expectEqual(@as(?usize, 5), try koino.scanners.tableCellEnd("|  \r\n"));
}

test "tableRowEnd" {
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.tableRowEnd("a"));
    try std.testing.expectEqual(@as(?usize, 1), try koino.scanners.tableRowEnd("\na"));
    try std.testing.expectEqual(@as(?usize, null), try koino.scanners.tableRowEnd("  a"));
    try std.testing.expectEqual(@as(?usize, 4), try koino.scanners.tableRowEnd("   \na"));
    try std.testing.expectEqual(@as(?usize, 5), try koino.scanners.tableRowEnd("   \r\na"));
}

test "removeAnchorizeRejectedChars" {
    for ([_][]const u8{ "abc", "'abc", "''abc", "a'bc", "'a'''b'c'" }) |abc| {
        const result = try koino.scanners.removeAnchorizeRejectedChars(std.testing.allocator, abc);
        try std.testing.expectEqualStrings("abc", result);
        std.testing.allocator.free(result);
    }
}

test "isBlank" {
    try std.testing.expect(koino.strings.isBlank(""));
    try std.testing.expect(koino.strings.isBlank("\nx"));
    try std.testing.expect(koino.strings.isBlank("    \t\t  \r"));
    try std.testing.expect(!koino.strings.isBlank("e"));
    try std.testing.expect(!koino.strings.isBlank("   \t    e "));
}

test "ltrim" {
    try std.testing.expectEqualStrings("abc", koino.strings.ltrim("abc"));
    try std.testing.expectEqualStrings("abc", koino.strings.ltrim("   abc"));
    try std.testing.expectEqualStrings("abc", koino.strings.ltrim("      \n\n \t\r abc"));
    try std.testing.expectEqualStrings("abc \n zz \n   ", koino.strings.ltrim("\nabc \n zz \n   "));
}

test "rtrim" {
    try std.testing.expectEqualStrings("abc", koino.strings.rtrim("abc"));
    try std.testing.expectEqualStrings("abc", koino.strings.rtrim("abc   "));
    try std.testing.expectEqualStrings("abc", koino.strings.rtrim("abc      \n\n \t\r "));
    try std.testing.expectEqualStrings("  \nabc \n zz", koino.strings.rtrim("  \nabc \n zz \n"));
}

test "trim" {
    try std.testing.expectEqualStrings("abc", koino.strings.trim("abc"));
    try std.testing.expectEqualStrings("abc", koino.strings.trim("  abc   "));
    try std.testing.expectEqualStrings("abc", koino.strings.trim(" abc      \n\n \t\r "));
    try std.testing.expectEqualStrings("abc \n zz", koino.strings.trim("  \nabc \n zz \n"));
}

test "trimIt" {
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();

    try buf.appendSlice("abc");
    koino.strings.trimIt(&buf);
    try std.testing.expectEqualStrings("abc", buf.items);

    buf.items.len = 0;
    try buf.appendSlice("  \tabc");
    koino.strings.trimIt(&buf);
    try std.testing.expectEqualStrings("abc", buf.items);

    buf.items.len = 0;
    try buf.appendSlice(" \r abc  \n ");
    koino.strings.trimIt(&buf);
    try std.testing.expectEqualStrings("abc", buf.items);
}

test "chopTrailingHashtags" {
    try std.testing.expectEqualStrings("xyz", koino.strings.chopTrailingHashtags("xyz"));
    try std.testing.expectEqualStrings("xyz#", koino.strings.chopTrailingHashtags("xyz#"));
    try std.testing.expectEqualStrings("xyz###", koino.strings.chopTrailingHashtags("xyz###"));
    try std.testing.expectEqualStrings("xyz###", koino.strings.chopTrailingHashtags("xyz###  "));
    try std.testing.expectEqualStrings("xyz###", koino.strings.chopTrailingHashtags("xyz###  #"));
    try std.testing.expectEqualStrings("xyz", koino.strings.chopTrailingHashtags("xyz  "));
    try std.testing.expectEqualStrings("xyz", koino.strings.chopTrailingHashtags("xyz  ##"));
    try std.testing.expectEqualStrings("xyz", koino.strings.chopTrailingHashtags("xyz  ##"));
}

const Case = struct {
    in: []const u8,
    out: []const u8,
};

fn testCases(comptime function: fn (std.mem.Allocator, []const u8) anyerror![]u8, cases: []const Case) !void {
    for (cases) |case| {
        const result = try function(std.testing.allocator, case.in);
        defer std.testing.allocator.free(result);
        try std.testing.expectEqualStrings(case.out, result);
    }
}

test "normalizeCode" {
    try testCases(koino.strings.normalizeCode, &[_]Case{
        .{ .in = "qwe", .out = "qwe" },
        .{ .in = " qwe ", .out = "qwe" },
        .{ .in = "  qwe  ", .out = " qwe " },
        .{ .in = " abc\rdef'\r\ndef ", .out = "abc def' def" },
    });
}

test "removeTrailingBlankLines" {
    const cases = [_]Case{
        .{ .in = "\n\n   \r\t\n ", .out = "" },
        .{ .in = "yep\nok\n\n  ", .out = "yep\nok" },
        .{ .in = "yep  ", .out = "yep  " },
    };

    var line = std.ArrayList(u8).init(std.testing.allocator);
    defer line.deinit();
    for (cases) |case| {
        line.items.len = 0;
        try line.appendSlice(case.in);
        koino.strings.removeTrailingBlankLines(&line);
        try std.testing.expectEqualStrings(case.out, line.items);
    }
}

test "unescapeHtml" {
    try testCases(koino.strings.unescapeHtml, &[_]Case{
        .{ .in = "&#116;&#101;&#115;&#116;", .out = "test" },
        .{ .in = "&#12486;&#12473;&#12488;", .out = "テスト" },
        .{ .in = "&#x74;&#x65;&#X73;&#X74;", .out = "test" },
        .{ .in = "&#x30c6;&#x30b9;&#X30c8;", .out = "テスト" },

        // "Although HTML5 does accept some entity references without a trailing semicolon
        // (such as &copy), these are not recognized here, because it makes the grammar too
        // ambiguous:"
        .{ .in = "&hellip;&eacute&Eacute;&rrarr;&oS;", .out = "…&eacuteÉ⇉Ⓢ" },
    });
}

test "cleanAutolink" {
    const email = try koino.strings.cleanAutolink(std.testing.allocator, "  hello&#x40;world.example ", .Email);
    defer std.testing.allocator.free(email);
    try std.testing.expectEqualStrings("mailto:hello@world.example", email);

    const uri = try koino.strings.cleanAutolink(std.testing.allocator, "  www&#46;com ", .URI);
    defer std.testing.allocator.free(uri);
    try std.testing.expectEqualStrings("www.com", uri);
}

test "cleanUrl" {
    const url = try koino.strings.cleanUrl(std.testing.allocator, "  \\(hello\\)&#x40;world  ");
    defer std.testing.allocator.free(url);
    try std.testing.expectEqualStrings("(hello)@world", url);
}

test "cleanTitle" {
    try testCases(koino.strings.cleanTitle, &[_]Case{
        .{ .in = "\\'title", .out = "'title" },
        .{ .in = "'title'", .out = "title" },
        .{ .in = "(&#x74;&#x65;&#X73;&#X74;)", .out = "test" },
        .{ .in = "\"&#x30c6;&#x30b9;&#X30c8;\"", .out = "テスト" },
        .{ .in = "'&hellip;&eacute&Eacute;&rrarr;&oS;'", .out = "…&eacuteÉ⇉Ⓢ" },
    });
}

test "normalizeLabel" {
    try testCases(koino.strings.normalizeLabel, &[_]Case{
        .{ .in = "Hello", .out = "hello" },
        .{ .in = "   Y        E  S  ", .out = "y e s" },
        .{ .in = "yÉs", .out = "yés" },
    });
}

test "toLower" {
    try testCases(koino.strings.toLower, &[_]Case{
        .{ .in = "Hello", .out = "hello" },
        .{ .in = "ΑαΒβΓγΔδΕεΖζΗηΘθΙιΚκΛλΜμ", .out = "ααββγγδδεεζζηηθθιικκλλμμ" },
        .{ .in = "АаБбВвГгДдЕеЁёЖжЗзИиЙйКкЛлМмНнОоПпРрСсТтУуФфХхЦцЧчШшЩщЪъЫыЬьЭэЮюЯя", .out = "ааббввггддееёёжжззииййккллммннооппррссттууффххццччшшщщъъыыььээююяя" },
    });
}

test "createMap" {
    comptime {
        const m = koino.strings.createMap("abcxyz");
        try std.testing.expect(m['a']);
        try std.testing.expect(m['b']);
        try std.testing.expect(m['c']);
        try std.testing.expect(!m['d']);
        try std.testing.expect(!m['e']);
        try std.testing.expect(!m['f']);
        try std.testing.expect(m['x']);
        try std.testing.expect(!m[0]);
    }
}
