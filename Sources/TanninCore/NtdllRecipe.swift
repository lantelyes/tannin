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
        // winecx-gptk 4.8.3 (Wine 11.19), detour32-winecx-4.8.3.bin, built from the corrected shim32.S
        NtdllRecipe(
            arch: "i386",
            cleanSHA256: "404264bcb910ca81fd4832e14c2bb8a8a808742fad562ff18df7476575e26473",
            patchedSHA256: "5d515cf480c596b43e61726a745a1af261228ee95a996c6b9c18a7c078c9212e",
            size: 1145589,
            runs: [
                Run(offset: 403472, hex: """
                    e9fb8b0300cc
                    """),
                Run(offset: 635920, hex: """
                    60e8
                    """),
                Run(offset: 635926, hex: """
                    5981e916b4c97b89de89eb89e783e4f083ec308d81303dc17b8944240c8d816052c17b894424108d81e4d7c07b894424
                    148d8114d6c07b894424188d8144d3c07b8944241c8d81d4d3c07b89442420894c24248d44240c89042489742404895c
                    2408e81002000089fc61f645b4020f85b573fcffe98773fcff905589e5575653518b583031c98955f085db751731c0eb
                    2c8d78bf8d70206683ff1a0f42c66639c275ea418b45f0660fbe1408668b044b84d275dd6685c00f94c00fb6c05a5b5e
                    5f5dc35589e557565389c381ecc80200008b413c8b7228898d34fdffffc7853cfdffff00100000898530fdffff31c089
                    8538fdffff8b422466d1e885f60f846c0100006683f8010f86620100000fb7f88d570489bd2cfdffff81fa400100000f
                    874a01000066833e5c0f8440010000c78574fdffff5c003f0031d2c78578fdffff3f005c00668b3c566689bc557cfdff
                    ff423b952cfdffff72eb8d4400088dbd40fdffff89ce6689854cfdffff6689854efdffff8d8574fdffff898550fdffff
                    8d853cfdffff576a04508d8534fdffff506affff530885c00f85d10000008d854cfdffff31c98d9544fdffffc7855cfd
                    ffff18000000898564fdffff31c089856cfdffff898570fdffff8d855cfdffff898d60fdffffc78568fdffff40000000
                    6a606a0552508d8538fdffff680000108050ff530c85c0754c8b8d30fdffff8b8530fdffff31d2899558fdffff8d9544
                    fdffff83c1348d440634898d54fdffff8d8d54fdffff6a00516a0450526a006a006a00ffb538fdffffff5310ffb538fd
                    ffffff53148d853cfdffff89b534fdffffc7853cfdffff0010000057ffb540fdffff508d8534fdffff506affff53088d
                    65f45b5e5f5dc35589e557565383ec548b45088b7d0c8945e08b45108945c485ff0f84390200008b45e08b581889f88d
                    93f0b8c97be8d0fdffff8945c085c075158d9300b9c97b89f8e8bcfdffff85c00f840a0200008b771885f60f84ff0100
                    008b45c481c330b9c97b31c9c745ec20002200895df08d5de88b50a48d45ec894de853506a00528b45e08955dcff108b
                    55dc85c075078b4de885c975218d45ec53506a00528b45e0ff500485c00f85ad0100008b4de885c90f84a20100008b46
                    3c894dd48975e401f08945cc8b413c8945bc8b45cc8b40508945e88d45ec508d45e86a40508d45e4506aff8b45e0ff50
                    0885c00f85360100008b463c8b44067885c00f842701000001f031d28945d88b401c8b4dd88955dc8945b88b412001f0
                    8945a48b41248b4dd401f08945a08b45d88b5ddc3b58180f83cc0000008b413c8b4401788945d485c00f84b20000008b
                    55a48b45dc89f3031c828b45d431d2895db401c88945d48b40188b5dd48945ac89c80343208945a83b55ac0f84800000
                    008b5da88b049301c88945b031c08945d08b45b08b5dd08a1c188b45b4885dcb8b5dd08a1c18807dcb00740aff45d03a
                    5dcb74ddeb4584db75418d04128b55d48b5ddc01c80342240fb7008d048103421c8b108b45a001ca0fb704588955d48b
                    55b88d04868b1c108b55d401f3c603b889530166c74305ffe0eb0642e977ffffffff45dce925ffffff8b45cc8b402885
                    c0741c8b55bc8b54112885d2741101cac60406b88954060166c7440605ffe08b4734837dc000742083c80289f189fa89
                    47348b45c48348b4028b45e08d65f45b5e5f5de9fbfbffff0d000000208947348d65f45b5e5f5dc39090737465616d63
                    6c69656e742e646c6c0067616d656f7665726c617972656e64657265722e646c6c
                    """),
                Run(offset: 637232, hex: """
                    6c0073007400650061006d0063006c00690065006e0074002e0064006c006c
                    """),
            ]
        ),
    ]
}
