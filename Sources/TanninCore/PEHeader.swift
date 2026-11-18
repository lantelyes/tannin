import Foundation

/// Reads the one fact Tannin needs from a Windows program: which processor it was built for.
public enum PEHeader {
    public enum Machine: Sendable, Equatable {
        case x86
        case x64
        case arm64
        case other(UInt16)

        public var is32Bit: Bool { self == .x86 }
    }

    /// Nil if the file is missing or is not a Windows program.
    public static func machine(of url: URL) -> Machine? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 64), head.count == 64, head[0] == 0x4D, head[1] == 0x5A else { return nil }
        // The DOS header ends with the position of the real header.
        let offset = UInt64(head[60]) | UInt64(head[61]) << 8 | UInt64(head[62]) << 16 | UInt64(head[63]) << 24
        guard (try? handle.seek(toOffset: offset)) != nil,
              let header = try? handle.read(upToCount: 6), header.count == 6,
              header[0] == 0x50, header[1] == 0x45, header[2] == 0, header[3] == 0
        else { return nil }
        let value = UInt16(header[4]) | UInt16(header[5]) << 8
        return switch value {
        case 0x014C: .x86
        case 0x8664: .x64
        case 0xAA64: .arm64
        default: .other(value)
        }
    }
}
