import Foundation
import Testing
@testable import TanninCore

@Suite struct VDFTests {
    let sample = """
    "libraryfolders"
    {
    \t"0"
    \t{
    \t\t"path"\t\t"/Users/someone/Library/Application Support/Steam"
    \t\t"apps"
    \t\t{
    \t\t\t"1478500"\t\t"3988841039"
    \t\t}
    \t}
    }
    """

    @Test func parsesNestedObjects() throws {
        let vdf = try VDF.parse(sample)
        #expect(vdf.value(at: ["libraryfolders", "0", "path"])?.string == "/Users/someone/Library/Application Support/Steam")
        #expect(vdf.value(at: ["libraryfolders", "0", "apps", "1478500"])?.string == "3988841039")
    }

    @Test func keysAreCaseInsensitive() throws {
        let vdf = try VDF.parse(sample)
        #expect(vdf.value(at: ["LibraryFolders", "0", "PATH"])?.string != nil)
    }

    @Test func roundTripsUnchanged() throws {
        let vdf = try VDF.parse(sample)
        let again = try VDF.parse(VDF.serialize(vdf))
        #expect(again == vdf)
    }

    @Test func escapesSurviveARoundTrip() throws {
        var vdf = VDFValue.object([])
        let options = "D3DM_SUPPORT_DXR=1 \"C:\\Games\\run me.exe\" %command%"
        vdf.set(.string(options), at: ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps", "1544360", "LaunchOptions"])
        let text = VDF.serialize(vdf)
        let parsed = try VDF.parse(text)
        #expect(parsed.value(at: ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps", "1544360", "LaunchOptions"])?.string == options)
    }

    @Test func setKeepsExistingKeysAndOrder() throws {
        var vdf = try VDF.parse(sample)
        vdf.set(.string("42"), at: ["libraryfolders", "0", "apps", "1544360"])
        let apps = vdf.value(at: ["libraryfolders", "0", "apps"])?.pairs.map(\.key)
        #expect(apps == ["1478500", "1544360"])
        #expect(vdf.value(at: ["libraryfolders", "0", "path"])?.string != nil)
    }

    @Test func removeDeletesOnlyTheTarget() throws {
        var vdf = try VDF.parse(sample)
        let removed = vdf.remove(at: ["libraryfolders", "0", "apps", "1478500"])
        #expect(removed)
        #expect(vdf.value(at: ["libraryfolders", "0", "apps"])?.pairs.isEmpty == true)
        let removedMissing = vdf.remove(at: ["libraryfolders", "0", "missing"])
        #expect(removedMissing == false)
        #expect(vdf.value(at: ["libraryfolders", "0", "path"])?.string != nil)
    }

    @Test func ignoresCommentsAndUnquotedTokens() throws {
        let vdf = try VDF.parse("// a comment\nroot { key value // trailing\n \"other\" \"x\" }")
        #expect(vdf.value(at: ["root", "key"])?.string == "value")
        #expect(vdf.value(at: ["root", "other"])?.string == "x")
    }

    @Test func rejectsTruncatedInput() {
        #expect(throws: VDFError.self) { try VDF.parse("\"a\" { \"b\" \"c\"") }
    }
}
