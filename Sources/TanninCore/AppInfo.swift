import Foundation

/// What Steam's cached app information says about one app.
public struct AppInfoEntry: Sendable, Equatable {
    public struct Launch: Sendable, Equatable {
        /// Path of the program inside the game's folder, with forward slashes.
        public let executable: String
        /// Platforms this entry is for ("windows", "macos", "linux"). Empty means any.
        public let platforms: [String]
        /// 32 or 64 when Steam states it.
        public let bits: Int?

        public var isForWindows: Bool { platforms.isEmpty || platforms.contains("windows") }
    }

    public let appID: String
    public let name: String
    /// Lowercased: "game", "dlc", "tool", "demo", …
    public let type: String
    /// Platforms the app ships for. Empty when Steam does not say, which is how old Windows-only games appear.
    public let platforms: [String]
    public let launches: [Launch]

    public var isGame: Bool { type == "game" }
    public var hasMacBuild: Bool { platforms.contains("macos") }
}

/// Reads `appcache/appinfo.vdf`, Steam's local cache of what it knows about every app in the library.
///
/// Only format 29 is understood (the one Steam writes since 2024: binary KeyValues with keys held in a string table
/// at the end of the file). Anything else, or a damaged file, gives an empty result rather than a guess.
public enum AppInfo {
    static let magic: UInt32 = 0x0756_4429
    /// Bytes between an entry's size field and its data: state, time, token, two hashes and a change number.
    static let entryHeaderSize = 4 + 4 + 8 + 20 + 4 + 20
    static let maxDepth = 32

    public static func load(_ url: URL) -> [String: AppInfoEntry] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [:] }
        return parse(data)
    }

    static func parse(_ data: Data) -> [String: AppInfoEntry] {
        (try? Reader(bytes: [UInt8](data)).entries()) ?? [:]
    }

    private struct Malformed: Error {}

    private indirect enum Node {
        case string(String)
        case number(Int)
        case object([String: Node])

        subscript(key: String) -> Node? {
            if case let .object(children) = self { return children[key] }
            return nil
        }

        var text: String? {
            switch self {
            case let .string(value): value
            case let .number(value): String(value)
            case .object: nil
            }
        }

        var children: [String: Node] {
            if case let .object(children) = self { return children }
            return [:]
        }
    }

    private struct Reader {
        let bytes: [UInt8]

        func u32(_ at: Int) throws -> UInt32 {
            guard at >= 0, at + 4 <= bytes.count else { throw Malformed() }
            return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        }

        func u64(_ at: Int) throws -> UInt64 {
            UInt64(try u32(at)) | UInt64(try u32(at + 4)) << 32
        }

        /// A zero-terminated string and the position after its terminator.
        func cString(_ at: Int, limit: Int) throws -> (String, Int) {
            guard at >= 0, at < limit, let end = bytes[at..<limit].firstIndex(of: 0) else { throw Malformed() }
            return (String(decoding: bytes[at..<end], as: UTF8.self), end + 1)
        }

        func stringTable(at offset: Int) throws -> [String] {
            let count = Int(try u32(offset))
            guard count <= bytes.count else { throw Malformed() }
            var strings: [String] = []
            strings.reserveCapacity(count)
            var position = offset + 4
            for _ in 0..<count {
                let (string, next) = try cString(position, limit: bytes.count)
                strings.append(string)
                position = next
            }
            return strings
        }

        /// Reads pairs until the end marker. `limit` is where this app's data stops.
        func object(_ start: Int, limit: Int, keys: [String], depth: Int) throws -> (Node, Int) {
            guard depth < AppInfo.maxDepth else { throw Malformed() }
            var position = start
            var children: [String: Node] = [:]
            while true {
                guard position < limit else { throw Malformed() }
                let kind = bytes[position]
                position += 1
                if kind == 0x08 { return (.object(children), position) }
                let keyIndex = Int(try u32(position))
                position += 4
                guard keyIndex < keys.count else { throw Malformed() }
                let key = keys[keyIndex].lowercased()
                switch kind {
                case 0x00:
                    let (child, next) = try object(position, limit: limit, keys: keys, depth: depth + 1)
                    children[key] = child
                    position = next
                case 0x01:
                    let (string, next) = try cString(position, limit: limit)
                    children[key] = .string(string)
                    position = next
                case 0x02:
                    children[key] = .number(Int(Int32(bitPattern: try u32(position))))
                    position += 4
                case 0x07:
                    children[key] = .number(Int(truncatingIfNeeded: try u64(position)))
                    position += 8
                default:
                    throw Malformed()
                }
            }
        }

        func entries() throws -> [String: AppInfoEntry] {
            guard try u32(0) == AppInfo.magic else { throw Malformed() }
            let tableOffset = Int(truncatingIfNeeded: try u64(8))
            guard tableOffset >= 16, tableOffset < bytes.count else { throw Malformed() }
            let keys = try stringTable(at: tableOffset)

            var result: [String: AppInfoEntry] = [:]
            var position = 16
            while position + 4 <= tableOffset {
                let appID = try u32(position)
                if appID == 0 { break }
                let size = Int(try u32(position + 4))
                let start = position + 8
                let end = start + size
                guard size >= AppInfo.entryHeaderSize, end <= tableOffset else { throw Malformed() }
                // One damaged app should not hide the rest of the library.
                if let (root, _) = try? object(start + AppInfo.entryHeaderSize, limit: end, keys: keys, depth: 0) {
                    result[String(appID)] = entry(appID: String(appID), root: root["appinfo"] ?? root)
                }
                position = end
            }
            return result
        }

        func platforms(_ node: Node?) -> [String] {
            (node?.text ?? "").lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        func entry(appID: String, root: Node) -> AppInfoEntry {
            let common = root["common"]
            let launches = (root["config"]?["launch"]?.children ?? [:])
                .sorted { (Int($0.key) ?? .max) < (Int($1.key) ?? .max) }
                .compactMap { _, launch -> AppInfoEntry.Launch? in
                    guard let executable = launch["executable"]?.text, !executable.isEmpty else { return nil }
                    let config = launch["config"]
                    return AppInfoEntry.Launch(
                        executable: executable.replacingOccurrences(of: "\\", with: "/"),
                        platforms: platforms(config?["oslist"]),
                        bits: config?["osarch"]?.text.flatMap(Int.init)
                    )
                }
            return AppInfoEntry(
                appID: appID,
                name: common?["name"]?.text ?? appID,
                type: (common?["type"]?.text ?? "").lowercased(),
                platforms: platforms(common?["oslist"]),
                launches: launches
            )
        }
    }
}
