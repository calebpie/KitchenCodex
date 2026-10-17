import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A fetched web page.
public struct FetchedPage: Sendable {
    public var html: String
    /// Where the page ended up after redirects.
    public var url: URL
}

/// Fetches recipe pages and their cover images the way Safari would, so sites serve the same HTML
/// a cook sees.
public struct WebPageFetcher: Sendable {
    /// Safari on iPhone. iOS reports a frozen OS version in its user agent; the Safari version is current.
    public static let safariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Mobile/15E148 Safari/604.1"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Turns what a cook pastes ("seriouseats.com/x", " https://… ", text with a link in it) into a URL.
    public static func webURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // A bare address ("seriouseats.com/x") gets https, not the detector's http.
        if !trimmed.contains("://"), !trimmed.contains(" "), trimmed.contains("."),
           let url = URL(string: "https://" + trimmed), url.host()?.contains(".") == true {
            return url
        }
        #if canImport(Darwin)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
           let match = detector.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return url
        }
        #endif
        return nil
    }

    public func fetchPage(_ url: URL) async throws(WebImportError) -> FetchedPage {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { throw .invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(Self.safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await load(request)
        let mimeType = response.mimeType?.lowercased() ?? "text/html"
        guard mimeType.contains("html") || mimeType.contains("xml") || mimeType == "text/plain" else { throw .notAWebPage }
        return FetchedPage(html: Self.decode(data, encodingName: response.textEncodingName), url: response.url ?? url)
    }

    /// Image bytes, sent with the page as referrer since some image hosts refuse hotlinks without one.
    public func fetchImage(_ url: URL, referrer: URL? = nil) async throws(WebImportError) -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(Self.safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/png,image/jpeg,image/*;q=0.8", forHTTPHeaderField: "Accept")
        if let referrer { request.setValue(referrer.absoluteString, forHTTPHeaderField: "Referer") }
        let (data, response) = try await load(request)
        guard response.mimeType?.lowercased().hasPrefix("image/") ?? true else { throw .notAWebPage }
        return data
    }

    private func load(_ request: URLRequest) async throws(WebImportError) -> (Data, URLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .network((error as? URLError).map(Self.describe) ?? error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw .httpStatus(http.statusCode)
        }
        return (data, response)
    }

    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost: "You appear to be offline."
        case .timedOut: "The site took too long to answer."
        case .cannotFindHost, .dnsLookupFailed: "Check the address."
        case .secureConnectionFailed, .serverCertificateUntrusted: "The site's secure connection failed."
        default: error.localizedDescription
        }
    }

    /// HTTP charset, else a `<meta charset>` in the first few kilobytes, else UTF-8, else Windows Latin 1.
    static func decode(_ data: Data, encodingName: String?) -> String {
        if let name = encodingName ?? sniffCharset(data), let encoding = encoding(named: name),
           let text = String(data: data, encoding: encoding) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }

    private static func sniffCharset(_ data: Data) -> String? {
        let head = String(decoding: data.prefix(4_096), as: UTF8.self).lowercased()
        guard let range = head.range(of: #"charset\s*=\s*["']?([a-z0-9_-]+)"#, options: .regularExpression) else { return nil }
        return head[range].components(separatedBy: "=").last?.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
    }

    private static func encoding(named name: String) -> String.Encoding? {
        #if canImport(Darwin)
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        #else
        switch name.lowercased() {
        case "utf-8", "utf8": return .utf8
        case "iso-8859-1", "latin1": return .isoLatin1
        case "windows-1252": return .windowsCP1252
        default: return nil
        }
        #endif
    }
}
