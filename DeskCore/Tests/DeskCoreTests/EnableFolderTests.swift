import Foundation
import Testing
@testable import DeskCore

@Suite struct EnableFolderTests {
    let home = "/Users/test"

    func link(_ s: String) -> DeskURL.EnableLink? { DeskURL.enableLink(URL(string: s)!) }

    @Test func enableLinks() {
        #expect(link("runnerdesk://enable?path=%2FUsers%2Ftest%2FMy%20Repo") == .path("/Users/test/My Repo"))
        #expect(link("runnerdesk://enable?path=/Users/test/repo") == .path("/Users/test/repo"))
        #expect(link("RunnerDesk://ENABLE?path=/Users/test/repo") == .path("/Users/test/repo"))
        #expect(link("runnerdesk://enable/?path=/Users/test/repo") == .path("/Users/test/repo"))
        #expect(link("runnerdesk://enable?path=/a%2Bb%26c%3Dd") == .path("/a+b&c=d"))
        #expect(link("runnerdesk://enable?path=/a+b") == .path("/a+b"))
        #expect(link("runnerdesk://enable?path=~/repo") == .path("~/repo"))
        #expect(link("runnerdesk://enable?path=%C3%BC") == .path("\u{00FC}"))
    }

    @Test func badEnableLinks() {
        for bad in ["runnerdesk://enable", "runnerdesk://enable?", "runnerdesk://enable?path=",
                    "runnerdesk://enable?path", "runnerdesk://enable?folder=/x",
                    "runnerdesk://enable?path=/a&path=/b", "runnerdesk://enable?path=/a&x=1",
                    "runnerdesk://enable?path=/a#frag", "runnerdesk://enable/x?path=/a",
                    "runnerdesk://enable?path=/a%00b", "runnerdesk://enable?path=/a%0Ab"] {
            #expect(link(bad) == .malformed, "\(bad)")
        }
        let long = String(repeating: "a", count: 1100)
        #expect(link("runnerdesk://enable?path=/\(long)") == .malformed)
    }

    @Test func notEnableLinks() {
        #expect(link("runnerdesk://job/q-20261022T1630-7f3a") == nil)
        #expect(link("shelf://enable?path=/x") == nil)
        #expect(DeskURL.jobID(URL(string: "runnerdesk://enable?path=/x")!) == nil)
    }

    @Test func enableLinkRoundTrip() {
        for path in ["/Users/test/My Repo", "/a+b&c=d#e?f", "/Users/test/\u{00DC}r\u{00FC}n", "/x/'quote'"] {
            let url = DeskURL.url(enable: path)
            #expect(url.map { link($0.absoluteString) } == .path(path), "\(path)")
        }
        #expect(DeskURL.url(enable: "/Users/test/My Repo")?.absoluteString == "runnerdesk://enable?path=/Users/test/My%20Repo")
    }

    func check(_ requested: String, _ resolved: String?, dir: Bool = true) -> EnableFolder.Check {
        EnableFolder.check(requested: requested, resolved: resolved, isDirectory: dir, home: home)
    }

    @Test func pathRules() {
        #expect(check("/Users/test/repo", "/Users/test/repo") == .ok("/Users/test/repo"))
        #expect(check("/Users/test/link/", "/Volumes/Work/repo/") == .ok("/Volumes/Work/repo"))
        #expect(check("repo", "/Users/test/repo") == .problem(.notAbsolute))
        #expect(check("~/repo", "/Users/test/repo") == .problem(.notAbsolute))
        #expect(check("/Users/test/gone", nil) == .problem(.missing))
        #expect(check("/Users/test/a.md", "/Users/test/a.md", dir: false) == .problem(.notADirectory))
        #expect(check("/", "/") == .problem(.root))
        #expect(check("/Users/test/", "/Users/test") == .problem(.home))
        #expect(check("/Users/test/home-link", "/Users/test") == .problem(.home))
        #expect(EnableFolder.check(requested: "/Users/test", resolved: "/Users/test", isDirectory: true, home: "/Users/test/") == .problem(.home))
        for system in ["/System/Library", "/Library", "/usr/local/src", "/private/tmp/x", "/private/var/folders/x",
                       "/Applications/Some.app", "/opt/homebrew", "/Users", "/Volumes", "/Users/test/Library/Mobile Documents"] {
            #expect(check(system, system) == .problem(.system), "\(system)")
        }
        #expect(check("/Users/test/Libraryish", "/Users/test/Libraryish") == .ok("/Users/test/Libraryish"))
        #expect(check("/Users/other/repo", "/Users/other/repo") == .ok("/Users/other/repo"))
        #expect(check("/Volumes/Work", "/Volumes/Work") == .ok("/Volumes/Work"))
    }

    @Test func alreadyEnabled() {
        #expect(EnableFolder.isEnabled("/Users/test/repo", folders: ["/Users/test/repo"]))
        #expect(EnableFolder.isEnabled("/Users/test/repo/", folders: ["/Users/test/repo"]))
        #expect(!EnableFolder.isEnabled("/Users/test/repo", folders: ["/Users/test/repo2"]))
        #expect(!EnableFolder.isEnabled("/Users/test/repo", folders: nil))
        #expect(EnableFolderPhase.initial(check: .ok("/Users/test/repo"), folders: ["/Users/test/repo"], cliFound: true) == .alreadyEnabled)
        #expect(EnableFolderPhase.initial(check: .ok("/Users/test/repo"), folders: [], cliFound: true) == .confirm)
        #expect(EnableFolderPhase.initial(check: .ok("/Users/test/repo"), folders: nil, cliFound: false) == .manual)
        #expect(EnableFolderPhase.initial(check: .problem(.home), folders: [], cliFound: true) == .invalid(.home))
    }

    @Test func argvAndCommand() {
        #expect(EnableFolder.arguments("/Users/test/My Repo") == ["enable", "/Users/test/My Repo"])
        #expect(EnableFolder.command("/Users/test/repo") == "shelf-runner enable /Users/test/repo")
        #expect(EnableFolder.command("/Users/test/My Repo") == "shelf-runner enable '/Users/test/My Repo'")
        #expect(EnableFolder.command("/Users/test/it's") == "shelf-runner enable '/Users/test/it'\\''s'")
    }

    @Test func findingTheCLI() throws {
        let plist: [String: Any] = ["Label": "dev.ted2xmen.shelf-runner",
                                    "ProgramArguments": ["/Apps/ShelfRunner.app/Contents/MacOS/shelf-runner", "agent"]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        #expect(EnableFolder.launchAgentProgram(data) == "/Apps/ShelfRunner.app/Contents/MacOS/shelf-runner")
        let other = try PropertyListSerialization.data(fromPropertyList: ["ProgramArguments": ["/bin/sh", "-c", "x"]], format: .xml, options: 0)
        #expect(EnableFolder.launchAgentProgram(other) == nil)
        let relative = try PropertyListSerialization.data(fromPropertyList: ["ProgramArguments": ["shelf-runner", "agent"]], format: .xml, options: 0)
        #expect(EnableFolder.launchAgentProgram(relative) == nil)
        #expect(EnableFolder.launchAgentProgram(Data("not a plist".utf8)) == nil)
        #expect(EnableFolder.bundleExecutable(app: "/Applications/ShelfRunner.app/") == "/Applications/ShelfRunner.app/Contents/MacOS/shelf-runner")
        #expect(EnableFolder.candidates(launchAgent: "/a/shelf-runner", onPath: "/opt/homebrew/bin/shelf-runner", appBundle: "/Applications/ShelfRunner.app")
            == ["/a/shelf-runner", "/opt/homebrew/bin/shelf-runner", "/Applications/ShelfRunner.app/Contents/MacOS/shelf-runner"])
        #expect(EnableFolder.candidates(launchAgent: "/a/shelf-runner", onPath: "/a/shelf-runner", appBundle: nil) == ["/a/shelf-runner"])
        #expect(EnableFolder.candidates(launchAgent: nil, onPath: nil, appBundle: nil).isEmpty)
    }

    @Test func cliAnswers() {
        #expect(EnableFolder.outcome(status: 0, output: "enabled: /Users/test/repo\n") == .enabled(already: false))
        #expect(EnableFolder.outcome(status: 0, output: "already enabled: /Users/test/repo\n") == .enabled(already: true))
        #expect(EnableFolder.outcome(status: 1, output: "shelf-runner: not a folder or missing: /x\n") == .failed("not a folder or missing: /x"))
        #expect(EnableFolder.outcome(status: 1, output: "shelf-runner: config.toml: bad\nmore\n") == .failed("config.toml: bad\nmore"))
        #expect(EnableFolder.outcome(status: 1, output: "") == .failed("shelf-runner stopped with status 1."))
        #expect(EnableFolder.outcome(status: -1, output: "The file doesn't exist.") == .failed("Couldn't start shelf-runner. The file doesn't exist."))
        guard case .failed(let long) = EnableFolder.outcome(status: 1, output: String(repeating: "x", count: 900)) else {
            Issue.record("expected a failure")
            return
        }
        #expect(long.count == 401)
    }

    @Test func sheetWords() {
        #expect(EnableFolder.title == "Enable this folder in shelf-runner?")
        #expect(EnableFolderPhase.after(.enabled(already: false)).message == "Enabled. shelf-runner will list it in a moment.")
        #expect(EnableFolderPhase.after(.enabled(already: false)).tone == .green)
        #expect(EnableFolderPhase.after(.failed("Nope")) == .failed("Nope"))
        #expect(EnableFolderPhase.confirm.message == nil)
        #expect(EnableFolderPhase.confirm.showsExplanation && EnableFolderPhase.confirm.showsEnable)
        #expect(EnableFolderPhase.manual.showsCommand && !EnableFolderPhase.manual.showsEnable)
        #expect(EnableFolderPhase.alreadyEnabled.message == "shelf-runner already reads this folder. Nothing to do.")
        #expect(EnableFolderPhase.alreadyEnabled.dismissTitle == "Done")
        #expect(EnableFolderPhase.running.dismissTitle == "Close")
        #expect(EnableFolderPhase.manual.dismissTitle == "Cancel")
        #expect(EnableFolderPhase.invalid(.system).tone == .rose)
    }

    @Test func request() {
        let r = EnableFolderRequest(requested: "/Users/test/link", check: .ok("/Volumes/Work/repo"), home: home)
        #expect(r.display == "/Volumes/Work/repo")
        #expect(r.full == "/Volumes/Work/repo")
        #expect(r.resolvedFrom == "Resolved from ~/link")
        #expect(r.path == "/Volumes/Work/repo")
        let same = EnableFolderRequest(requested: "/Users/test/repo/", check: .ok("/Users/test/repo"), home: home)
        #expect(same.display == "~/repo")
        #expect(same.resolvedFrom == nil)
        #expect(same.command == "shelf-runner enable /Users/test/repo")
        let bad = EnableFolderRequest(requested: "/Users/test/gone", check: .problem(.missing), home: home)
        #expect(bad.display == "~/gone")
        #expect(bad.path == nil)
        #expect(bad.resolvedFrom == nil)
    }
}
