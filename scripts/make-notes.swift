// Turns CHANGELOG.md into the pages and text that describe a release, so the notes are written once.
//
//   swift scripts/make-notes.swift site                     docs/whats-new.html, and docs/notes/<version>.html
//                                                           (what the update window shows) for each release
//   swift scripts/make-notes.swift text <version>           the text for the GitHub release, on standard output
//   swift scripts/make-notes.swift check <version>          fails unless the changelog has notes for that version
//   swift scripts/make-notes.swift stamp <version> <date>   writes the release date into that version's heading
//
// Options, for trying things without touching the real files: --changelog <file>  --docs <folder>
// A version whose heading says "(not released yet)" is left out of the site until it has been stamped.
import Foundation

// MARK: Reading the changelog

struct Release {
    enum Block {
        case heading(String)
        case list([String])
        case paragraph(String)
    }

    let version: String
    /// The date as written in the heading, or nil while the version is not released.
    let date: String?
    /// The section as written, for places that take Markdown.
    var markdown: [String] = []
    var blocks: [Block] = []
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-notes: \(message)\n".utf8))
    exit(1)
}

func parse(_ changelog: String) -> [Release] {
    var releases: [Release] = []
    var items: [String]?
    var paragraph: String?

    func close() {
        guard !releases.isEmpty else { return }
        if let list = items { releases[releases.count - 1].blocks.append(.list(list)) }
        if let text = paragraph { releases[releases.count - 1].blocks.append(.paragraph(text)) }
        items = nil
        paragraph = nil
    }

    for line in changelog.components(separatedBy: "\n") {
        if let match = line.wholeMatch(of: #/## (\d+\.\d+\.\d+)(?: \((.+)\))?/#) {
            close()
            let date = match.2.map(String.init)
            releases.append(Release(version: String(match.1), date: date == "not released yet" ? nil : date))
            continue
        }
        guard !releases.isEmpty else { continue }
        releases[releases.count - 1].markdown.append(line)
        let text = line.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            close()
        } else if text.hasPrefix("### ") {
            close()
            releases[releases.count - 1].blocks.append(.heading(String(text.dropFirst(4))))
        } else if text.hasPrefix("- ") {
            if paragraph != nil { close() }
            items = (items ?? []) + [String(text.dropFirst(2))]
        } else if let list = items, let last = list.last {
            // A wrapped line belongs to the item above it.
            items = list.dropLast() + ["\(last) \(text)"]
        } else {
            paragraph = paragraph.map { "\($0) \(text)" } ?? text
        }
    }
    close()
    for index in releases.indices {
        releases[index].markdown = Array(releases[index].markdown.trimmingPrefix { $0.isEmpty })
        while releases[index].markdown.last?.isEmpty == true { releases[index].markdown.removeLast() }
    }
    return releases
}

// MARK: Writing HTML

/// One line of changelog text as HTML: escaped, with the little Markdown the changelog uses.
func html(_ text: String) -> String {
    var out = text.replacing("&", with: "&amp;").replacing("<", with: "&lt;").replacing(">", with: "&gt;")
    out = out.replacing(#/\*\*(.+?)\*\*/#) { "<strong>\($0.1)</strong>" }
    out = out.replacing(#/`(.+?)`/#) { "<code>\($0.1)</code>" }
    out = out.replacing(#/\[(.+?)\]\((https?:[^)\s]+)\)/#) { "<a href=\"\($0.2)\">\($0.1)</a>" }
    out = out.replacing(#/(\w)'(\w)/#) { "\($0.1)’\($0.2)" }
    return out
}

func body(of release: Release, heading tag: String) -> String {
    release.blocks.map { block in
        switch block {
        case let .heading(text): "<\(tag)>\(html(text))</\(tag)>"
        case let .paragraph(text): "<p>\(html(text))</p>"
        case let .list(items): "<ul>\n" + items.map { "  <li>\(html($0))</li>" }.joined(separator: "\n") + "\n</ul>"
        }
    }.joined(separator: "\n")
}

func whatsNewPage(_ releases: [Release]) -> String {
    let sections = releases.map { release in
        """
          <section class="rel">
            <div>
              <h2>\(release.version)</h2>
              <div class="date">\(html(release.date ?? "Not released yet"))</div>
            </div>
            <div class="changes">
        \(body(of: release, heading: "h3"))
            </div>
          </section>
        """
    }.joined(separator: "\n")
    return """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>What’s new in Tannin</title>
    <meta name="description" content="Every release of Tannin, newest first.">
    <link rel="icon" href="icon.png">
    <link rel="stylesheet" href="site.css">
    </head>
    <body>
    <!-- Written by scripts/make-notes.swift from CHANGELOG.md. Change the notes there, not here. -->

    <header class="wrap nav">
      <a class="name" href="./">Tannin</a>
      <nav class="links" aria-label="Site">
        <a href="whats-new.html" aria-current="page">What’s new</a>
        <a href="https://github.com/lantelyes/tannin">GitHub</a>
      </nav>
    </header>

    <main class="news">
      <h1>What’s new</h1>
      <p class="lead">Every release of Tannin, newest first.</p>
    \(sections)
    </main>

    <footer class="wrap foot">
      Tannin is free software under the GPL, version 3. <a href="https://github.com/lantelyes/tannin">Source on GitHub</a>. Not affiliated with Valve, Apple or CodeWeavers.
    </footer>

    </body>
    </html>

    """
}

/// The notes as the update window shows them: small, no navigation, in the Mac's own typeface and colours,
/// with nothing loaded from anywhere else. The newest version comes first, then the ones before it.
func notesPage(_ releases: [Release]) -> String {
    let sections = releases.map { "<h2>New in \($0.version)</h2>\n\(body(of: $0, heading: "h3"))" }.joined(separator: "\n")
    return """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="color-scheme" content="light dark">
    <title>What’s new in Tannin \(releases.first?.version ?? "")</title>
    <style>
    :root { color-scheme: light dark; }
    body { margin: 0; padding: 10px 14px; font: 12px/17px -apple-system, BlinkMacSystemFont, sans-serif; color: CanvasText; }
    h2 { margin: 0 0 4px; font-size: 13px; line-height: 17px; font-weight: 700; }
    h3 { margin: 0 0 2px; font-size: 12px; font-weight: 600; }
    ul { margin: 0 0 10px; padding-left: 18px; }
    p { margin: 0 0 10px; }
    a { color: LinkText; }
    </style>
    </head>
    <body>
    <!-- Written by scripts/make-notes.swift from CHANGELOG.md. Change the notes there, not here. -->
    \(sections)
    </body>
    </html>

    """
}

// MARK: Commands

var arguments = Array(CommandLine.arguments.dropFirst())

func option(_ name: String, default fallback: String) -> String {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return fallback }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...index + 1)
    return value
}

let changelogFile = URL(fileURLWithPath: option("--changelog", default: "CHANGELOG.md"))
let docs = URL(fileURLWithPath: option("--docs", default: "docs"))

guard let changelog = try? String(contentsOf: changelogFile, encoding: .utf8) else {
    fail("cannot read \(changelogFile.path)")
}
let releases = parse(changelog)

func release(_ version: String) -> Release {
    guard let found = releases.first(where: { $0.version == version }) else {
        fail("\(changelogFile.lastPathComponent) has no section headed \"## \(version)\"")
    }
    guard !found.blocks.isEmpty else { fail("the section for \(version) is empty") }
    return found
}

func write(_ text: String, to file: URL) {
    do {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
        print("wrote \(file.path)")
    } catch {
        fail("cannot write \(file.path): \(error.localizedDescription)")
    }
}

switch arguments.first {
case "site" where arguments.count == 1:
    let released = releases.filter { $0.date != nil }
    guard !released.isEmpty else { fail("no released version in \(changelogFile.lastPathComponent)") }
    write(whatsNewPage(released), to: docs.appending(path: "whats-new.html"))
    for (index, release) in released.enumerated() {
        write(notesPage(Array(released[index...])), to: docs.appending(path: "notes/\(release.version).html"))
    }

case "text" where arguments.count == 2:
    let version = arguments[1]
    print(release(version).markdown.joined(separator: "\n"))
    print("""

    **To install:** download `Tannin-\(version).zip` below and open it, move Tannin to your Applications folder, \
    and open it. macOS will ask you to allow it once, in System Settings › Privacy & Security › Open Anyway. \
    The [README](https://github.com/lantelyes/tannin#install) has every step. If you already have Tannin 0.2.0 \
    or later, choose Tannin › Check for Updates… instead.

    For Macs with Apple silicon, on macOS 26 or later. This is a test build.
    """)

case "check" where arguments.count == 2:
    _ = release(arguments[1])

case "stamp" where arguments.count == 3:
    let (version, date) = (arguments[1], arguments[2])
    let found = release(version)
    if let existing = found.date {
        print("\(version) is already dated \(existing)")
    } else {
        var lines = changelog.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { $0.hasPrefix("## \(version)") }) else { fail("lost the heading for \(version)") }
        lines[index] = "## \(version) (\(date))"
        write(lines.joined(separator: "\n"), to: changelogFile)
    }

default:
    fail("usage: make-notes.swift site | text <version> | check <version> | stamp <version> <date>  [--changelog <file>] [--docs <folder>]")
}
