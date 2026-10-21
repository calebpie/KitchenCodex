import Foundation

/// Prose kept beside the recipes it informs (02 §4.2), as it arrives from a web page or a scanned
/// page, before it becomes a `Reference`: an article with its headed sections, a chapter opener, a
/// technique write-up, or a glossary page whose sections are its entries, one per term.
public struct ImportedReference: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        /// An essay or article saved from the web (Article markup, no recipe).
        case article
        /// A cookbook chapter or chapter opener.
        case chapter
        /// A technique written up on its own ("How to Fillet a Flat Fish").
        case technique
        /// A glossary page: each section is one term and its definition, so a page pointer opens
        /// the entry.
        case glossary
    }

    /// One headed part, in order.
    public struct Section: Sendable, Equatable {
        /// Empty for the opening text before the first heading.
        public var heading: String
        /// Paragraphs separated by blank lines.
        public var body: String

        public init(heading: String = "", body: String) {
            self.heading = heading
            self.body = body
        }
    }

    public var title: String
    public var author: String?
    public var siteName: String?
    public var sourceURL: URL?
    public var imageURL: URL?
    public var kind: Kind
    public var sections: [Section]
    /// Why the page read as reference reading ("a glossary page: 12 entries"), for the processing
    /// sheet; nil for the web.
    public var reason: String?
    /// 0…1.
    public var confidence: Double

    public init(title: String, author: String? = nil, siteName: String? = nil, sourceURL: URL? = nil, imageURL: URL? = nil, kind: Kind, sections: [Section], reason: String? = nil, confidence: Double = 0.8) {
        self.title = title
        self.author = author
        self.siteName = siteName
        self.sourceURL = sourceURL
        self.imageURL = imageURL
        self.kind = kind
        self.sections = sections
        self.reason = reason
        self.confidence = confidence
    }

    public var characterCount: Int { sections.reduce(0) { $0 + $1.body.count } }

    /// The sections' headings, for a summary.
    public var headings: [String] { sections.map(\.heading).filter { !$0.isEmpty } }
}
