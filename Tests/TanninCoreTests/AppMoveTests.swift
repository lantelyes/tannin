import Foundation
import Testing
@testable import TanninCore

@Suite struct AppMoveTests {
    private struct RetireFailed: Error {}

    /// A scratch folder holding a made-up app in "Downloads", an empty "Applications" and a stand-in for the Trash.
    private struct Scratch {
        let root = FileManager.default.temporaryDirectory.appending(path: "tannin-move-\(UUID().uuidString)")
        var downloads: URL { root.appending(path: "Downloads") }
        var applications: URL { root.appending(path: "Applications") }
        var trash: URL { root.appending(path: "Trash") }
        var source: URL { downloads.appending(path: "Tannin.app") }
        var installed: URL { applications.appending(path: "Tannin.app") }

        init() throws {
            try makeApp(at: source, marker: "new")
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        }

        func makeApp(at url: URL, marker: String) throws {
            let macOS = url.appending(path: "Contents/MacOS")
            try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
            try Data(marker.utf8).write(to: macOS.appending(path: "Tannin"))
        }

        func marker(of app: URL) -> String? {
            (try? Data(contentsOf: app.appending(path: "Contents/MacOS/Tannin"))).map { String(decoding: $0, as: UTF8.self) }
        }

        func move(retire: AppMove.Retire? = nil) -> AppMove {
            let trash = trash
            return AppMove(source: source, into: applications, retire: retire ?? { url in
                let target = trash.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")
                try FileManager.default.moveItem(at: url, to: target)
                return target
            })
        }

        func leftovers() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: applications.path)) ?? []).filter { $0 != "Tannin.app" }
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func copiesIntoAnEmptyFolderAndLeavesTheSourceUntilAsked() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let move = scratch.move()

        let placed = try move.place()
        #expect(placed.app.path == scratch.installed.path)
        #expect(scratch.marker(of: scratch.installed) == "new")
        #expect(scratch.marker(of: scratch.source) == "new")
        #expect(scratch.leftovers().isEmpty)

        move.retireSource()
        #expect(!FileManager.default.fileExists(atPath: scratch.source.path))
        #expect(scratch.marker(of: scratch.installed) == "new")
    }

    @Test func anOlderCopyIsSetAsideAndUndoPutsItBack() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try scratch.makeApp(at: scratch.installed, marker: "old")
        let move = scratch.move()

        let placed = try move.place()
        #expect(scratch.marker(of: scratch.installed) == "new")
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.trash.path).count == 1)

        move.undo(placed)
        #expect(scratch.marker(of: scratch.installed) == "old")
        #expect(scratch.marker(of: scratch.source) == "new")
        #expect(scratch.leftovers().isEmpty)
    }

    @Test func aFailureLeavesEverythingWhereItWas() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try scratch.makeApp(at: scratch.installed, marker: "old")
        let move = scratch.move(retire: { _ in throw RetireFailed() })

        #expect(throws: RetireFailed.self) { try move.place() }
        #expect(scratch.marker(of: scratch.installed) == "old")
        #expect(scratch.marker(of: scratch.source) == "new")
        #expect(scratch.leftovers().isEmpty)
    }

    @Test func refusesSomethingThatIsNotAnAppOrIsAlreadyInPlace() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let notAnApp = AppMove(source: scratch.downloads.appending(path: "Missing.app"), into: scratch.applications)
        #expect(throws: AppMoveError.self) { try notAnApp.place() }
        let inPlace = AppMove(source: scratch.source, into: scratch.downloads)
        #expect(throws: AppMoveError.self) { try inPlace.place() }
        #expect(scratch.marker(of: scratch.source) == "new")
    }

    @Test func theDownloadMarkIsClearedOnTheCopyOnly() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let mark = "com.apple.quarantine"
        try Shell.check("/usr/bin/xattr", ["-w", mark, "0081;00000000;Tannin tests;", scratch.source.path])

        _ = try scratch.move().place()
        #expect(try Shell.run("/usr/bin/xattr", ["-p", mark, scratch.source.path]).ok)
        #expect(try !Shell.run("/usr/bin/xattr", ["-p", mark, scratch.installed.path]).ok)
    }

    @Test func knowsAnApplicationsFolderAndAHiddenCopy() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(AppLocation.isInApplicationsFolder(URL(fileURLWithPath: "/Applications/Tannin.app"), home: home))
        #expect(AppLocation.isInApplicationsFolder(URL(fileURLWithPath: "/Users/someone/Applications/Tannin.app"), home: home))
        #expect(!AppLocation.isInApplicationsFolder(URL(fileURLWithPath: "/Users/someone/Downloads/Tannin.app"), home: home))
        #expect(!AppLocation.isInApplicationsFolder(URL(fileURLWithPath: "/Applications/Games/Tannin.app"), home: home))

        let hidden = URL(fileURLWithPath: "/private/var/folders/ab/T/AppTranslocation/0000/d/Tannin.app")
        #expect(AppLocation.isTranslocated(hidden))
        let plain = URL(fileURLWithPath: "/Users/someone/Downloads/Tannin.app")
        #expect(!AppLocation.isTranslocated(plain))
        #expect(AppLocation.original(of: plain) == plain)
    }
}
