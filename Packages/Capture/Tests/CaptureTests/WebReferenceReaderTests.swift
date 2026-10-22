import Foundation
import Testing
@testable import Capture

/// Save as Reference from the web (02 §4.2, 04 §5.1 "Import reading"): a page with Article markup
/// and no recipe reads as an article with its headed sections. The pages are made up.
@Suite("Web references")
struct WebReferenceReaderTests {
    static let paragraph = "Brown butter is what happens when you keep going past melted: the milk solids toast, the water cooks off and the whole pan smells of hazelnuts. It takes four minutes and changes everything it touches."
    static let second = "Watch the foam, not the clock. When it quiets and the specks underneath turn the colour of a walnut shell, pour it out at once; the pan holds enough heat to burn it."

    static func page(jsonLD: String, body: String, title: String = "On Brown Butter") -> String {
        """
        <html><head><title>\(title) | Test Kitchen Notes</title>
        <meta property="og:site_name" content="Test Kitchen Notes"><meta name="author" content="Pat Example">
        <meta property="og:image" content="https://example.test/img/butter.jpg">
        <script type="application/ld+json">\(jsonLD)</script></head>
        <body><nav><a href="/">Home</a> <a href="/recipes">Recipes</a></nav>
        <article><h1>\(title)</h1><p class="byline">By Pat Example</p><p>Published March 3, 2026</p>
        \(body)
        </article>
        <h2>Comments</h2><p>Lovely piece, thank you for writing it up so clearly for the rest of us at home.</p>
        <footer>© Test Kitchen Notes. All rights reserved.</footer></body></html>
        """
    }

    @Test func readsAnArticleUnderItsHeadings() throws {
        let html = Self.page(
            jsonLD: #"{"@context":"https://schema.org","@type":"NewsArticle","headline":"On Brown Butter","author":{"@type":"Person","name":"Pat Example"}}"#,
            body: "<p>\(Self.paragraph)</p><h2>When to stop</h2><p>\(Self.second)</p><h3>Keeping it:</h3><p>\(Self.paragraph) \(Self.second)</p>"
        )
        let reference = try #require(WebReferenceReader.read(html: html, url: URL(string: "https://example.test/notes/brown-butter")))
        #expect(reference.title == "On Brown Butter")
        #expect(reference.author == "Pat Example")
        #expect(reference.siteName == "Test Kitchen Notes")
        #expect(reference.kind == .article)
        #expect(reference.sourceURL?.absoluteString == "https://example.test/notes/brown-butter")
        #expect(reference.imageURL?.absoluteString == "https://example.test/img/butter.jpg")
        // The opening text, then one section per heading as the page cases them (a colon dropped),
        // the comments left out.
        #expect(reference.sections.map(\.heading) == ["", "When to stop", "Keeping it"])
        #expect(reference.sections[0].body == Self.paragraph)
        #expect(reference.sections[1].body == Self.second)
        #expect(!reference.sections.contains { $0.body.contains("Lovely piece") })
        #expect(reference.confidence == 0.8)
    }

    /// ux-notes row 130: the article's figures in reading order, each after the section it follows,
    /// captioned from its alt text or its caption line; icons, avatars and images set small left out.
    @Test func keepsTheArticlesFiguresBetweenItsSections() throws {
        let html = Self.page(
            jsonLD: #"{"@type":"Article","headline":"On Brown Butter"}"#,
            body: """
            <img src="/img/avatar-pat.jpg" class="author-avatar" alt="Pat Example">
            <p>\(Self.paragraph)</p>
            <figure><img src="/img/pan.jpg" alt="Butter foaming in a steel pan"></figure>
            <h2>When to stop</h2>
            <p>\(Self.second)</p>
            <figure><img data-src="/img/specks.jpg" src="data:image/gif;base64,R0lGOD"><figcaption>The specks the colour of a walnut shell</figcaption></figure>
            <img src="/img/share-icon.png" alt="Share" width="24" height="24">
            <figure><img src="/img/jar.jpg" alt="A jar of it, cooled"></figure>
            <h2>Keeping it</h2>
            <p>\(Self.paragraph)</p>
            """
        )
        let reference = try #require(WebReferenceReader.read(html: html, url: URL(string: "https://example.test/notes/brown-butter")))
        #expect(reference.sections.map(\.heading) == ["", "When to stop", "Keeping it"])
        #expect(reference.figures.map(\.url.lastPathComponent) == ["pan.jpg", "specks.jpg", "jar.jpg"])
        #expect(reference.figures.map(\.caption) == ["Butter foaming in a steel pan", "The specks the colour of a walnut shell", "A jar of it, cooled"])
        #expect(reference.figures.map(\.section) == [0, 1, 1])
    }

    @Test func theImporterOffersTheArticleOnlyWhenNoRecipeWasFound() throws {
        let html = Self.page(
            jsonLD: #"{"@type":"Article","headline":"On Brown Butter"}"#,
            body: "<p>\(Self.paragraph)</p><p>\(Self.second)</p>"
        )
        let extraction = WebRecipeImporter.extract(html: html, url: URL(string: "https://example.test/notes/brown-butter"))
        #expect(extraction.recipe == nil)
        #expect(!WebRecipeImporter.wantsModel(extraction))
        #expect(extraction.article?.title == "On Brown Butter")
        #expect(extraction.article?.sections.count == 1)

        // The same markup around a recipe read from the page text: the recipe path, no article.
        let recipe = Self.page(
            jsonLD: #"{"@type":"Article","headline":"Brown Butter Cookies"}"#,
            body: "<h2>Ingredients</h2><ul><li>1 cup unsalted butter</li><li>2 cups flour</li><li>1 teaspoon kosher salt</li><li>2 eggs</li></ul><h2>Method</h2><ol><li>Brown the butter in a wide pan and let it cool a little.</li><li>Whisk in the flour, salt and eggs, then scoop and bake at 350°F for 11 minutes.</li></ol>",
            title: "Brown Butter Cookies"
        )
        let cookies = WebRecipeImporter.extract(html: recipe, url: URL(string: "https://example.test/notes/cookies"))
        #expect(cookies.recipe?.method == .pageText)
        #expect(cookies.recipe?.ingredients.count == 4)
        #expect(cookies.article == nil)
    }

    @Test func fallsBackToTheMarkupsBodyAndRefusesTooLittle() throws {
        let body = (Self.paragraph + "\n\n" + Self.second).replacingOccurrences(of: "\n", with: "\\n")
        let scripted = Self.page(jsonLD: #"{"@type":"BlogPosting","headline":"On Brown Butter","articleBody":"\#(body)"}"#, body: "<div id=\"app\"></div>")
        let reference = try #require(WebReferenceReader.read(html: scripted, url: nil))
        #expect(reference.sections.count == 1)
        #expect(reference.sections[0].body.hasPrefix("Brown butter is what happens"))
        #expect(reference.confidence == 0.7)

        // No Article markup: nothing, however much prose.
        let plain = "<html><head><title>Notes</title></head><body><h1>Notes</h1><p>\(Self.paragraph)</p><p>\(Self.second)</p></body></html>"
        #expect(WebReferenceReader.read(html: plain, url: nil) == nil)
        // Article markup over a few lines of links: nothing.
        let thin = Self.page(jsonLD: #"{"@type":"Article","headline":"On Brown Butter"}"#, body: "<p>Read the full story in the magazine.</p>")
        #expect(WebReferenceReader.read(html: thin, url: nil) == nil)
    }
}
