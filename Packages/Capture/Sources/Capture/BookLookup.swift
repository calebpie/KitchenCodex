import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(os)
import os
#endif

/// An ISBN as printed on a cookbook (Flow C step 1), checked and normalised to ISBN-13.
public enum ISBN {
    /// The ISBN-13 for `text`, or nil when it isn't an ISBN. Takes ISBN-10 or ISBN-13 with or
    /// without hyphens and spaces, and a leading "ISBN" or "ISBN-13:" label as copyright pages
    /// print it; the check digit must be right. An ISBN-10 becomes its 978 ISBN-13.
    public static func normalized(_ text: String) -> String? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let label = body.range(of: #"^ISBN(?:-1[03])?\s*:?\s*"#, options: [.regularExpression, .caseInsensitive]) {
            body.removeSubrange(label)
        }
        let characters = Array(body.filter { !$0.isWhitespace && $0 != "-" }.uppercased())
        guard characters.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "X") }) else { return nil }
        switch characters.count {
        case 13:
            let digits = characters.compactMap(\.wholeNumberValue)
            guard digits.count == 13, String(characters.prefix(3)) == "978" || String(characters.prefix(3)) == "979",
                  checkDigit13(digits.prefix(12)) == digits[12] else { return nil }
            return String(characters)
        case 10:
            // X stands for 10 and only as the check digit.
            let digits = characters.prefix(9).compactMap(\.wholeNumberValue)
            guard digits.count == 9 else { return nil }
            let check = characters[9] == "X" ? 10 : characters[9].wholeNumberValue
            guard checkDigit10(digits) == check else { return nil }
            let body13 = [9, 7, 8] + digits
            return (body13 + [checkDigit13(body13[...])]).map(String.init).joined()
        default:
            return nil
        }
    }

    /// Weights 1, 3, 1, 3… over the first twelve digits.
    private static func checkDigit13(_ digits: ArraySlice<Int>) -> Int {
        let sum = digits.enumerated().reduce(0) { $0 + $1.element * ($1.offset.isMultiple(of: 2) ? 1 : 3) }
        return (10 - sum % 10) % 10
    }

    /// Weights 10 down to 2 over the first nine digits; 10 is written X.
    private static func checkDigit10(_ digits: [Int]) -> Int {
        let sum = digits.enumerated().reduce(0) { $0 + $1.element * (10 - $1.offset) }
        return (11 - sum % 11) % 11
    }
}

/// A book found by ISBN or title, for the cook to confirm before it goes on the shelf (Flow C step 2).
public struct BookCandidate: Sendable, Hashable, Identifiable {
    public enum Source: String, Sendable, Hashable {
        case openLibrary = "Open Library"
        case googleBooks = "Google Books"
    }

    /// The title without its subtitle: "The Food Lab", not "The Food Lab: Better Home Cooking…".
    public var title: String
    public var subtitle: String?
    public var authors: [String]
    public var publicationYear: Int?
    public var isbn13: String?
    public var coverURL: URL?
    public var source: Source
    /// The record's key at its source ("/books/OL…M", "/works/OL…W", a Google volume id).
    public var sourceKey: String

    public var id: String { "\(source.rawValue) \(sourceKey)" }

    public init(title: String, subtitle: String? = nil, authors: [String] = [], publicationYear: Int? = nil, isbn13: String? = nil, coverURL: URL? = nil, source: Source, sourceKey: String) {
        self.title = title
        self.subtitle = subtitle
        self.authors = authors
        self.publicationYear = publicationYear
        self.isbn13 = isbn13
        self.coverURL = coverURL
        self.source = source
        self.sourceKey = sourceKey
    }
}

/// Why a lookup gave no book, so the sheet can say which.
public enum BookLookupError: Error, Equatable, Sendable {
    /// The digits aren't an ISBN, or the check digit is wrong. No request was made.
    case invalidISBN
    /// No record for the ISBN, or no book with that title.
    case notFound
    /// The device is offline or the service can't be reached.
    case offline
    /// The service answered with an error or with something other than the expected JSON.
    case badResponse
}

/// Book metadata and covers for Add Cookbook (Flow C steps 1–2, 01 §2.6): Open Library first, which
/// needs no key; Google Books only when a key is configured, and only after Open Library has nothing.
public struct BookLookup: Sendable {
    /// Fetches one URL: the body, or nil when the server has nothing there (404).
    public typealias Loader = @Sendable (URL) async throws(BookLookupError) -> Data?

    private let load: Loader
    private let googleBooksKey: String?

    /// Looks books up over `session`. With no `googleBooksKey`, Google Books is never asked.
    public init(session: URLSession = .shared, googleBooksKey: String? = nil) {
        self.init(googleBooksKey: googleBooksKey, loader: Self.loader(session: session))
    }

    /// Looks books up through `loader`; tests pass recorded responses.
    public init(googleBooksKey: String? = nil, loader: @escaping Loader) {
        self.load = loader
        self.googleBooksKey = googleBooksKey.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The edition with this ISBN (10 or 13 digits), with its authors from the edition or its work.
    public func lookup(isbn text: String) async throws(BookLookupError) -> BookCandidate {
        guard let isbn = ISBN.normalized(text) else { throw .invalidISBN }
        do throws(BookLookupError) {
            return try await openLibraryEdition(isbn: isbn)
        } catch {
            guard error == .notFound, let googleBooksKey else { throw error }
            guard let volume = try await googleBooks(query: "isbn:\(isbn)", key: googleBooksKey).first else { throw .notFound }
            return volume
        }
    }

    /// The cover's image bytes, or nil when there is none (Open Library answers 404 for a missing
    /// cover when asked with `default=false`, and a tiny placeholder otherwise).
    public func coverImage(at url: URL) async throws(BookLookupError) -> Data? {
        guard let data = try await load(url), data.count >= 1_000 else { return nil }
        return data
    }

    // MARK: - Open Library

    private func openLibraryEdition(isbn: String) async throws(BookLookupError) -> BookCandidate {
        // Redirects to the edition's own record, /books/OL…M.json.
        guard let data = try await load(Self.openLibraryURL("/isbn/\(isbn)")) else { throw .notFound }
        let edition = try Self.decode(OpenLibrary.Edition.self, from: data)
        guard let fullTitle = edition.title?.trimmed, !fullTitle.isEmpty else { throw .badResponse }

        // Most editions name their authors only through the work.
        var authorKeys = edition.authors?.compactMap(\.key) ?? []
        var work: OpenLibrary.Work?
        if authorKeys.isEmpty, let workKey = edition.works?.first?.key {
            work = try? await fetch(OpenLibrary.Work.self, at: Self.openLibraryURL(workKey))
            authorKeys = work?.authors?.compactMap(\.author?.key) ?? []
        }
        let authors = await authorNames(authorKeys)

        let (title, titleSubtitle) = Self.splitSubtitle(fullTitle)
        let coverURL = edition.covers?.first { $0 > 0 }.map(Self.coverURL(id:))
            ?? URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg?default=false")
        return BookCandidate(
            title: title,
            subtitle: edition.subtitle?.trimmed.nonEmpty ?? titleSubtitle ?? work?.subtitle?.trimmed.nonEmpty,
            authors: authors,
            publicationYear: Self.year(in: edition.publish_date) ?? Self.year(in: work?.first_publish_date),
            isbn13: isbn,
            coverURL: coverURL,
            source: .openLibrary,
            sourceKey: edition.key ?? "/isbn/\(isbn)"
        )
    }

    /// The authors' names in the record's order; one that can't be fetched is left out.
    private func authorNames(_ keys: [String]) async -> [String] {
        let fetched = await withTaskGroup(of: (Int, String?).self) { group in
            for (index, key) in keys.enumerated() {
                group.addTask {
                    let author = try? await fetch(OpenLibrary.Author.self, at: Self.openLibraryURL(key))
                    return (index, author?.name?.trimmed.nonEmpty ?? author?.personal_name?.trimmed.nonEmpty)
                }
            }
            var names: [Int: String] = [:]
            for await (index, name) in group { names[index] = name }
            return names
        }
        var seen = Set<String>()
        return keys.indices.compactMap { fetched[$0] }.filter { seen.insert($0).inserted }
    }

    private static func openLibraryURL(_ key: String) -> URL {
        URL(string: "https://openlibrary.org\(key).json")!
    }

    private static func coverURL(id: Int) -> URL {
        URL(string: "https://covers.openlibrary.org/b/id/\(id)-L.jpg")!
    }

    // MARK: - Google Books

    /// Google Books volumes for a `q` query ("isbn:…"). Only called with a key.
    private func googleBooks(query: String, key: String) async throws(BookLookupError) -> [BookCandidate] {
        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "printType", value: "books"),
            URLQueryItem(name: "maxResults", value: "20"),
            URLQueryItem(name: "key", value: key),
        ]
        guard let data = try await load(components.url!) else { throw .notFound }
        let results = try Self.decode(GoogleBooks.Volumes.self, from: data)
        return (results.items ?? []).compactMap { volume in
            guard let info = volume.volumeInfo, let fullTitle = info.title?.trimmed, !fullTitle.isEmpty else { return nil }
            let (title, titleSubtitle) = Self.splitSubtitle(fullTitle)
            let identifiers = info.industryIdentifiers ?? []
            let isbns = identifiers.filter { $0.type == "ISBN_13" } + identifiers.filter { $0.type == "ISBN_10" }
            // Google serves thumbnails over http; App Transport Security wants https.
            let thumbnail = (info.imageLinks?.thumbnail ?? info.imageLinks?.smallThumbnail)
                .map { $0.replacingOccurrences(of: "http://", with: "https://") }
            return BookCandidate(
                title: title,
                subtitle: info.subtitle?.trimmed.nonEmpty ?? titleSubtitle,
                authors: info.authors ?? [],
                publicationYear: Self.year(in: info.publishedDate),
                isbn13: isbns.lazy.compactMap { $0.identifier.flatMap(ISBN.normalized) }.first,
                coverURL: thumbnail.flatMap(URL.init(string:)),
                source: .googleBooks,
                sourceKey: volume.id ?? fullTitle
            )
        }
    }

    // MARK: - Reading

    private func fetch<T: Decodable>(_ type: T.Type, at url: URL) async throws(BookLookupError) -> T {
        guard let data = try await load(url) else { throw .notFound }
        return try Self.decode(type, from: data)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(BookLookupError) -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            log("Book lookup: couldn't read \(T.self): \(error)")
            throw .badResponse
        }
    }

    /// Why a lookup failed, in the app's log (category "books"); the sheet shows only the kind.
    static func log(_ message: String) {
        #if canImport(os)
        Logger(subsystem: "com.calebpietrafesa.KitchenCodex", category: "books").error("\(message, privacy: .public)")
        #endif
    }

    /// "The Food Lab: Better Home Cooking Through Science" → ("The Food Lab", "Better Home Cooking
    /// Through Science"). Open Library often folds the subtitle into the title.
    static func splitSubtitle(_ title: String) -> (String, String?) {
        guard let colon = title.range(of: ": ") else { return (title, nil) }
        let main = title[..<colon.lowerBound].trimmed
        let rest = title[colon.upperBound...].trimmed
        guard !main.isEmpty, !rest.isEmpty else { return (title, nil) }
        return (main, rest)
    }

    /// The first plausible year in a free-text date: "Sep 21, 2015", "c2015", "2015-09-21".
    static func year(in text: String?) -> Int? {
        guard let text, let match = text.firstMatch(of: /(?:^|[^0-9])(1[5-9][0-9]{2}|20[0-9]{2})(?![0-9])/) else { return nil }
        return Int(match.1)
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
        .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut,
    ]

    private static func loader(session: URLSession) -> Loader {
        { (url: URL) async throws(BookLookupError) -> Data? in
            var request = URLRequest(url: url, timeoutInterval: 15)
            // Open Library asks apps to name themselves.
            request.setValue("KitchenCodex/1.0 (iOS; book lookup)", forHTTPHeaderField: "User-Agent")
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch let error as URLError where offlineCodes.contains(error.code) {
                log("Book lookup: \(url.absoluteString) unreachable: \(error.code.rawValue)")
                throw .offline
            } catch {
                log("Book lookup: \(url.absoluteString) failed: \(error)")
                throw .badResponse
            }
            guard let http = response as? HTTPURLResponse else { return data }
            if http.statusCode == 404 { return nil }
            guard (200..<300).contains(http.statusCode) else {
                log("Book lookup: \(url.absoluteString) answered \(http.statusCode)")
                throw .badResponse
            }
            return data
        }
    }
}

// MARK: - Response shapes

/// Open Library's JSON, only the fields Add Cookbook reads. Field names are the service's own.
private enum OpenLibrary {
    struct Key: Decodable { var key: String? }

    struct Edition: Decodable {
        var key: String?
        var title: String?
        var subtitle: String?
        var authors: [Key]?
        var works: [Key]?
        var publish_date: String?
        var covers: [Int]?
    }

    struct Work: Decodable {
        struct Role: Decodable { var author: Key? }
        var subtitle: String?
        var authors: [Role]?
        var first_publish_date: String?
    }

    struct Author: Decodable {
        var name: String?
        var personal_name: String?
    }
}

/// Google Books' volumes JSON, only the fields Add Cookbook reads.
private enum GoogleBooks {
    struct Volumes: Decodable {
        var items: [Volume]?
    }

    struct Volume: Decodable {
        var id: String?
        var volumeInfo: Info?
    }

    struct Info: Decodable {
        struct Identifier: Decodable {
            var type: String?
            var identifier: String?
        }

        struct ImageLinks: Decodable {
            var smallThumbnail: String?
            var thumbnail: String?
        }

        var title: String?
        var subtitle: String?
        var authors: [String]?
        var publishedDate: String?
        var industryIdentifiers: [Identifier]?
        var imageLinks: ImageLinks?
    }
}

private extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
