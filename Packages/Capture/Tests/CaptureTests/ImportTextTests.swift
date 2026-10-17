import Foundation
import Testing
@testable import Capture

@Suite("Import text helpers")
struct ImportTextTests {
    @Test(arguments: [
        ("Serves 6", 6, nil),
        ("6 serving(s)", 6, nil),
        ("YIELD — 4 servings", 4, nil),
        ("4  Servings", 4, nil),
        ("8", 8, nil),
        ("Serves 8 to 10", 8, "Serves 8–10"),
        ("4 to 6 servings", 4, "Serves 4–6"),
        ("Servings: 4-6", 4, "Serves 4–6"),
        ("Makes 30 cookies", nil, "Makes 30 cookies"),
        ("1 loaf", nil, "1 loaf"),
    ] as [(String, Int?, String?)])
    func readsYields(text: String, servings: Int?, description: String?) {
        let reading = YieldText.parse(text)
        #expect(reading.servings == servings)
        #expect(reading.description == description)
    }

    @Test(arguments: [
        ("PT45M", 45 * 60), ("PT2H", 7_200), ("P1DT1H", 90_000), ("PT1H30M", 5_400),
        ("P0Y0M0DT0H20M0.000S", 1_200), ("PT195M", 11_700), ("P1DT4H30M", 102_600), ("pt10m", 600),
    ])
    func parsesISODurations(text: String, seconds: Int) {
        #expect(ISO8601Duration.parse(text) == .seconds(seconds))
    }

    @Test func rejectsNonDurations() {
        #expect(ISO8601Duration.parse("45 minutes") == nil)
        #expect(ISO8601Duration.parse("P") == nil)
    }

    @Test(arguments: [
        ("25 minutes", 1_500), ("55 minutes, plus overnight marination", 3_300), ("5 days", 432_000),
        ("4 hrs", 14_400), ("1 hour 10 minutes", 4_200), ("1½ hours", 5_400), ("1 1/2 hours", 5_400),
    ])
    func parsesWrittenDurations(text: String, seconds: Int) {
        #expect(TextDuration.parse(text) == .seconds(seconds))
    }

    @Test(arguments: [
        ("Orzo with Roasted Vegetables | Recipes", "Barefoot Contessa", "Orzo with Roasted Vegetables"),
        ("Lamb Tartare Recipe | Bon Appétit", "Bon Appétit", "Lamb Tartare"),
        ("Ultimate Peking Duck | ChefSteps", "ChefSteps", "Ultimate Peking Duck"),
        ("Barefoot Contessa | Orzo with Roasted Vegetables | Recipes", "Barefoot Contessa", "Orzo with Roasted Vegetables"),
        ("Pear and Ginger Cranberry Sauce Recipe", nil, "Pear and Ginger Cranberry Sauce"),
        ("The Recipe", nil, "The Recipe"),
    ] as [(String, String?, String)])
    func cleansTitles(raw: String, site: String?, expected: String) {
        #expect(ImportText.cleanTitle(raw, siteName: site) == expected)
    }

    @Test func cleansInlineMarkupAndEntities() {
        #expect(ImportText.inline("Salt &amp;amp; <b>pepper</b>&nbsp;to&#160;taste") == "Salt & pepper to taste")
        #expect(ImportText.ingredientLine("▢ 1 ¼ cups|284 ml soy sauce") == "1 ¼ cups (284 ml) soy sauce")
        #expect(ImportText.ingredientLine("- 2 eggs") == "2 eggs")
    }

    @Test func recognisesGroupHeadings() {
        for heading in ["For the Dressing:", "To Assemble:", "for the beef:", "To serve", "For the glaze"] {
            #expect(ImportText.isGroupHeading(heading), "\(heading)")
        }
        for line in ["2 cups flour", "Salt to taste", "Kosher salt", "For about 10 minutes, stir.", "1 cup sugar:"] {
            #expect(!ImportText.isGroupHeading(line), "\(line)")
        }
    }

    @Test func turnsPastedTextIntoURLs() {
        #expect(WebPageFetcher.webURL(from: "  https://www.seriouseats.com/x  ")?.host() == "www.seriouseats.com")
        #expect(WebPageFetcher.webURL(from: "seriouseats.com/roast-potatoes")?.absoluteString == "https://seriouseats.com/roast-potatoes")
        #expect(WebPageFetcher.webURL(from: "Try this: https://cooking.example/r/1 it's great")?.host() == "cooking.example")
        #expect(WebPageFetcher.webURL(from: "not a link") == nil)
        #expect(WebPageFetcher.webURL(from: "") == nil)
    }

    @Test func decodesLegacyEncodings() {
        let latin1 = "Crème brûlée".data(using: .isoLatin1)!
        #expect(WebPageFetcher.decode(latin1, encodingName: "iso-8859-1") == "Crème brûlée")
        #expect(WebPageFetcher.decode(Data("<meta charset=\"utf-8\">Jalapeño".utf8), encodingName: nil).hasSuffix("Jalapeño"))
    }
}

@Suite("HTML page reading")
struct HTMLPageTests {
    @Test func readsTagsRightAfterAnEmptyComment() {
        // Svelte pages write "<!---->" markers right before tags; the tag after one must still be read.
        let page = HTMLPage(html: #"<html><head><!----><title>T</title></head><body><!----><script type="application/ld+json">{"a":1}</script><!----><p>Hi</p></body></html>"#)
        #expect(page.title == "T")
        #expect(page.jsonLDBlocks == [#"{"a":1}"#])
        #expect(page.lines.map(\.text) == ["Hi"])
    }

    @Test func skipsHiddenNavigationAndScripts() {
        let page = HTMLPage(html: """
            <body><nav><a>Home</a></nav><div hidden><p>print copy</p></div><p aria-hidden="true">icon</p>
            <span class="sr-only">opens in a new window</span><script>var x = "<p>no</p>";</script>
            <style>p { color: red }</style><p>Visible <b>text</b></p><footer>© 2026</footer></body>
            """)
        #expect(page.lines.map(\.text) == ["Visible text"])
    }

    @Test func linesFollowBlocksBreaksAndSiblingInlines() {
        let page = HTMLPage(html: "<ul><li>2 cups <a>flour</a></li><li><span>Pekin duck</span><span>whole</span></li></ul><p>a<br>b</p><h2>Ingredients</h2><table><tr><td>1 cup</td><td>milk</td></tr></table>")
        #expect(page.lines.map(\.text) == ["2 cups flour", "Pekin duck whole", "a", "b", "Ingredients", "1 cup milk"])
        #expect(page.lines[0].tag == "li")
        #expect(page.lines[0].listID != nil)
        #expect(page.lines[0].listID == page.lines[1].listID)
        #expect(page.lines[4].headingLevel == 2)
    }

    @Test func decodesEntitiesAndKeepsFractions() {
        let page = HTMLPage(html: "<p>1&frac12; cups &amp; 1&#8260;2 tsp &#x2014; caf&eacute;&nbsp;au&nbsp;lait</p>")
        #expect(page.lines.first?.text == "1½ cups & 1⁄2 tsp — café au lait")
    }

    @Test func readsMetadata() {
        let page = HTMLPage(html: #"<head><meta property="og:site_name" content="Site"><meta name="author" content="A. Cook"><link rel="canonical" href="https://x.test/r"></head>"#)
        #expect(page.meta("og:site_name") == "Site")
        #expect(page.meta("author") == "A. Cook")
        #expect(page.canonicalURL == "https://x.test/r")
    }
}
