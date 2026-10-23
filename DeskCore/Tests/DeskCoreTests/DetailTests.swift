import Foundation
import Testing
import ShelfRunnerCore
@testable import DeskCore

@Suite struct DetailTests {
    let now = Fixture.seen + 20

    func detail(_ id: String, fixture: String = "status-busy", online: Bool = true) throws -> JobDetail {
        let job = try #require(try Fixture.status(fixture).jobs.first { $0.id == id })
        return DetailBuilder.build(job, online: online, now: now, timeZone: Fixture.tz)
    }

    @Test func runningJobGetsTheTerminal() throws {
        let d = try detail("q-20261022T1630-7f3a")
        #expect(d.body == .terminal(TmuxTarget(status: "shelf-SHELF-TEST:q-20261022T1630-7f3a", jobID: "q-20261022T1630-7f3a")!))
        #expect(d.label == Label("Running 4 min", .green))
        #expect(d.source == "SHELF-TEST/TODO.md")
        #expect(d.agent == "Claude" && d.mode == "attended" && d.isAttended)
    }

    @Test func offlineLiveJobKeepsItsTerminal() throws {
        let d = try detail("q-20261022T1630-7f3a", online: false)
        guard case .terminal = d.body else { Issue.record("no terminal offline"); return }
        #expect(d.label == .unknown)
        #expect(try detail("q-20261022T1633-2d4e", online: false).body == .unknown)
    }

    @Test func resultCards() throws {
        guard case .result(let done) = try detail("q-20261022T1405-1111").body else { Issue.record(); return }
        #expect(done.title == "Done" && done.line == "Finished at 14:19 after 14 min.")
        guard case .result(let blocked) = try detail("q-20261022T1300-5555").body else { Issue.record(); return }
        #expect(blocked.blocked == "2 actions blocked")
        guard case .result(let failed) = try detail("q-20261022T1200-2222").body else { Issue.record(); return }
        #expect(failed.title == "Failed" && failed.line == "Stopped with exit code 1 at 12:02.")
        #expect(failed.hint == "The last lines of the log usually say why." && failed.tone == .rose)
        guard case .result(let timeout) = try detail("q-20261021T0900-4444").body else { Issue.record(); return }
        #expect(timeout.title == "Stopped: took too long" && timeout.line == nil)
        guard case .result(let cancelled) = try detail("q-20261022T1100-3333").body else { Issue.record(); return }
        #expect(cancelled.title == "Cancelled")
    }

    @Test func d1WaitsWithoutActions() throws {
        #expect(try detail("q-20261022T1633-2d4e").body == .approval(line: "Claude, attended, in SHELF-TEST."))
        #expect(try detail("q-20261022T1630-7f3a", fixture: "status-unpaired").body == .notSigned)
        #expect(try detail("q-20261022T1631-0b2c").body
            == .waiting(reason: "Waits for memory", soFar: "6 min so far", since: "Waiting since 16:25"))
    }

    @Test func refSource() {
        #expect(DetailBuilder.source(folder: "Notes", ref: "My%20Notes/TODO%40x%25.md@a41c09e2") == "Notes/My Notes/TODO@x%.md")
        #expect(DetailBuilder.source(folder: "Notes", ref: nil) == "Notes")
    }

    @Test func finishedLogRule() {
        #expect(FinishedLog.sources(attended: true) == [.screen, .log])
        #expect(FinishedLog.sources(attended: false) == [.log])
        let plain = FinishedLog.lines("a\n\nb\n", source: .screen)
        #expect(plain.lines == ["a", "b"] && plain.styles == [[], []])
        let colored = FinishedLog.lines("\u{1B}[31mred\u{1B}[0m plain\n", source: .log)
        #expect(colored.lines == ["red plain"])
        #expect(colored.styles.first?.first?.style.fg == 1)
    }

    @Test func termColors() {
        #expect(TermColor(-1) == .defaultColor)
        #expect(TermColor(9) == .palette(9))
        #expect(TermColor(16) == .rgb(0, 0, 0))
        #expect(TermColor(231) == .rgb(255, 255, 255))
        #expect(TermColor(196) == .rgb(255, 0, 0))
        #expect(TermColor(232) == .rgb(8, 8, 8))
        #expect(TermColor(256 + 0x12_34_56) == .rgb(0x12, 0x34, 0x56))
    }
}
