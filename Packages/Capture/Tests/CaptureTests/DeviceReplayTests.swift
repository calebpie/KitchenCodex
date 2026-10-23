import CoreGraphics
import Foundation
import Testing
@testable import Capture

/// Where the device's Read Fixtures reports are: `RECIPE_CODEX_DEVICE_REPORTS` (a report's JSON or a
/// folder of them), else the newest `iphone-*` folder under `Docs/Fixtures/Private/Review`. The
/// reports hold page text and stay there (gitignored).
enum DeviceReports {
    static let files: [URL] = {
        let manager = FileManager.default
        func jsonFiles(in folder: URL) -> [URL] {
            ((try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        if let path = ProcessInfo.processInfo.environment["RECIPE_CODEX_DEVICE_REPORTS"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
            return isDirectory.boolValue ? jsonFiles(in: url) : [url]
        }
        guard let review = PageFixtures.reviewDirectory,
              let names = try? manager.contentsOfDirectory(atPath: review.path) else { return [] }
        let folders = names.filter { $0.hasPrefix("iphone-") }.sorted()
        guard let newest = folders.last else { return [] }
        return jsonFiles(in: review.appending(path: newest))
    }()

    static var available: Bool { !files.isEmpty }

    static let skipReason: Comment = "No device report: set RECIPE_CODEX_DEVICE_REPORTS or put Read Fixtures JSON in Docs/Fixtures/Private/Review/iphone-<date>/"
}

/// The phone's readings replayed through this build (`DeviceReplay`; ux-notes rows 107, 160, 169):
/// each photo's blocks as the device read them, through the structurer, the contents, reference
/// and Sources readers and the stitcher, compared with the manifest as `PrivatePageTests` compares
/// the Mac's reading, and with what the device itself made of them at its build. A counts-only
/// report goes to `Docs/Fixtures/Private/Review/device-replay-<report date>.md`; with
/// `RECIPE_CODEX_REPLAY_DUMP=<folder>` each photo's lines and roles are written there too (page
/// text: a scratch folder, never the repository).
@Suite("Device readings replayed", .enabled(if: DeviceReports.available, DeviceReports.skipReason), .serialized)
struct DeviceReplayTests {
    @Test(.timeLimit(.minutes(15)))
    func replaysTheDeviceReports() async throws {
        let manifest = Dictionary(PageFixtures.manifest.map { ($0.file, $0) }, uniquingKeysWith: { first, _ in first })
        var photoFiles: [String: (slug: String, url: URL)] = [:]
        for book in PageFixtures.books() {
            for file in book.files { photoFiles[file.lastPathComponent] = (book.slug, file) }
        }
        let dumpFolder = ProcessInfo.processInfo.environment["RECIPE_CODEX_REPLAY_DUMP"].map { URL(fileURLWithPath: $0) }
        if let dumpFolder { try FileManager.default.createDirectory(at: dumpFolder, withIntermediateDirectories: true) }

        var replay = ReplayReport()
        var photosBySlug: [String: [DeviceReadingReport.Photo]] = [:]
        var slugOrder: [String] = []
        for url in DeviceReports.files {
            let report = try DeviceReadingReport.decoded(from: Data(contentsOf: url))
            replay.sources.append((url.lastPathComponent, report.device, report.build ?? "unknown", report.createdAt, report.photos.count))
            for photo in report.photos {
                let slug = manifest[photo.fileName]?.slug ?? photoFiles[photo.fileName]?.slug ?? "unknown"
                if photosBySlug[slug] == nil { slugOrder.append(slug) }
                photosBySlug[slug, default: []].append(photo)
            }
        }
        #expect(!slugOrder.isEmpty)

        let structurer = PageStructurer()
        let gate = PageQualityGate()
        for slug in slugOrder {
            let photos = photosBySlug[slug]!.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
            var book = ReplayReport.Book(slug: slug, photos: photos.count)
            var singles: [PageReading] = []
            var devices: [String: DeviceReadingReport.Result] = [:]
            for photo in photos {
                guard var reading = DeviceReplay.reading(of: photo, structurer: structurer, gate: gate) else {
                    book.unreadable.append(photo.fileName)
                    continue
                }
                let entry = manifest[photo.fileName]
                // The page's outline for a contents or index page, from the fixture photo on the Mac.
                if reading.kind == .contents || reading.kind == .index || entry?.kind == "contents" || entry?.kind == "index",
                   let file = photoFiles[photo.fileName]?.url, let image = try? PageImage.load(contentsOf: file, maxPixelSize: 4_096) {
                    reading.outline = await PageCleanup.detectOutline(in: image, quarterTurns: reading.quarterTurns.first ?? 0)
                }
                singles.append(reading)
                if let result = photo.result { devices[photo.fileName] = result }
                if let dumpFolder { Self.dump(photo, reading: reading, to: dumpFolder.appending(path: "\(slug)-\(photo.fileName).txt")) }
            }
            let stitched = PageStitcher.stitch(singles)

            // Review as the cook would meet it (as PrivatePageTests simulates it).
            var reviewedLayouts = Set<String>()
            var hasRecipes = false
            for reading in stitched where reading.kind == .recipe {
                for recipe in reading.recipes {
                    let reasons = recipe.reviewReasons(bookHasRecipes: hasRecipes, reviewedLayouts: reviewedLayouts)
                    if hasRecipes { book.laterRecipes += 1 }
                    if hasRecipes, reasons.contains(.unseenLayout) { book.forcedLater += 1 }
                    if !reasons.isEmpty { reviewedLayouts.insert(recipe.layoutSignature) }
                    hasRecipes = true
                    book.ingredientLines += recipe.ingredients.count
                    book.unparsedLines += recipe.unparsedIngredientCount
                }
            }
            book.layouts = reviewedLayouts.count
            book.seconds = photos.map(\.seconds)
            for reading in singles {
                for block in reading.blocks where block.kind != .photo {
                    for line in block.lines {
                        book.lines += 1
                        if Self.isMostlyNonLatin(line.text) { book.nonLatinLines += 1 }
                    }
                }
            }

            // Against the manifest, and against the device's own reading.
            for single in singles {
                let file = single.files[0]
                let stitchedReading = stitched.first { $0.files.contains(file) }
                var row = ReplayReport.Row(file: file, replaySummary: Self.summary(single, stitched: stitchedReading))
                if let device = devices[file] { row.deviceSummary = Self.summary(device) }
                if let entry = manifest[file] {
                    row.replay = Self.compare(single, stitched: stitchedReading, with: entry)
                    if let device = devices[file] { row.device = Self.compare(device, with: entry) }
                    row.isListed = true
                } else {
                    row.isListed = false
                }
                if let device = devices[file] { row.changed = Self.changed(single, from: device) }
                book.rows.append(row)
            }
            replay.books.append(book)
        }

        let date = replay.sources.first.map { ISO8601DateFormatter.string(from: $0.createdAt, timeZone: .current, formatOptions: [.withFullDate]) } ?? "undated"
        let output = PageFixtures.reviewDirectory!.appending(path: "device-replay-\(date).md")
        try replay.markdown().write(to: output, atomically: true, encoding: .utf8)
        print(replay.summaryLines().joined(separator: "\n"))
        print("Replay report: \(output.path)")
        #expect(replay.books.reduce(0) { $0 + $1.rows.count } > 0)
    }

    // MARK: - Comparing

    /// What differs from the manifest, by part; empty when nothing does.
    static func compare(_ single: PageReading, stitched: PageReading?, with entry: PageFixtures.Entry) -> [String] {
        var differences: [String] = []
        let gate = single.quality.first??.quality.rawValue
        if gate != entry.gate { differences.append("gate \(gate ?? "-") (manifest \(entry.gate))") }
        if let page = entry.page, single.pageNumber != page { differences.append("page \(single.pageNumber.map(String.init) ?? "none") (manifest \(page))") }
        switch entry.kind {
        case "recipe", "spread-start":
            if !(single.kind == .recipe && !single.isContinuation) {
                differences.append("kind \(single.kind.rawValue)\(single.isContinuation ? " (continues)" : "") (manifest \(entry.kind))")
            } else if entry.kind == "spread-start", (stitched?.files.count ?? 0) <= 1 {
                differences.append("not stitched to the next page")
            }
            if let expected = entry.recipes, let stitched, stitched.files.first == single.files[0], single.kind == .recipe, !single.isContinuation {
                let counts = stitched.recipes.map { "\($0.ingredients.count)/\($0.steps.count)" }
                let wanted = expected.map { "\($0.ingredients)/\($0.steps)" }
                if counts != wanted { differences.append("counts \(counts.joined(separator: ", ")) (manifest \(wanted.joined(separator: ", ")))") }
            }
        case "spread-middle", "spread-end":
            if !single.isContinuation { differences.append("kind \(single.kind.rawValue) (manifest \(entry.kind): should continue the page before)") }
            else if stitched?.files.first == single.files[0] { differences.append("not stitched to the page before") }
        case "reference", "glossary":
            if !(single.kind == .prose && single.reference != nil) {
                differences.append("kind \(single.kind.rawValue)\(single.reference == nil ? ", no reference" : "") (manifest \(entry.kind))")
            } else {
                if entry.kind == "glossary", single.reference?.kind != .glossary { differences.append("reference \(single.reference?.kind.rawValue ?? "-") (manifest glossary)") }
                if let expected = entry.sections, single.reference?.sections.count != expected { differences.append("sections \(single.reference?.sections.count ?? 0) (manifest \(expected))") }
            }
        case "contents", "index", "sources", "photo":
            if single.kind.rawValue != entry.kind {
                differences.append("kind \(single.kind.rawValue)\(single.isContinuation ? " (continues)" : "") (manifest \(entry.kind))")
            } else {
                if let expected = entry.suppliers {
                    let count = SourcesPageReader.read(single).count
                    if count != expected { differences.append("suppliers \(count) (manifest \(expected))") }
                }
                if let expected = entry.contents {
                    let contents = ContentsReader.read(single)
                    let listed = entry.kind == "index" ? contents.index : contents.entries
                    let counts = PageFixtures.ContentsCounts(sections: contents.sections.count, entries: listed.count, paged: listed.count { $0.page != nil })
                    if counts != expected { differences.append("contents \(counts.sections)/\(counts.entries)/\(counts.paged) (manifest \(expected.sections)/\(expected.entries)/\(expected.paged))") }
                }
            }
        case "bad-capture":
            if gate == PageQuality.sharp.rawValue { differences.append("a bad capture read Sharp") }
        default:
            break
        }
        return differences
    }

    /// The device's own structured result against the manifest: kind, page and the recipes' counts
    /// (a spread read singly on the device differs by design).
    static func compare(_ result: DeviceReadingReport.Result, with entry: PageFixtures.Entry) -> [String] {
        var differences: [String] = []
        if let page = entry.page, result.pageNumber != page { differences.append("page \(result.pageNumber.map(String.init) ?? "none") (manifest \(page))") }
        switch entry.kind {
        case "recipe", "spread-start":
            if !(result.kind == .recipe && !result.isContinuation) {
                differences.append("kind \(result.kind.rawValue)\(result.isContinuation ? " (continues)" : "") (manifest \(entry.kind))")
            } else if entry.kind == "recipe", let expected = entry.recipes {
                let counts = result.recipes.map { "\($0.ingredients)/\($0.steps)" }
                let wanted = expected.map { "\($0.ingredients)/\($0.steps)" }
                if counts != wanted { differences.append("counts \(counts.joined(separator: ", ")) (manifest \(wanted.joined(separator: ", ")))") }
            }
        case "spread-middle", "spread-end":
            if !result.isContinuation { differences.append("kind \(result.kind.rawValue) (manifest \(entry.kind))") }
        case "reference", "glossary":
            if result.kind != .prose { differences.append("kind \(result.kind.rawValue) (manifest \(entry.kind))") }
        case "contents", "index", "sources", "photo":
            if result.kind.rawValue != entry.kind { differences.append("kind \(result.kind.rawValue)\(result.isContinuation ? " (continues)" : "") (manifest \(entry.kind))") }
        default:
            break
        }
        return differences
    }

    /// Whether this build reads the device's blocks differently from the device's own build: kind,
    /// continuation, page or the recipes' counts.
    static func changed(_ reading: PageReading, from device: DeviceReadingReport.Result) -> Bool {
        if reading.kind != device.kind || reading.isContinuation != device.isContinuation || reading.pageNumber != device.pageNumber { return true }
        return reading.recipes.map { "\($0.ingredients.count)/\($0.steps.count)" } != device.recipes.map { "\($0.ingredients)/\($0.steps)" }
    }

    static func summary(_ single: PageReading, stitched: PageReading?) -> String {
        var parts = [single.kind.rawValue + (single.isContinuation ? " (continues)" : "")]
        if let page = single.pageNumber { parts.append("p. \(page)") }
        switch single.kind {
        case .recipe:
            let recipes = single.recipes.map { "\($0.ingredients.count)/\($0.steps.count)" }
            if !recipes.isEmpty { parts.append(recipes.joined(separator: ", ")) }
            if let stitched, stitched.files.count > 1, stitched.files.first == single.files[0] {
                parts.append("stitched \(stitched.files.count): " + stitched.recipes.map { "\($0.ingredients.count)/\($0.steps.count)" }.joined(separator: ", "))
            }
        case .contents, .index:
            let contents = ContentsReader.read(single)
            parts.append(single.kind == .index ? "index \(contents.index.count)" : "\(contents.sections.count)/\(contents.entries.count)/\(contents.pagedEntryCount)")
        case .sources:
            parts.append("\(SourcesPageReader.read(single).count) suppliers")
        case .prose:
            if let reference = single.reference { parts.append("\(reference.kind.rawValue) \(reference.sections.count) sections") }
        default:
            break
        }
        if let gate = single.quality.first??.quality { parts.append(gate.rawValue) }
        return parts.joined(separator: " · ")
    }

    static func summary(_ result: DeviceReadingReport.Result) -> String {
        var parts = [result.kind.rawValue + (result.isContinuation ? " (continues)" : "")]
        if let page = result.pageNumber { parts.append("p. \(page)") }
        let recipes = result.recipes.map { "\($0.ingredients)/\($0.steps)" }
        if !recipes.isEmpty { parts.append(recipes.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    /// Most of the line's letters outside the Latin script (ux-notes row 126).
    static func isMostlyNonLatin(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty else { return false }
        let latin = letters.count { ContentsReader.Script($0) == .latin }
        return latin * 2 < letters.count
    }

    /// The photo's lines and roles and its reading, for diagnosis (page text: scratch only).
    static func dump(_ photo: DeviceReadingReport.Photo, reading: PageReading, to url: URL) {
        var out: [String] = ["# \(photo.fileName) · replay \(summary(reading, stitched: nil)) · device \(photo.result.map(summary) ?? "-")"]
        if let quality = photo.quality { out.append("quality \(quality.quality.rawValue) sharpness \(Int(quality.sharpness)) smudge \(String(format: "%.3f", quality.smudge))") }
        if let margins = photo.marginLines { out.append("margins: " + margins.joined(separator: " | ")) }
        if let outline = reading.outline { out.append("outline \(outline.corners.map { String(format: "(%.3f,%.3f)", $0.x, $0.y) }.joined(separator: " "))") }
        out.append("")
        for block in reading.blocks {
            let role = block.role?.rawValue ?? "-"
            out.append(String(format: "[%d] %@ %@ r=%d i=%d (%.3f, %.3f, %.3f × %.3f) size %.4f conf %.2f", block.id, block.kind.rawValue, role, block.recipe ?? -1, block.item ?? -1, block.rect.x, block.rect.y, block.rect.width, block.rect.height, block.typeSize, block.confidence))
            for line in block.lines { out.append(String(format: "    x=%.3f y=%.3f w=%.3f s=%.4f c=%.2f %@", line.rect.x, line.rect.y, line.rect.width, line.size, line.confidence, line.text)) }
        }
        out.append("")
        for (index, recipe) in reading.recipes.enumerated() {
            out.append("recipe \(index): \(recipe.title) · yield \(recipe.yield ?? "-") · signature \(recipe.layoutSignature) · stepCountDisagrees \(recipe.stepCountDisagrees) · reasons \(recipe.reviewReasons(bookHasRecipes: true, reviewedLayouts: []).map(\.rawValue))")
            if let headnote = recipe.headnote { out.append("  headnote: \(headnote)") }
            for ingredient in recipe.ingredients { out.append("  - [\(ingredient.group ?? "")] \(ingredient.text)\(ingredient.isUnparsed ? "  (unparsed)" : "")") }
            for step in recipe.steps { out.append("  \(step.number.map { "\($0). " } ?? "• ")\(step.text)") }
            for note in recipe.notes { out.append("  note: \(note)") }
        }
        if let reference = reading.reference {
            out.append("reference \(reference.kind.rawValue): \(reference.title)")
            for section in reference.sections { out.append("  § \(section.heading): \(section.body.prefix(120))") }
        }
        if reading.kind == .contents || reading.kind == .index {
            let contents = ContentsReader.read(reading)
            for section in contents.sections {
                out.append("  § \(section.title) p=\(section.page.map(String.init) ?? "-")")
                for entry in section.entries { out.append("      \(entry.title) | \(entry.page.map(String.init) ?? "-")") }
            }
            for entry in contents.index { out.append("    ix \(entry.title) | \(entry.page.map(String.init) ?? "-")") }
        }
        if reading.kind == .sources {
            for source in SourcesPageReader.read(reading) { out.append("  source: \(source.name) · \(source.phone ?? "-") · \(source.url?.absoluteString ?? "-")") }
        }
        try? out.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

/// The counts-only report: no page text, titles or terms.
struct ReplayReport {
    struct Row {
        var file: String
        var isListed = false
        /// What differs from the manifest when this build reads the device's blocks.
        var replay: [String] = []
        /// What differed from the manifest in the device's own reading at its build.
        var device: [String] = []
        /// This build reads the blocks differently from the device's build.
        var changed = false
        var replaySummary: String
        var deviceSummary: String?
    }

    struct Book {
        var slug: String
        var photos: Int
        var rows: [Row] = []
        var unreadable: [String] = []
        var laterRecipes = 0
        var forcedLater = 0
        var layouts = 0
        var ingredientLines = 0
        var unparsedLines = 0
        var lines = 0
        var nonLatinLines = 0
        var seconds: [Double] = []

        var listed: [Row] { rows.filter(\.isListed) }
    }

    var sources: [(file: String, device: String, build: String, createdAt: Date, photos: Int)] = []
    var books: [Book] = []

    func summaryLines() -> [String] {
        var out: [String] = []
        out.append("| Book | Photos | Manifest rows | Replay same | Device same | Changed by this build | Later recipes forced | Unparsed lines | Non-Latin lines |")
        out.append("|---|---|---|---|---|---|---|---|---|")
        var totals = (rows: 0, replaySame: 0, deviceSame: 0, changed: 0, later: 0, forced: 0, lines: 0, unparsed: 0, text: 0, nonLatin: 0)
        for book in books {
            let listed = book.listed
            let replaySame = listed.count { $0.replay.isEmpty }
            let deviceSame = listed.count { $0.device.isEmpty && $0.deviceSummary != nil }
            let changed = book.rows.count(where: \.changed)
            out.append("| \(book.slug) | \(book.photos) | \(listed.count) | \(replaySame) | \(deviceSame) | \(changed) | \(book.forcedLater) of \(book.laterRecipes) | \(book.unparsedLines) of \(book.ingredientLines) | \(book.nonLatinLines) of \(book.lines) |")
            totals.rows += listed.count; totals.replaySame += replaySame; totals.deviceSame += deviceSame; totals.changed += changed
            totals.later += book.laterRecipes; totals.forced += book.forcedLater
            totals.lines += book.ingredientLines; totals.unparsed += book.unparsedLines
            totals.text += book.lines; totals.nonLatin += book.nonLatinLines
        }
        out.append("| all | \(books.reduce(0) { $0 + $1.photos }) | \(totals.rows) | \(totals.replaySame) | \(totals.deviceSame) | \(totals.changed) | \(totals.forced) of \(totals.later) | \(totals.unparsed) of \(totals.lines) | \(totals.nonLatin) of \(totals.text) |")
        let seconds = books.flatMap(\.seconds).sorted()
        if !seconds.isEmpty {
            out.append("")
            out.append("Seconds a photo on the device: median \(String(format: "%.2f", seconds[seconds.count / 2])), slowest \(String(format: "%.2f", seconds.last!)).")
        }
        return out
    }

    func markdown() -> String {
        var out: [String] = ["# Device readings replayed"]
        out.append("")
        let date = ISO8601DateFormatter.string(from: .now, timeZone: .current, formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime])
        out.append("*Written by `DeviceReplayTests` (Packages/Capture) on \(date): the device's Read Fixtures blocks through this build's structurer and readers, against the manifest (`Fixtures/private-pages.json`) and against the device's own reading. Counts only; no page text.*")
        out.append("")
        for source in sources {
            out.append("- \(source.file): \(source.device), build \(source.build), \(source.photos) photos, read \(ISO8601DateFormatter.string(from: source.createdAt, timeZone: .current, formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime]))")
        }
        out.append("")
        out.append("## Summary")
        out.append("")
        out += summaryLines()
        out.append("")
        out.append("Replay same: the manifest row's kind, gate, page and counts all match when this build reads the device's blocks (spreads stitched as on the Mac). Device same: the device's own kind, page and recipe counts at its build match the manifest (a spread read singly differs by design). Changed by this build: this build reads the blocks to another kind, page or count than the device's build did. Later recipes forced: recipes after a book's first that would be forced into review for a layout not yet confirmed.")
        out.append("")
        for book in books {
            out.append("## \(book.slug)")
            out.append("")
            let differing = book.listed.filter { !$0.replay.isEmpty }
            if differing.isEmpty, !book.listed.isEmpty { out.append("Every manifest row reads the same in the replay.") }
            for row in differing { out.append("- \(row.file): " + row.replay.joined(separator: "; ") + " — replay \(row.replaySummary)") }
            let deviceDiffering = book.listed.filter { !$0.device.isEmpty }
            if !deviceDiffering.isEmpty {
                out.append("")
                out.append("Device as read, differing from the manifest:")
                for row in deviceDiffering { out.append("- \(row.file): " + row.device.joined(separator: "; ")) }
            }
            let changed = book.rows.filter(\.changed)
            if !changed.isEmpty {
                out.append("")
                out.append("Read differently by this build than by the device's:")
                for row in changed { out.append("- \(row.file): device \(row.deviceSummary ?? "-") → replay \(row.replaySummary)") }
            }
            let unlisted = book.rows.filter { !$0.isListed }
            if !unlisted.isEmpty {
                out.append("")
                out.append("Not in the manifest (replay reading):")
                for row in unlisted { out.append("- \(row.file): \(row.replaySummary)") }
            }
            if !book.unreadable.isEmpty { out.append("- unreadable on the device: \(book.unreadable.joined(separator: ", "))") }
            out.append("")
        }
        return out.joined(separator: "\n") + "\n"
    }
}
