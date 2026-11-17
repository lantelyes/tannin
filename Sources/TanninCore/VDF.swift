import Foundation

/// Valve's text KeyValues format, as used by config.vdf, localconfig.vdf, libraryfolders.vdf and appmanifest files.
/// Order and duplicate keys are preserved so a file can be edited and written back without reshuffling it.
public enum VDFValue: Equatable, Sendable {
    case string(String)
    case object([VDFPair])
}

public struct VDFPair: Equatable, Sendable {
    public var key: String
    public var value: VDFValue

    public init(_ key: String, _ value: VDFValue) {
        self.key = key
        self.value = value
    }
}

public enum VDFError: Error, CustomStringConvertible {
    case unexpectedEnd
    case unexpected(String, line: Int)

    public var description: String {
        switch self {
        case .unexpectedEnd: return "The file ends in the middle of a value."
        case let .unexpected(what, line): return "Unexpected \(what) on line \(line)."
        }
    }
}

public enum VDF {
    /// Parses a whole file. The result is always an object holding the top-level pairs.
    public static func parse(_ text: String) throws -> VDFValue {
        var tokenizer = Tokenizer(text)
        return .object(try parsePairs(&tokenizer, topLevel: true))
    }

    public static func load(_ url: URL) throws -> VDFValue {
        try parse(String(contentsOf: url, encoding: .utf8))
    }

    public static func serialize(_ value: VDFValue) -> String {
        var out = ""
        write(value.pairs, indent: 0, into: &out)
        return out
    }

    private enum Token { case open, close, string(String) }

    private struct Tokenizer {
        let chars: [Character]
        var index = 0
        var line = 1

        init(_ text: String) { chars = Array(text) }

        mutating func next() throws -> Token? {
            skipSpaceAndComments()
            guard index < chars.count else { return nil }
            let c = chars[index]
            if c == "{" { index += 1; return .open }
            if c == "}" { index += 1; return .close }
            if c == "\"" {
                index += 1
                var s = ""
                while index < chars.count {
                    let ch = chars[index]
                    if ch == "\\", index + 1 < chars.count {
                        switch chars[index + 1] {
                        case "n": s.append("\n")
                        case "t": s.append("\t")
                        case "\\": s.append("\\")
                        case "\"": s.append("\"")
                        default:
                            s.append("\\")
                            s.append(chars[index + 1])
                        }
                        index += 2
                        continue
                    }
                    if ch == "\"" { index += 1; return .string(s) }
                    if ch.isNewline { line += 1 }
                    s.append(ch)
                    index += 1
                }
                throw VDFError.unexpectedEnd
            }
            var s = ""
            while index < chars.count, !chars[index].isWhitespace, chars[index] != "{", chars[index] != "}", chars[index] != "\"" {
                s.append(chars[index])
                index += 1
            }
            return .string(s)
        }

        private mutating func skipSpaceAndComments() {
            while index < chars.count {
                let c = chars[index]
                if c.isNewline { line += 1; index += 1; continue }
                if c.isWhitespace { index += 1; continue }
                if c == "/", index + 1 < chars.count, chars[index + 1] == "/" {
                    while index < chars.count, !chars[index].isNewline { index += 1 }
                    continue
                }
                break
            }
        }
    }

    private static func parsePairs(_ tokenizer: inout Tokenizer, topLevel: Bool) throws -> [VDFPair] {
        var pairs: [VDFPair] = []
        while true {
            guard let token = try tokenizer.next() else {
                if topLevel { return pairs }
                throw VDFError.unexpectedEnd
            }
            switch token {
            case .close:
                if topLevel { throw VDFError.unexpected("closing brace", line: tokenizer.line) }
                return pairs
            case .open:
                throw VDFError.unexpected("opening brace without a key", line: tokenizer.line)
            case let .string(key):
                // Platform conditionals such as [$WIN32] follow a value; they carry no data we use.
                if key.hasPrefix("["), key.hasSuffix("]") { continue }
                guard let valueToken = try tokenizer.next() else { throw VDFError.unexpectedEnd }
                switch valueToken {
                case .open:
                    pairs.append(VDFPair(key, .object(try parsePairs(&tokenizer, topLevel: false))))
                case let .string(value):
                    pairs.append(VDFPair(key, .string(value)))
                case .close:
                    throw VDFError.unexpected("closing brace after key \"\(key)\"", line: tokenizer.line)
                }
            }
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func write(_ pairs: [VDFPair], indent: Int, into out: inout String) {
        let tabs = String(repeating: "\t", count: indent)
        for pair in pairs {
            switch pair.value {
            case let .string(value):
                out += "\(tabs)\"\(escape(pair.key))\"\t\t\"\(escape(value))\"\n"
            case let .object(children):
                out += "\(tabs)\"\(escape(pair.key))\"\n\(tabs){\n"
                write(children, indent: indent + 1, into: &out)
                out += "\(tabs)}\n"
            }
        }
    }
}

extension VDFValue {
    public var string: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    public var pairs: [VDFPair] {
        if case let .object(p) = self { return p }
        return []
    }

    /// First child with this key. Steam treats keys case-insensitively, so this does too.
    public subscript(key: String) -> VDFValue? {
        pairs.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    public func value(at path: [String]) -> VDFValue? {
        var current: VDFValue = self
        for key in path {
            guard let next = current[key] else { return nil }
            current = next
        }
        return current
    }

    /// Sets a value, creating intermediate objects as needed. Existing keys keep their position and spelling.
    public mutating func set(_ newValue: VDFValue, at path: [String]) {
        guard let first = path.first else {
            self = newValue
            return
        }
        var children = pairs
        let rest = Array(path.dropFirst())
        if let i = children.firstIndex(where: { $0.key.caseInsensitiveCompare(first) == .orderedSame }) {
            if rest.isEmpty {
                children[i].value = newValue
            } else {
                var child = children[i].value
                if case .string = child { child = .object([]) }
                child.set(newValue, at: rest)
                children[i].value = child
            }
        } else {
            var child: VDFValue = .object([])
            if rest.isEmpty { child = newValue } else { child.set(newValue, at: rest) }
            children.append(VDFPair(first, child))
        }
        self = .object(children)
    }

    /// Removes the value at a path. Returns whether anything was removed.
    @discardableResult
    public mutating func remove(at path: [String]) -> Bool {
        guard let first = path.first else { return false }
        var children = pairs
        guard let i = children.firstIndex(where: { $0.key.caseInsensitiveCompare(first) == .orderedSame }) else {
            return false
        }
        let rest = Array(path.dropFirst())
        if rest.isEmpty {
            children.remove(at: i)
            self = .object(children)
            return true
        }
        var child = children[i].value
        let removed = child.remove(at: rest)
        children[i].value = child
        self = .object(children)
        return removed
    }
}
