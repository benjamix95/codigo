import XCTest
@testable import CoderEngine

extension WebToolsTests {
    // MARK: - HTMLToMarkdown

    func testConvertHeadings() {
        let html = "<h1>Title</h1><h2>Subtitle</h2><h3>Section</h3>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("# Title"), "Expected h1 conversion, got: \(md)")
        XCTAssertTrue(md.contains("## Subtitle"), "Expected h2 conversion, got: \(md)")
        XCTAssertTrue(md.contains("### Section"), "Expected h3 conversion, got: \(md)")
    }

    func testConvertLinks() {
        let html = #"<a href="https://example.com">Click here</a>"#
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("[Click here](https://example.com)"), "Expected link conversion, got: \(md)")
    }

    func testConvertEmphasis() {
        let html = "<strong>bold</strong> and <em>italic</em>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("**bold**"), "Expected bold conversion, got: \(md)")
        XCTAssertTrue(md.contains("*italic*"), "Expected italic conversion, got: \(md)")
    }

    func testConvertInlineCode() {
        let html = "<code>let x = 42</code>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("`let x = 42`"), "Expected code conversion, got: \(md)")
    }

    func testConvertCodeBlock() {
        let html = "<pre>func hello() {\n  print(\"hi\")\n}</pre>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("```"), "Expected code block markers, got: \(md)")
        XCTAssertTrue(md.contains("func hello()"), "Expected code block content, got: \(md)")
    }

    func testConvertList() {
        let html = "<ul><li>Apple</li><li>Banana</li></ul>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("- Apple"), "Expected list item, got: \(md)")
        XCTAssertTrue(md.contains("- Banana"), "Expected list item, got: \(md)")
    }

    func testConvertBlockquote() {
        let html = "<blockquote>Famous quote</blockquote>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("> Famous quote"), "Expected blockquote, got: \(md)")
    }

    func testConvertHorizontalRule() {
        let html = "<p>Before</p><hr/><p>After</p>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("---"), "Expected horizontal rule, got: \(md)")
    }

    func testStripsScriptAndStyleTags() {
        let html = "<html><body><script>alert('xss')</script><style>.foo{color:red}</style><p>Content</p></body></html>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertFalse(md.contains("alert"), "Script content should be removed")
        XCTAssertFalse(md.contains("color:red"), "Style content should be removed")
        XCTAssertTrue(md.contains("Content"), "Regular content should be preserved")
    }

    func testStripsNavAndFooter() {
        let html = "<body><nav>Menu items</nav><main><p>Article</p></main><footer>Copyright</footer></body>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertFalse(md.contains("Menu items"), "Nav should be stripped")
        XCTAssertFalse(md.contains("Copyright"), "Footer should be stripped")
        XCTAssertTrue(md.contains("Article"), "Main content should be preserved")
    }

    func testExtractsArticleContent() {
        let html = "<html><body><div>Sidebar</div><article><p>Article content</p></article></body></html>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("Article content"), "Article content should be extracted")
    }

    func testExtractsMainContent() {
        let html = "<html><body><div>Header</div><main><p>Main content</p></main></body></html>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("Main content"), "Main content should be extracted")
    }

    func testDecodesHTMLEntities() {
        let html = "<p>Tom &amp; Jerry &lt;3&gt; &quot;Cartoons&quot; &copy; 2024</p>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("Tom & Jerry"), "Should decode &amp;")
        XCTAssertTrue(md.contains("<3>"), "Should decode &lt; and &gt;")
        XCTAssertTrue(md.contains("\"Cartoons\""), "Should decode &quot;")
        XCTAssertTrue(md.contains("©"), "Should decode &copy;")
    }

    func testDecodesNumericEntities() {
        let html = "<p>&#65;&#66;&#67;</p>"  // ABC
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("ABC"), "Should decode numeric entities, got: \(md)")
    }

    func testDecodesHexEntities() {
        let html = "<p>&#x41;&#x42;&#x43;</p>"  // ABC
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("ABC"), "Should decode hex entities, got: \(md)")
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(HTMLToMarkdown.convert(""), "")
    }

    func testStripTagsBasic() {
        let html = "<b>bold</b> and <i>italic</i>"
        let stripped = HTMLToMarkdown.stripTags(html)
        XCTAssertEqual(stripped, "bold and italic")
    }

    func testStripTagsDecodesEntities() {
        let html = "Tom &amp; Jerry"
        let stripped = HTMLToMarkdown.stripTags(html)
        XCTAssertEqual(stripped, "Tom & Jerry")
    }

    func testStripTagsTrims() {
        let html = "  <span>  hello  </span>  "
        let stripped = HTMLToMarkdown.stripTags(html)
        XCTAssertEqual(stripped, "hello")
    }

    func testCollapsesExcessiveWhitespace() {
        let html = "<p>Line one</p>\n\n\n\n\n<p>Line two</p>"
        let md = HTMLToMarkdown.convert(html)
        // Should not have more than 2 consecutive newlines
        XCTAssertFalse(md.contains("\n\n\n"), "Should collapse excessive newlines, got: \(md)")
    }
}
