import Foundation

/// Why an archive couldn't be read, worded for the cook.
public enum ArchiveError: Error, Equatable, LocalizedError {
    case notAnArchive
    case unsupported(String)
    case damaged(String)

    public var errorDescription: String? {
        switch self {
        case .notAnArchive: "That file isn't an archive Kitchen Codex can open."
        case let .unsupported(detail): "That archive uses a format Kitchen Codex can't read (\(detail))."
        case let .damaged(name): "Part of the archive is damaged (\(name))."
        }
    }
}

/// Reads a ZIP archive held in memory: the central directory, then each entry stored or deflated.
/// Enough for recipe-app exports (Paprika's `.paprikarecipes`, Mela's `.melarecipes`); no ZIP64,
/// encryption or multi-disk archives.
struct ZipArchive: Sendable {
    struct Entry: Sendable, Equatable {
        var name: String
        var method: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int

        var isDirectory: Bool { name.hasSuffix("/") }
        /// The name without folders.
        var fileName: String { name.split(separator: "/").last.map(String.init) ?? name }
    }

    let data: Data
    let entries: [Entry]

    static func isZip(_ data: Data) -> Bool {
        data.count >= 4 && data.prefix(4).elementsEqual([0x50, 0x4B, 0x03, 0x04])
    }

    init(data: Data) throws(ArchiveError) {
        self.data = data
        let reader = ByteReader(data: data)
        // End of central directory: 22 bytes plus a comment of up to 64 KB, at the end.
        let minimum = 22
        guard data.count >= minimum else { throw .notAnArchive }
        let earliest = max(0, data.count - minimum - 65_535)
        var end: Int?
        var offset = data.count - minimum
        while offset >= earliest {
            if reader.u32(offset) == 0x0605_4B50 {
                end = offset
                break
            }
            offset -= 1
        }
        guard let end, let count = reader.u16(end + 10), let directoryOffset = reader.u32(end + 16) else {
            throw .notAnArchive
        }
        if count == 0xFFFF || directoryOffset == 0xFFFF_FFFF { throw .unsupported("ZIP64") }

        var entries: [Entry] = []
        var cursor = Int(directoryOffset)
        for _ in 0..<Int(count) {
            guard reader.u32(cursor) == 0x0201_4B50,
                  let flags = reader.u16(cursor + 8),
                  let method = reader.u16(cursor + 10),
                  let compressed = reader.u32(cursor + 20),
                  let uncompressed = reader.u32(cursor + 24),
                  let nameLength = reader.u16(cursor + 28),
                  let extraLength = reader.u16(cursor + 30),
                  let commentLength = reader.u16(cursor + 32),
                  let localOffset = reader.u32(cursor + 42),
                  let nameBytes = reader.bytes(cursor + 46, count: Int(nameLength)) else {
                throw .damaged("central directory")
            }
            if flags & 0x1 != 0 { throw .unsupported("encrypted") }
            // Bit 11 marks UTF-8 names; older tools wrote CP437, which is ASCII for plain names.
            let name = String(decoding: nameBytes, as: UTF8.self)
            entries.append(Entry(
                name: name,
                method: method,
                compressedSize: Int(compressed),
                uncompressedSize: Int(uncompressed),
                localHeaderOffset: Int(localOffset)
            ))
            cursor += 46 + Int(nameLength) + Int(extraLength) + Int(commentLength)
        }
        self.entries = entries
    }

    /// The entries that are files, skipping folders and macOS resource forks (`__MACOSX/`, `._name`).
    var files: [Entry] {
        entries.filter { !$0.isDirectory && !$0.name.hasPrefix("__MACOSX/") && !$0.fileName.hasPrefix("._") && $0.fileName != ".DS_Store" }
    }

    func contents(of entry: Entry) throws(ArchiveError) -> Data {
        let reader = ByteReader(data: data)
        let header = entry.localHeaderOffset
        guard reader.u32(header) == 0x0403_4B50,
              let nameLength = reader.u16(header + 26),
              let extraLength = reader.u16(header + 28) else { throw .damaged(entry.name) }
        let start = header + 30 + Int(nameLength) + Int(extraLength)
        guard let payload = reader.slice(start, count: entry.compressedSize) else { throw .damaged(entry.name) }
        switch entry.method {
        case 0:
            return payload
        case 8:
            guard let inflated = Inflate.raw(payload) else { throw .damaged(entry.name) }
            return inflated
        default:
            throw .unsupported("compression method \(entry.method)")
        }
    }
}

/// DEFLATE and gzip, through Foundation's zlib support (raw DEFLATE, RFC 1951).
enum Inflate {
    static func raw(_ data: Data) -> Data? {
        if data.isEmpty { return Data() }
        return try? (data as NSData).decompressed(using: .zlib) as Data
    }

    static func isGzip(_ data: Data) -> Bool {
        data.count >= 18 && data.prefix(2).elementsEqual([0x1F, 0x8B])
    }

    /// A gzip member's contents (RFC 1952): header fields skipped, the DEFLATE body inflated.
    static func gunzip(_ data: Data) -> Data? {
        guard isGzip(data) else { return nil }
        let reader = ByteReader(data: data)
        guard reader.byte(2) == 8, let flags = reader.byte(3) else { return nil }
        var cursor = 10
        if flags & 0x04 != 0 {
            guard let extra = reader.u16(cursor) else { return nil }
            cursor += 2 + Int(extra)
        }
        for flag in [UInt8(0x08), 0x10] where flags & flag != 0 {
            // Zero-terminated file name or comment.
            while let byte = reader.byte(cursor), byte != 0 { cursor += 1 }
            cursor += 1
        }
        if flags & 0x02 != 0 { cursor += 2 }
        guard cursor <= data.count - 8, let body = reader.slice(cursor, count: data.count - 8 - cursor) else { return nil }
        return raw(body)
    }
}

/// Bounds-checked little-endian reads from `Data` at offsets from its start.
struct ByteReader {
    let data: Data

    func byte(_ offset: Int) -> UInt8? {
        guard offset >= 0, offset < data.count else { return nil }
        return data[data.startIndex + offset]
    }

    func u16(_ offset: Int) -> UInt16? {
        guard let low = byte(offset), let high = byte(offset + 1) else { return nil }
        return UInt16(low) | UInt16(high) << 8
    }

    func u32(_ offset: Int) -> UInt32? {
        guard let low = u16(offset), let high = u16(offset + 2) else { return nil }
        return UInt32(low) | UInt32(high) << 16
    }

    func slice(_ offset: Int, count: Int) -> Data? {
        guard offset >= 0, count >= 0, offset + count <= data.count else { return nil }
        let start = data.startIndex + offset
        return data.subdata(in: start..<(start + count))
    }

    func bytes(_ offset: Int, count: Int) -> [UInt8]? {
        slice(offset, count: count).map(Array.init)
    }
}
