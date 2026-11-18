import Foundation

/// The Steam bridge patch for one exact ntdll, as data: the bytes that differ between the engine's file and the
/// patched one. It holds Tannin's detour and the jump to it, and no Wine code.
///
/// Made with `Tools/ntdll-patch/make-recipe.py` from a patch derived by NotProton's tools (see
/// `Tools/ntdll-patch/UPSTREAM.md`). Applying it needs nothing but this file, so setup works from the app alone.
public struct NtdllRecipe: Sendable {
    public struct Run: Sendable {
        public let offset: Int
        public let hex: String

        /// The run's bytes. Line breaks in the text are only there to keep the source readable.
        var bytes: [UInt8]? {
            let digits = hex.filter { !$0.isWhitespace }.utf8.map { $0 }
            guard digits.count.isMultiple(of: 2) else { return nil }
            func value(_ digit: UInt8) -> UInt8? {
                switch digit {
                case 0x30...0x39: digit - 0x30
                case 0x61...0x66: digit - 0x61 + 10
                default: nil
                }
            }
            var out: [UInt8] = []
            out.reserveCapacity(digits.count / 2)
            for index in stride(from: 0, to: digits.count, by: 2) {
                guard let high = value(digits[index]), let low = value(digits[index + 1]) else { return nil }
                out.append(high << 4 | low)
            }
            return out
        }
    }

    public let arch: String
    public let cleanSHA256: String
    public let patchedSHA256: String
    /// Length of the file, which the patch does not change.
    public let size: Int
    public let runs: [Run]

    public enum Failure: Error, CustomStringConvertible {
        case wrongSize(expected: Int, actual: Int)
        case damagedRecipe

        public var description: String {
            switch self {
            case let .wrongSize(expected, actual): return "The ntdll is \(actual) bytes, expected \(expected)."
            case .damagedRecipe: return "Tannin's own patch data is damaged."
            }
        }
    }

    /// Writes the runs over a copy of the clean file. The caller checks the hashes before and after.
    public func apply(to clean: Data) throws -> Data {
        guard clean.count == size else { throw Failure.wrongSize(expected: size, actual: clean.count) }
        var patched = [UInt8](clean)
        for run in runs {
            guard let bytes = run.bytes, run.offset >= 0, run.offset + bytes.count <= patched.count else {
                throw Failure.damagedRecipe
            }
            patched.replaceSubrange(run.offset..<run.offset + bytes.count, with: bytes)
        }
        return Data(patched)
    }

    public static let all: [NtdllRecipe] = [
        // winecx-gptk 4.8.3 (Wine 11.19), detour2-winecx-4.8.3.bin
        NtdllRecipe(
            arch: "x86_64",
            cleanSHA256: "53692da95fb6fac94f320ba11378c07dad37ea9dc3a99237a36882c885ae1ed8",
            patchedSHA256: "77ab70fe288d96d3f505912b9275ad798a649b5df9321193fafdb5da17daefaa",
            size: 1326403,
            runs: [
                Run(offset: 413446, hex: """
                    e9158a0300cccccccc
                    """),
                Run(offset: 645408, hex: """
                    56488bb424d8000000505152565741504151415241534989e24883e4f04883ec604c89542458488d0513aef7ff488944
                    2438488d05c7c3f7ff4889442440488d058b1df7ff4889442448488d4c24384889da4989f0e826000000488b64245841
                    5b415a415941585f5e5a59585e4883bc24f0
                    """),
                Run(offset: 645526, hex: """
                    e97475fcff90909090904885d20f844b0200004157415641554154554c89c5574889d756534883ec784c8b42604d85c0
                    0f84170200004989cc4c8d0d2a02000031c966410fbe140966418b044884d2741e448d58bf448d5020664183fb1a410f
                    42c248ffc16639c274d8e9de0100006685c00f85d5010000488b5f304885db0f84c801000031c031d24c8d4c24584889
                    e94889442458488d05ed0100004c8d44246048c744246020002200488944246841ff142485c0750a488b7424584885f6
                    752a31d24c8d4c24584c8d4424604889e941ff54240885c00f856f010000488b7424584885f60f84610100008b6b3c4c
                    8d44246048895c245841b940000000488d54245848c7c1ffffffff4801dd8b45504889442460488d4424544889442420
                    41ff5424104189c085c00f85190100008b433c8b94038800000085d20f84070100004801da8b4220448b722448894424
                    308b421c4889442438443b42180f83d10000008b463c8b8c068800000085c90f84b70000004801f14c8b7c24304589c1
                    448b51204a8d048b428b0438448b79184e8d1c164c895c24484801d8488944244031c04439f80f83800000004c8b5c24
                    484531d2458b1c834901f34c8b642440478a2c13478a24144584ed740a49ffc24538e574e6eb4d4584e47548448b5124
                    4801c04d01c94c8b7c24384801f04901d9460fb714108b411c4a8d0c968b0c01430fb70431488d04834801f1428b0438
                    66c7040348b848894c030266c744030affe0eb0848ffc0e977ffffff41ffc0e925ffffff8b452885c0740ec70403b801
                    000066c744030400c3834f68024883c4785b5e5f5d415c415d415e415fc3c39090909090909090909090737465616d63
                    6c69656e7436342e646c6c
                    """),
                Run(offset: 646176, hex: """
                    6c0073007400650061006d0063006c00690065006e0074002e0064006c006c
                    """),
            ]
        ),
    ]
}
