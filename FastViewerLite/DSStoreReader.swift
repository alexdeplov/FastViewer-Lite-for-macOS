//
//  DSStoreReader.swift
//  FastViewer
//
//  Created by Alexander Deplov on 27.01.26.
//

import Foundation

/// Sort orders that Finder can apply to a folder
enum FinderSortOrder {
    case name
    case dateModified
    case dateCreated
    case dateAdded
    case size
    case kind

    /// Finder's default sort direction when the user first clicks a column.
    /// Name and Kind default ascending (A-Z); dates and size default descending (newest/largest first).
    var finderDefaultAscending: Bool {
        switch self {
        case .name, .kind:
            return true
        case .dateModified, .dateCreated, .dateAdded, .size:
            return false
        }
    }
}

/// Result of reading Finder sort settings from .DS_Store
struct FinderSortSettings {
    var order: FinderSortOrder
    var ascending: Bool
}

/// Reads .DS_Store files to extract Finder's sort column and direction for a directory.
///
/// .DS_Store record structure:
///   - 4 bytes: filename length in UTF-16 characters (big-endian UInt32)
///   - N*2 bytes: filename in UTF-16BE
///   - 4 bytes: structure ID (ASCII, e.g. "lsvC", "lsvp")
///   - 4 bytes: data type (ASCII, e.g. "ustr", "bool")
///   - variable: data payload
///
/// Folder-level settings use filename "." (length=1, UTF-16BE 0x002E).
struct DSStoreReader {

    /// Reads the .DS_Store file in the given directory and returns the Finder sort settings.
    /// Returns name/ascending if the file doesn't exist or can't be parsed.
    static func sortSettings(forDirectoryAt directoryURL: URL) -> FinderSortSettings {
        let dsStoreURL = directoryURL.appendingPathComponent(".DS_Store")

        guard let data = try? Data(contentsOf: dsStoreURL) else {
            return FinderSortSettings(order: .name, ascending: true)
        }

        let bytes = [UInt8](data)

        // Determine the active view mode so we read the correct sort record.
        // "Nlsv" = list view, "icnv" = icon, "clmv" = column, "Flwv" = gallery
        let viewStyle = extractDotRecord_vstl(from: bytes)

        if viewStyle == "Nlsv" {
            // List view: sort column + direction stored in lsvC / lsvp
            let order = extractDotRecord_lsvC(from: bytes).map { mapSortColumn($0) } ?? .name
            let ascending = extractDotRecord_lsvp(from: bytes) ?? order.finderDefaultAscending
            return FinderSortSettings(order: order, ascending: ascending)
        }

        // Icon / column / gallery view: sort stored as arrangeBy inside icvp plist blob
        if let arrangeBy = extractDotRecord_icvp_arrangeBy(from: bytes) {
            let order = mapSortColumn(arrangeBy)
            return FinderSortSettings(order: order, ascending: order.finderDefaultAscending)
        }

        // View mode unknown or icvp unavailable — fall back to list view settings
        let order = extractDotRecord_lsvC(from: bytes).map { mapSortColumn($0) } ?? .name
        let ascending = extractDotRecord_lsvp(from: bytes) ?? order.finderDefaultAscending
        return FinderSortSettings(order: order, ascending: ascending)
    }

    // MARK: - Private

    // The byte prefix for a "." filename record:
    // filename_length = 1 (0x00000001) + filename = "." in UTF-16BE (0x002E)
    private static let dotPrefix: [UInt8] = [0x00, 0x00, 0x00, 0x01, 0x00, 0x2E]

    /// Finds the "." record with structure ID "vstl" (view style)
    /// and reads the 4-byte FourCC value: "icnv", "Nlsv", "clmv", or "Flwv".
    private static func extractDotRecord_vstl(from bytes: [UInt8]) -> String? {
        let tag: [UInt8] = [0x76, 0x73, 0x74, 0x6C] // "vstl"
        let pattern = dotPrefix + tag
        let typeMarker: [UInt8] = [0x74, 0x79, 0x70, 0x65] // "type"

        guard let i = findPattern(pattern, in: bytes) else { return nil }

        let typeOffset = i + pattern.count
        guard typeOffset + 4 <= bytes.count else { return nil }

        let typeBytes = Array(bytes[typeOffset..<typeOffset + 4])
        guard typeBytes == typeMarker else { return nil }

        let valueOffset = typeOffset + 4
        guard valueOffset + 4 <= bytes.count else { return nil }
        let valueData = Data(bytes[valueOffset..<valueOffset + 4])
        return String(data: valueData, encoding: .ascii)
    }

    /// Finds the "." record with structure ID "icvp" (icon view properties),
    /// parses the blob as a binary plist, and returns the `arrangeBy` value.
    /// Returns nil if the record is missing, unparseable, or arrangeBy is "none".
    private static func extractDotRecord_icvp_arrangeBy(from bytes: [UInt8]) -> String? {
        let tag: [UInt8] = [0x69, 0x63, 0x76, 0x70] // "icvp"
        let pattern = dotPrefix + tag
        let blobMarker: [UInt8] = [0x62, 0x6C, 0x6F, 0x62] // "blob"

        guard let i = findPattern(pattern, in: bytes) else { return nil }

        let typeOffset = i + pattern.count
        guard typeOffset + 4 <= bytes.count else { return nil }

        let typeBytes = Array(bytes[typeOffset..<typeOffset + 4])
        guard typeBytes == blobMarker else { return nil }

        let lenOffset = typeOffset + 4
        guard lenOffset + 4 <= bytes.count else { return nil }
        let blobLen = Int(readUInt32BE(bytes, at: lenOffset))
        let dataOffset = lenOffset + 4
        let endOffset = min(dataOffset + blobLen, bytes.count)
        guard dataOffset < endOffset else { return nil }

        let blobData = Data(bytes[dataOffset..<endOffset])

        // Parse the blob as a binary property list
        guard let plist = try? PropertyListSerialization.propertyList(
            from: blobData, options: [], format: nil
        ) as? [String: Any] else {
            return nil
        }

        guard let arrangeBy = plist["arrangeBy"] as? String,
              !arrangeBy.isEmpty,
              arrangeBy != "none" else {
            return nil
        }

        return arrangeBy
    }

    /// Finds the "." record with structure ID "lsvC" (list view sort column)
    /// and reads the ustr payload as a UTF-16BE string.
    private static func extractDotRecord_lsvC(from bytes: [UInt8]) -> String? {
        // Full pattern: dotPrefix + "lsvC"
        let tag: [UInt8] = [0x6C, 0x73, 0x76, 0x43] // "lsvC"
        let pattern = dotPrefix + tag
        let ustrMarker: [UInt8] = [0x75, 0x73, 0x74, 0x72] // "ustr"

        guard let i = findPattern(pattern, in: bytes) else { return nil }

        // After the pattern (10 bytes: 6 dot-prefix + 4 tag), expect data type
        let typeOffset = i + pattern.count
        guard typeOffset + 4 <= bytes.count else { return nil }

        let typeBytes = Array(bytes[typeOffset..<typeOffset + 4])

        if typeBytes == ustrMarker {
            // ustr: 4-byte length (UTF-16 char count) + UTF-16BE data
            let lenOffset = typeOffset + 4
            guard lenOffset + 4 <= bytes.count else { return nil }
            let charCount = Int(readUInt32BE(bytes, at: lenOffset))
            let dataOffset = lenOffset + 4
            let byteCount = charCount * 2
            guard dataOffset + byteCount <= bytes.count else { return nil }
            let strData = Data(bytes[dataOffset..<dataOffset + byteCount])
            return String(data: strData, encoding: .utf16BigEndian)
        }

        // blob type: contains a binary plist; scan for known column names inside it
        let blobMarker: [UInt8] = [0x62, 0x6C, 0x6F, 0x62] // "blob"
        if typeBytes == blobMarker {
            let lenOffset = typeOffset + 4
            guard lenOffset + 4 <= bytes.count else { return nil }
            let blobLen = Int(readUInt32BE(bytes, at: lenOffset))
            let dataOffset = lenOffset + 4
            let endOffset = min(dataOffset + blobLen, bytes.count)
            guard dataOffset < endOffset else { return nil }
            let region = Data(bytes[dataOffset..<endOffset])
            return scanForKnownColumn(in: region)
        }

        return nil
    }

    /// Finds the "." record with structure ID "lsvp" (list view sort ascending)
    /// and reads the bool payload.
    private static func extractDotRecord_lsvp(from bytes: [UInt8]) -> Bool? {
        let tag: [UInt8] = [0x6C, 0x73, 0x76, 0x70] // "lsvp"
        let pattern = dotPrefix + tag
        let boolMarker: [UInt8] = [0x62, 0x6F, 0x6F, 0x6C] // "bool"

        guard let i = findPattern(pattern, in: bytes) else { return nil }

        let typeOffset = i + pattern.count
        guard typeOffset + 4 <= bytes.count else { return nil }

        let typeBytes = Array(bytes[typeOffset..<typeOffset + 4])
        guard typeBytes == boolMarker else { return nil }

        // bool: single byte value
        let valueOffset = typeOffset + 4
        guard valueOffset < bytes.count else { return nil }
        return bytes[valueOffset] != 0
    }

    /// Finds the first occurrence of a byte pattern in the data.
    private static func findPattern(_ pattern: [UInt8], in bytes: [UInt8]) -> Int? {
        guard pattern.count <= bytes.count else { return nil }
        let limit = bytes.count - pattern.count
        outer: for i in 0...limit {
            for j in 0..<pattern.count {
                if bytes[i + j] != pattern[j] { continue outer }
            }
            return i
        }
        return nil
    }

    /// Reads a big-endian UInt32 from a byte array.
    private static func readUInt32BE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        return (UInt32(bytes[offset]) << 24)
             | (UInt32(bytes[offset + 1]) << 16)
             | (UInt32(bytes[offset + 2]) << 8)
             | UInt32(bytes[offset + 3])
    }

    /// Scans a data region for known Finder sort column names (UTF-8 encoded).
    /// Used as fallback when the data type is a binary plist blob.
    private static func scanForKnownColumn(in data: Data) -> String? {
        let knownColumns = [
            "dateLastOpened",
            "dateModified",
            "dateCreated",
            "dateAdded",
            "size",
            "kind",
            "name",
        ]
        for name in knownColumns {
            if let encoded = name.data(using: .utf8), data.range(of: encoded) != nil {
                return name
            }
        }
        return nil
    }

    /// Maps a Finder sort column string to our enum
    private static func mapSortColumn(_ column: String) -> FinderSortOrder {
        switch column {
        case "dateModified", "dateLastOpened":
            return .dateModified
        case "dateCreated":
            return .dateCreated
        case "dateAdded":
            return .dateAdded
        case "size":
            return .size
        case "kind":
            return .kind
        default:
            return .name
        }
    }
}
