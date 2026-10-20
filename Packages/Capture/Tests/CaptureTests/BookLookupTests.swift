import Foundation
import Synchronization
import Testing
@testable import Capture

/// Add Cookbook's lookups over synthetic JSON shaped like Open Library's and Google Books'
/// responses (`Fixtures/Synthetic/openlibrary-*.json`, `googlebooks-*.json`); nothing here reaches
/// the network.
@Suite("Book lookup")
struct BookLookupTests {
    /// Answers each request from a fixture by the URL's path, records what was asked, and answers
    /// 404 (nil) for anything it doesn't know.
    final class RecordedService: Sendable {
        let responses: [String: String]
        let failure: BookLookupError?
        private let requested = Mutex<[URL]>([])

        init(_ responses: [String: String], failure: BookLookupError? = nil) {
            self.responses = responses
            self.failure = failure
        }

        var requests: [URL] { requested.withLock { $0 } }

        func lookup(googleBooksKey: String? = nil) -> BookLookup {
            BookLookup(googleBooksKey: googleBooksKey) { url throws(BookLookupError) in
                self.requested.withLock { $0.append(url) }
                if let failure = self.failure { throw failure }
                let key = url.host() == "www.googleapis.com" ? "google" : url.path()
                guard let name = self.responses[key] else { return nil }
                do {
                    return try Fixtures.syntheticData(name)
                } catch {
                    return nil
                }
            }
        }
    }

    /// A fresh service per test, since tests run in parallel and each checks its own requests.
    static var exampleKitchen: RecordedService { RecordedService([
        "/isbn/9780000000019.json": "openlibrary-edition.json",
        "/works/OL1000001W.json": "openlibrary-work.json",
        "/authors/OL1000001A.json": "openlibrary-author-pat.json",
    ]) }

    // MARK: - ISBN

    @Test func isbnThirteenAndTenNormaliseToThirteen() {
        #expect(ISBN.normalized("9780306406157") == "9780306406157")
        #expect(ISBN.normalized("978-0-306-40615-7") == "9780306406157")
        #expect(ISBN.normalized(" 978 0 306 40615 7 ") == "9780306406157")
        #expect(ISBN.normalized("ISBN-13: 978-0-306-40615-7") == "9780306406157")
        #expect(ISBN.normalized("ISBN 0-306-40615-2") == "9780306406157")
        #expect(ISBN.normalized("0306406152") == "9780306406157")
        // X is the check digit 10, either case.
        #expect(ISBN.normalized("080442957X") == "9780804429573")
        #expect(ISBN.normalized("0-8044-2957-x") == "9780804429573")
        #expect(ISBN.normalized("979-10-9876543-8") == "9791098765438")
    }

    @Test func isbnWithAWrongCheckDigitOrShapeIsRejected() {
        #expect(ISBN.normalized("9780306406158") == nil) // check digit off by one
        #expect(ISBN.normalized("0306406153") == nil)
        #expect(ISBN.normalized("9770306406150") == nil) // 977 is an ISSN prefix, not a book
        #expect(ISBN.normalized("08044X2957") == nil) // X only as the check digit
        #expect(ISBN.normalized("978030640615") == nil) // twelve digits
        #expect(ISBN.normalized("97803064061577") == nil)
        #expect(ISBN.normalized("97803064O6157") == nil) // a letter O
        #expect(ISBN.normalized("") == nil)
    }

    @Test func yearsAndSubtitlesFromFreeText() {
        #expect(BookLookup.year(in: "Sep 21, 2015") == 2015)
        #expect(BookLookup.year(in: "c1998") == 1998)
        #expect(BookLookup.year(in: "2008-05-01") == 2008)
        #expect(BookLookup.year(in: "320 pages") == nil)
        #expect(BookLookup.year(in: nil) == nil)
        #expect(BookLookup.splitSubtitle("Plenty: Vibrant Recipes") == ("Plenty", "Vibrant Recipes"))
        #expect(BookLookup.splitSubtitle("Salt, Fat, Acid, Heat") == ("Salt, Fat, Acid, Heat", nil))
        #expect(BookLookup.splitSubtitle("Ratio:") == ("Ratio:", nil))
    }

    // MARK: - By ISBN

    @Test func hitByISBNTakesAuthorsFromTheWork() async throws {
        let service = Self.exampleKitchen
        let book = try await service.lookup().lookup(isbn: "978-0-00-000001-9")
        #expect(book.title == "The Example Kitchen")
        #expect(book.subtitle == "Everyday Cooking for Company")
        #expect(book.authors == ["Pat Example"])
        #expect(book.publicationYear == 2015)
        #expect(book.isbn13 == "9780000000019")
        #expect(book.coverURL?.absoluteString == "https://covers.openlibrary.org/b/id/10000001-L.jpg")
        #expect(book.source == .openLibrary)
        #expect(book.sourceKey == "/books/OL1000001M")
        #expect(service.requests.map { $0.path() } == ["/isbn/9780000000019.json", "/works/OL1000001W.json", "/authors/OL1000001A.json"])
    }

    @Test func anISBNTenIsLookedUpAsItsThirteen() async throws {
        let service = Self.exampleKitchen
        let book = try await service.lookup().lookup(isbn: "0000000019")
        #expect(book.isbn13 == "9780000000019")
        #expect(service.requests.first?.absoluteString == "https://openlibrary.org/isbn/9780000000019.json")
    }

    @Test func aBookWithTwoAuthorsKeepsTheirOrder() async throws {
        let service = RecordedService([
            "/isbn/9780000000033.json": "openlibrary-edition-two-authors.json",
            "/authors/OL1000001A.json": "openlibrary-author-pat.json",
            "/authors/OL1000002A.json": "openlibrary-author-sam.json",
        ])
        let book = try await service.lookup().lookup(isbn: "9780000000033")
        #expect(book.title == "Two Cooks")
        #expect(book.subtitle == "Recipes from a Shared Table")
        #expect(book.authors == ["Pat Example", "Sam Sample"])
        #expect(book.publicationYear == 2019)
        // No cover id (Open Library writes -1 for a removed one), so the cover by ISBN, which
        // answers 404 rather than a blank image when there is none.
        #expect(book.coverURL?.absoluteString == "https://covers.openlibrary.org/b/isbn/9780000000033-L.jpg?default=false")
        // The edition names its authors, so the work isn't fetched.
        #expect(!service.requests.contains { $0.path().hasPrefix("/works/") })
    }

    @Test func anAuthorThatCantBeFetchedIsLeftOut() async throws {
        let service = RecordedService([
            "/isbn/9780000000033.json": "openlibrary-edition-two-authors.json",
            "/authors/OL1000002A.json": "openlibrary-author-sam.json",
        ])
        let book = try await service.lookup().lookup(isbn: "9780000000033")
        #expect(book.authors == ["Sam Sample"])
    }

    @Test func aMissIsNotFound() async {
        let service = RecordedService([:])
        await #expect(throws: BookLookupError.notFound) {
            try await service.lookup().lookup(isbn: "9780000000040")
        }
        // Without a key Google Books is never asked.
        #expect(service.requests.count == 1)
    }

    @Test func aMalformedResponseIsABadResponse() async {
        let service = RecordedService(["/isbn/9780000000019.json": "openlibrary-edition-malformed.json"])
        await #expect(throws: BookLookupError.badResponse) {
            try await service.lookup().lookup(isbn: "9780000000019")
        }
        // Valid JSON without a title is no book either.
        let untitled = RecordedService(["/isbn/9780000000019.json": "openlibrary-author-pat.json"])
        await #expect(throws: BookLookupError.badResponse) {
            try await untitled.lookup().lookup(isbn: "9780000000019")
        }
    }

    @Test func anInvalidISBNAsksNothing() async {
        let service = Self.exampleKitchen
        await #expect(throws: BookLookupError.invalidISBN) {
            try await service.lookup().lookup(isbn: "9780000000018")
        }
        #expect(service.requests.isEmpty)
    }

    @Test func offlineIsPassedOn() async {
        let service = RecordedService([:], failure: .offline)
        await #expect(throws: BookLookupError.offline) {
            try await service.lookup().lookup(isbn: "9780000000019")
        }
    }

    @Test func googleBooksAnswersOnlyWithAKeyAndOnlyAfterOpenLibrary() async throws {
        let service = RecordedService(["google": "googlebooks-volumes.json"])
        let book = try await service.lookup(googleBooksKey: "test-key").lookup(isbn: "0306406152")
        #expect(book.source == .googleBooks)
        #expect(book.title == "A Small-Press Cookbook")
        #expect(book.authors == ["Robin Placeholder"])
        #expect(book.publicationYear == 2008)
        #expect(book.isbn13 == "9780306406157")
        #expect(book.coverURL?.scheme == "https")
        let google = try #require(service.requests.last)
        #expect(service.requests.first?.host() == "openlibrary.org")
        #expect(google.host() == "www.googleapis.com")
        #expect(google.query()?.contains("q=isbn:9780306406157") == true)
        #expect(google.query()?.contains("key=test-key") == true)

        await #expect(throws: BookLookupError.notFound) {
            try await service.lookup(googleBooksKey: nil).lookup(isbn: "0306406152")
        }
        await #expect(throws: BookLookupError.notFound) {
            try await service.lookup(googleBooksKey: "").lookup(isbn: "0306406152")
        }
    }

    // MARK: - Covers

    @Test func aMissingOrPlaceholderCoverIsNone() async throws {
        // A kilobyte or more stands in for an image; Open Library's placeholder is smaller.
        let lookup = BookLookup { url throws(BookLookupError) -> Data? in
            switch url.lastPathComponent {
            case "1-L.jpg": Data(count: 2_000)
            case "2-L.jpg": Data(count: 100)
            default: nil
            }
        }
        #expect(try await lookup.coverImage(at: URL(string: "https://covers.openlibrary.org/b/id/1-L.jpg")!) != nil)
        #expect(try await lookup.coverImage(at: URL(string: "https://covers.openlibrary.org/b/id/2-L.jpg")!) == nil)
        #expect(try await lookup.coverImage(at: URL(string: "https://covers.openlibrary.org/b/id/3-L.jpg")!) == nil)
    }
}
