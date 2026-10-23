import Foundation
import Testing
@testable import DeskCore

/// The argv must be exactly the commands verified against tmux 3.x.
@Suite struct TmuxTests {
    let id = "q-20261022T1630-7f3a"
    var target: TmuxTarget { TmuxTarget(status: "shelf-SHELF-TEST:\(id)", jobID: id)! }

    @Test func targetIsParsedAndChecked() {
        #expect(target.session == "shelf-SHELF-TEST" && target.window == id)
        #expect(TmuxTarget(status: nil, jobID: id) == nil)
        #expect(TmuxTarget(status: "shelf-SHELF-TEST", jobID: id) == nil)
        // The window must be the job's own id.
        #expect(TmuxTarget(status: "shelf-SHELF-TEST:q-20261022T1610-0a0b", jobID: id) == nil)
        // No tmux target syntax in the session name.
        #expect(TmuxTarget(status: "shelf-a.b:\(id)", jobID: id) == nil)
        #expect(TmuxTarget(status: "=shelf-a:\(id)", jobID: id) == nil)
        #expect(TmuxTarget(status: "shelf a:\(id)", jobID: id) == nil)
        #expect(TmuxTarget(status: "shelf-a:not-an-id", jobID: "not-an-id") == nil)
    }

    @Test func viewOneLinerIsTheVerifiedCommand() {
        let t = TmuxCommands(executable: "/opt/homebrew/bin/tmux", socket: nil)
        #expect(t.openView(target, name: ViewName.view(id)) == [
            "new-session", "-t", "=shelf-SHELF-TEST", "-s", "view-\(id)",
            ";", "set-option", "destroy-unattached", "keep-group",
            ";", "set-option", "detach-on-destroy", "on",
            ";", "set-option", "status", "off",
            ";", "select-window", "-t", ":=\(id)",
        ])
    }

    @Test func socketGoesFirst() {
        let t = TmuxCommands(executable: "/usr/local/bin/tmux", socket: "work")
        #expect(t.openView(target, name: "v").prefix(3) == ["-L", "work", "new-session"])
        #expect(t.killSession("view-x") == ["-L", "work", "kill-session", "-t", "=view-x"])
        #expect(TmuxCommands(executable: "/t", socket: "").base == [])
    }

    @Test func everyTargetIsExact() {
        let t = TmuxCommands(executable: "/t", socket: nil)
        #expect(t.hasSession("view-x") == ["has-session", "-t", "=view-x"])
        #expect(t.groupSize("view-x") == ["display-message", "-p", "-t", "=view-x:", "#{session_group_size}"])
        #expect(t.killSession("view-x") == ["kill-session", "-t", "=view-x"])
        #expect(t.jobWindow(target) == ["display-message", "-p", "-t", "=shelf-SHELF-TEST:=\(id)", "#{window_id} #{window_name}"])
        #expect(t.windowProbe("view-x") == ["display-message", "-p", "-t", "=view-x:", "#{window_id} #{window_name}"])
    }

    @Test func killOnlyWithAnotherGroupMember() {
        #expect(TmuxReply.groupSize("2\n") == 2)
        #expect(TmuxReply.groupSize("\n") == nil)
        #expect(TmuxReply.mayKill(groupSize: 2))
        #expect(!TmuxReply.mayKill(groupSize: 1))
        #expect(!TmuxReply.mayKill(groupSize: nil))
    }

    @Test func windowProbe() {
        #expect(TmuxReply.showsJob("@3 \(id)\n", jobID: id))
        #expect(!TmuxReply.showsJob("@4 q-20261022T1610-0a0b\n", jobID: id))
        #expect(!TmuxReply.showsJob(" \n", jobID: id))
        #expect(!TmuxReply.showsJob("", jobID: id))
    }

    @Test func copiedShellLine() {
        let t = TmuxCommands(executable: "/opt/homebrew/bin/tmux", socket: nil)
        let line = t.shellLine(t.openView(target, name: ViewName.terminal(id, suffix: "a1b2"), statusBar: true))
        #expect(line == "tmux new-session -t '=shelf-SHELF-TEST' -s term-\(id)-a1b2 \\; set-option destroy-unattached keep-group"
            + " \\; set-option detach-on-destroy on \\; select-window -t ':=\(id)'")
        let configured = TmuxCommands(executable: "/my tmux/tmux", socket: "s 1", configuredPath: true)
        #expect(configured.shellLine(configured.base + ["has-session"]) == "'/my tmux/tmux' -L 's 1' has-session")
    }

    @Test func commandScript() {
        let t = TmuxCommands(executable: "/opt/homebrew/bin/tmux", socket: "x")
        let script = t.commandScript(t.openView(target, name: "term-\(id)-0001", statusBar: true))
        #expect(script.hasPrefix("#!/bin/sh\n"))
        #expect(script.contains("\nunset TMUX\n"))
        #expect(script.hasSuffix("exec /opt/homebrew/bin/tmux -L x new-session -t '=shelf-SHELF-TEST' -s term-\(id)-0001"
            + " \\; set-option destroy-unattached keep-group \\; set-option detach-on-destroy on \\; select-window -t ':=\(id)'\n"))
    }

    @Test func quoting() {
        #expect(TmuxCommands.quoted("plain-1.2/x_y") == "plain-1.2/x_y")
        #expect(TmuxCommands.quoted("=a") == "'=a'")
        #expect(TmuxCommands.quoted("it's") == "'it'\\''s'")
        #expect(TmuxCommands.quoted("") == "''")
    }

    @Test func names() {
        var g = SeededGenerator(seed: 1)
        let s = ViewName.suffix(using: &g)
        #expect(s.count == 4 && s.allSatisfy(\.isHexDigit))
        #expect(ViewName.view(id) == "view-\(id)")
        #expect(ViewName.view(id, suffix: "beef") == "view-\(id)-beef")
        #expect(ViewName.terminal(id, suffix: "beef") == "term-\(id)-beef")
    }
}

/// A deterministic generator for the name suffix.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
