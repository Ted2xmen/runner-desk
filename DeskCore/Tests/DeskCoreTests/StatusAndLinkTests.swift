import Foundation
import Testing
import ShelfRunnerCore
@testable import DeskCore

@Suite struct StatusAndLinkTests {
    @Test func readsEveryFixture() throws {
        for name in ["status-busy", "status-idle", "status-unpaired", "status-offline-stale"] {
            let s = try Fixture.status(name)
            #expect(s.v == 1)
            #expect(s.runner == "0.3.0")
        }
    }

    @Test func anotherVersionIsUnsupported() {
        #expect(StatusReader.read(json: #"{"v":2,"runner":"0.9.0"}"#) == .unsupported(runner: "0.9.0"))
        #expect(StatusReader.read(json: "not json") == .unreadable)
        #expect(StatusReader.read(json: #"{"v":1,"runner":"0.3.0"}"#) == .unreadable)
    }

    @Test func notificationUserInfo() throws {
        let json = String(decoding: try Fixture.data("status-idle"), as: UTF8.self)
        guard case .status(let s)? = StatusReader.read(userInfo: ["v": 1, "json": json]) else { Issue.record("no status"); return }
        #expect(s.jobs.count == 1)
        #expect(StatusReader.read(userInfo: ["v": 1]) == nil)
        #expect(StatusReader.read(userInfo: nil) == nil)
    }

    @Test func newerKeepsTheLaterSeen() throws {
        let busy = StatusRead.status(try Fixture.status("status-busy"))
        let stale = StatusRead.status(try Fixture.status("status-offline-stale"))
        #expect(StatusReader.newer(busy, stale) == busy)
        #expect(StatusReader.newer(stale, busy) == busy)
        #expect(StatusReader.newer(busy, .unreadable) == busy)
        #expect(StatusReader.newer(nil, .unreadable) == .unreadable)
    }

    @Test func linkRule() throws {
        let launched = Fixture.seen
        let busy = StatusRead.status(try Fixture.status("status-busy"))
        // Nothing heard yet: looking for 5 s, then absent (no file) or offline (a file Desk cannot read).
        #expect(LinkRule.derive(latest: nil, heartbeatExists: false, launchedAt: launched, now: launched + 4.9) == .looking)
        #expect(LinkRule.derive(latest: nil, heartbeatExists: false, launchedAt: launched, now: launched + 5) == .absent)
        #expect(LinkRule.derive(latest: .unreadable, heartbeatExists: true, launchedAt: launched, now: launched + 6) == .offline(lastSeen: nil))
        // 180 s is still connected; past it, offline.
        #expect(LinkRule.derive(latest: busy, heartbeatExists: true, launchedAt: launched, now: Fixture.seen + 180)
            == .connected(runner: "0.3.0", seen: Fixture.seen))
        #expect(LinkRule.derive(latest: busy, heartbeatExists: true, launchedAt: launched, now: Fixture.seen + 181)
            == .offline(lastSeen: Fixture.seen))
        #expect(LinkRule.derive(latest: .unsupported(runner: "1.0.0"), heartbeatExists: true, launchedAt: launched, now: launched)
            == .unsupported(runner: "1.0.0"))
    }

    @Test func formats() {
        #expect(DeskFormat.ago(12) == "12 s ago")
        #expect(DeskFormat.ago(300) == "5 min ago")
        #expect(DeskFormat.ago(7200) == "2 h ago")
        #expect(DeskFormat.ago(-3) == "0 s ago")
        #expect(DeskFormat.clock(Fixture.date("2026-10-22T09:05:00+03:00"), timeZone: Fixture.tz) == "09:05")
        #expect(DeskFormat.weekdayClock(Fixture.date("2026-10-26T09:00:00+03:00"), timeZone: Fixture.tz) == "Mon 09:00")
    }

    @Test func urlScheme() {
        #expect(DeskURL.jobID(URL(string: "runnerdesk://job/q-20261022T1630-7f3a")!) == "q-20261022T1630-7f3a")
        #expect(DeskURL.jobID(URL(string: "runnerdesk://job/s-20261022T1640-b20d")!) == "s-20261022T1640-b20d")
        #expect(DeskURL.jobID(URL(string: "RunnerDesk://JOB/q-20261022T1630-7f3a")!) == "q-20261022T1630-7f3a")
        #expect(DeskURL.jobID(URL(string: "runnerdesk://job/q-20261022T1630-7f3a/x")!) == nil)
        #expect(DeskURL.jobID(URL(string: "runnerdesk://job/not-an-id")!) == nil)
        #expect(DeskURL.jobID(URL(string: "runnerdesk://job/q-20261022T1630-7f3a?x=1")!) == nil)
        #expect(DeskURL.jobID(URL(string: "runnerdesk://other/q-20261022T1630-7f3a")!) == nil)
        #expect(DeskURL.jobID(URL(string: "shelf://job/q-20261022T1630-7f3a")!) == nil)
        #expect(DeskURL.url(job: "q-20261022T1630-7f3a")?.absoluteString == "runnerdesk://job/q-20261022T1630-7f3a")
    }
}
