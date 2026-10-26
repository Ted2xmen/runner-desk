import Foundation
import Testing
import ShelfBridgeCore
@testable import BenchCore

@Suite struct SessionTests {
    let server = BenchServer(executable: "/opt/homebrew/bin/tmux", conf: "/Users/u/Library/Application Support/Shelf Bench/tmux.conf")
    let t0 = Date(timeIntervalSince1970: 1_792_916_978)

    func info(_ id: String = "bench-abcd1234", agent: BenchAgent = .claude, folder: String = "/Users/u/SHELF-TEST", dead: Bool = false,
              code: Int32? = nil, command: String = "node", createdAgo: TimeInterval = 600, quiet: TimeInterval = 0) -> BenchSessionInfo {
        BenchSessionInfo(id: id, agent: agent, folder: folder, created: t0 - createdAgo, isDead: dead, exitCode: code,
                        currentCommand: command, activity: t0 - quiet, attachedClients: 0)
    }

    @Test func names() {
        #expect(BenchSessionName.isValid("bench-abcd1234"))
        #expect(!BenchSessionName.isValid("bench-abcd123"))
        #expect(!BenchSessionName.isValid("bench-ABCD1234"))
        #expect(!BenchSessionName.isValid("bench-abcd12345"))
        #expect(!BenchSessionName.isValid("shelf-SHELF-TEST"))
        #expect(!BenchSessionName.isValid("view-bench-abcd1234"))
        var g = SystemRandomNumberGenerator()
        for _ in 0..<50 { #expect(BenchSessionName.isValid(BenchSessionName.make(using: &g))) }
    }

    @Test func everyArgvIsOnBenchsOwnServer() {
        let all = [server.startServer(), server.sourceConf(), server.listSessions(), server.attach("bench-abcd1234"),
                   server.respawn("bench-abcd1234"), server.kill("bench-abcd1234"), server.capture("bench-abcd1234"),
                   server.newSession(name: "bench-abcd1234", folder: "/tmp/a b", agent: .codex, shell: "/bin/zsh", columns: 120, rows: 40)]
        for args in all {
            #expect(Array(args.prefix(4)) == ["-L", "shelf-bench", "-f", server.conf])
        }
    }

    @Test func targetsAreExact() {
        #expect(server.kill("bench-abcd1234").suffix(2) == ["-t", "=bench-abcd1234"])
        #expect(server.attach("bench-abcd1234").suffix(2) == ["-t", "=bench-abcd1234"])
        #expect(server.respawn("bench-abcd1234").suffix(2) == ["-t", "=bench-abcd1234:"])
        #expect(server.capture("bench-abcd1234").suffix(2) == ["-t", "=bench-abcd1234:"])
    }

    @Test func newSessionStartsTheAgentThroughTheLoginShellAndTagsIt() {
        let args = server.newSession(name: "bench-abcd1234", folder: "/tmp/a b", agent: .claude, shell: "/bin/zsh", columns: 120, rows: 40)
        let dash = args.firstIndex(of: "--")!
        #expect(Array(args[4..<dash]) == ["new-session", "-d", "-s", "bench-abcd1234", "-c", "/tmp/a b", "-x", "120", "-y", "40"])
        #expect(Array(args[(dash + 1)...].prefix(6)) == ["/bin/zsh", "-l", "-c", "exec \"$@\"", "bench", "claude"])
        #expect(Array(args.suffix(12)) == [";", "set-option", "-t", "=bench-abcd1234:", "@bench_agent", "claude",
                                          ";", "set-option", "-t", "=bench-abcd1234:", "@bench_folder", "/tmp/a b"])
    }

    @Test func paneArgvIsNeverOneWordAndNeverSkipsPermissions() {
        let banned = ["--dangerously-skip-permissions", "--yolo", "--full-auto", "--dangerously-bypass-approvals-and-sandbox", "-p", "--print", "exec"]
        for agent in BenchAgent.allCases {
            let argv = BenchLaunch.argv(agent, shell: "/bin/zsh")
            #expect(argv.count >= 2)
            #expect(!argv.contains { banned.contains($0) })
        }
    }

    @Test func loginShellFallsBackForNonPosixShells() {
        #expect(BenchLaunch.shell(from: "/bin/bash") == "/bin/bash")
        #expect(BenchLaunch.shell(from: "/opt/homebrew/bin/zsh") == "/opt/homebrew/bin/zsh")
        #expect(BenchLaunch.shell(from: "/opt/homebrew/bin/fish") == "/bin/zsh")
        #expect(BenchLaunch.shell(from: "nu") == "/bin/zsh")
        #expect(BenchLaunch.shell(from: nil) == "/bin/zsh")
    }

    @Test func confIsInvisibleAndKeepsTheMouse() {
        let conf = BenchServer.confText
        for line in ["set -g status off", "set -g prefix None", "unbind -q -a -T prefix", "set -g remain-on-exit on", "set -g exit-empty off", "set -g mouse on"] {
            #expect(conf.contains(line))
        }
        // The root table holds the wheel and drag bindings: it is never emptied.
        #expect(!conf.contains("-a -T root"))
        #expect(!conf.contains("unbind -a"))
    }

    @Test func parsesListSessions() {
        let out = """
            bench-abcd1234\tshell\t/tmp/a b\t1792916978\t1\t7\tzsh\t1792916990\t0
            bench-ffff0000\tclaude\t/Users/u/P\t1792916000\t0\t\tnode\t1792916500\t1
            bench-00000000\t\t\t1792916978\t1\t127\tzsh\t1792916978\t0
            mine\tclaude\t/Users/u\t1\t0\t\tzsh\t1\t0

            """
        let s = BenchSessionInfo.parse(out)
        #expect(s.map(\.id) == ["bench-abcd1234", "bench-ffff0000"])
        #expect(s[0].folder == "/tmp/a b" && s[0].isDead && s[0].exitCode == 7 && s[0].agent == .shell)
        #expect(!s[1].isDead && s[1].exitCode == nil && s[1].attachedClients == 1 && s[1].currentCommand == "node")
        #expect(s[1].activity == Date(timeIntervalSince1970: 1_792_916_500))
        #expect(BenchSessionInfo.parse("no server running on /private/tmp/tmux-501/shelf-bench\n").isEmpty)
    }

    @Test func endAsksOnlyWhenSomethingRuns() {
        #expect(info(command: "node").endNeedsConfirmation(shell: "/bin/zsh"))
        #expect(info(command: "claude").endNeedsConfirmation(shell: "/bin/zsh"))
        #expect(!info(command: "zsh").endNeedsConfirmation(shell: "/bin/zsh"))
        #expect(!info(command: "-zsh").endNeedsConfirmation(shell: "/bin/zsh"))
        #expect(!info(dead: true, code: 0, command: "zsh").endNeedsConfirmation(shell: "/bin/zsh"))
    }

    @Test func capturesOnlyQuietChangedLiveSessions() {
        #expect(!SessionAsking.shouldCapture(info(quiet: 30), lastLookedAt: nil, now: t0))
        #expect(SessionAsking.shouldCapture(info(quiet: 90), lastLookedAt: nil, now: t0))
        #expect(!SessionAsking.shouldCapture(info(quiet: 90), lastLookedAt: t0 - 60, now: t0))
        #expect(SessionAsking.shouldCapture(info(quiet: 90), lastLookedAt: t0 - 120, now: t0))
        #expect(!SessionAsking.shouldCapture(info(dead: true, code: 0, quiet: 90), lastLookedAt: nil, now: t0))
    }

    @Test func askingUsesBridgesRule() {
        let prompt = "Editing Sources/Paywall.swift\n\u{2502} Do you want to allow edits to Paywall.swift? (y/n)\n\n\n"
        #expect(SessionAsking.isAsking(prompt, info(quiet: 90), now: t0))
        #expect(!SessionAsking.isAsking(prompt, info(quiet: 10), now: t0))
        #expect(!SessionAsking.isAsking("Wrote docs/release-1.4.md\n", info(quiet: 90), now: t0))
        #expect(!SessionAsking.isAsking(prompt, info(agent: .shell, quiet: 90), now: t0))
    }

    @Test func rowWords() {
        let live = SessionRow.make(info(), asking: false, now: t0)
        #expect(live.title == "You \u{00B7} Claude" && live.time == "10 min" && live.label == Label("Session", .green))
        #expect(SessionRow.make(info(), asking: true, now: t0).label == Label("Claude asks", .amber))
        #expect(SessionRow.make(info(dead: true, code: 1), asking: true, now: t0).label == Label("Exited", .muted))
        #expect(SessionRow.make(info(dead: true, code: 127), asking: false, now: t0).label == Label("Not found", .muted))
        #expect(SessionWords.exited(info(dead: true, code: 127)).line == "claude was not found in your login shell's PATH.")
        #expect(SessionWords.sharedFolder(otherSessions: 1, bridgeJob: nil) == "Another session is running here.")
        #expect(SessionWords.sharedFolder(otherSessions: 1, bridgeJob: "q-1") == "Bridge job running here: q-1.")
        #expect(SessionWords.sharedFolder(otherSessions: 0, bridgeJob: nil) == nil)
        #expect(SessionRow.make(info(quiet: 1), asking: false, now: t0).isWorking)
        #expect(!SessionRow.make(info(quiet: 30), asking: false, now: t0).isWorking)
        #expect(!SessionRow.make(info(quiet: 1), asking: true, now: t0).isWorking)
        #expect(SessionRow.make(info(agent: .shell), asking: false, now: t0).mark == .shell)
        #expect(AgentMark(raw: "codex") == .codex && AgentMark(raw: "gemini") == .other)
    }

    @Test func sidebarListsSessionsUnderTheirFolderAndAskingOnesInNeedsYou() throws {
        let status = try Fixture.status("status-busy")
        let a = info("bench-00000001", folder: "/Users/test/SHELF-TEST", createdAgo: 900)
        let b = info("bench-00000002", agent: .codex, folder: "/Users/test/SHELF-TEST", createdAgo: 300)
        let c = info("bench-00000003", folder: "/Users/u/Elsewhere")
        let d = info("bench-00000004", folder: "/Users/test/Pantheon", quiet: 90)
        let m = SidebarBuilder.build(status: status, link: .connected(bridge: "0.3.0", seen: Fixture.seen), now: Fixture.seen + 20,
                                     sessions: [b, c, a, d], asking: ["bench-00000004"], timeZone: Fixture.tz)
        #expect(m.folders.map(\.name) == ["SHELF-TEST", "Pantheon", "Elsewhere"])
        #expect(m.folders[0].sessions.map(\.id) == ["bench-00000001", "bench-00000002"])
        // The asking one is in Needs you and stays under its folder too.
        #expect(m.folders[1].sessions.map(\.id) == ["bench-00000004"])
        #expect(m.folders[1].inNeedsYou == 2)
        #expect(m.askingSessions.map(\.id) == ["bench-00000004"])
        #expect(m.askingCount == 2)
    }

    @Test func withoutABridgeFoldersComeFromSessionsAndRecents() {
        let s = info("bench-00000001", folder: "/Users/u/A")
        let m = SidebarBuilder.build(status: nil, link: .absent, now: t0, sessions: [s], recents: ["/Users/u/B", "/Users/u/A"])
        #expect(m.showsBridgeFooter)
        #expect(m.folders.map(\.name) == ["A", "B"])
        #expect(m.folders[0].sessions.count == 1 && m.folders[0].emptyLine == nil)
        #expect(m.folders[1].emptyLine == "No sessions")
        // With Bridge, recents alone do not add folders.
        let busy = SidebarBuilder.build(status: nil, link: .connected(bridge: "0.3.0", seen: t0), now: t0, recents: ["/Users/u/B"])
        #expect(busy.folders.isEmpty)
    }
}
