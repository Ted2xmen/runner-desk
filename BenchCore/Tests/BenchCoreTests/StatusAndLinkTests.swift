import Foundation
import Testing
import ShelfBridgeCore
@testable import BenchCore

@Suite struct StatusAndLinkTests {
    @Test func readsEveryFixture() throws {
        for name in ["status-busy", "status-idle", "status-unpaired", "status-offline-stale"] {
            let s = try Fixture.status(name)
            #expect(s.v == 2)
            #expect(s.bridge == "0.3.0")
        }
    }

    @Test func anotherVersionIsUnsupported() {
        #expect(StatusReader.read(json: #"{"v":3,"bridge":"0.9.0"}"#) == .unsupported(bridge: "0.9.0"))
        // A protocol v1 status names its version "runner": unsupported, version unknown.
        #expect(StatusReader.read(json: #"{"v":1,"runner":"0.3.0"}"#) == .unsupported(bridge: nil))
        #expect(StatusReader.read(json: "not json") == .unreadable)
        #expect(StatusReader.read(json: #"{"v":2,"bridge":"0.3.0"}"#) == .unreadable)
    }

    @Test func notificationUserInfo() throws {
        let json = String(decoding: try Fixture.data("status-idle"), as: UTF8.self)
        guard case .status(let s)? = StatusReader.read(userInfo: ["v": 2, "json": json]) else { Issue.record("no status"); return }
        #expect(s.jobs.count == 1)
        #expect(StatusReader.read(userInfo: ["v": 2]) == nil)
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
        // Nothing heard yet: looking for 5 s, then absent (no file) or offline (a file Bench cannot read).
        #expect(LinkRule.derive(latest: nil, heartbeatExists: false, launchedAt: launched, now: launched + 4.9) == .looking)
        #expect(LinkRule.derive(latest: nil, heartbeatExists: false, launchedAt: launched, now: launched + 5) == .absent)
        #expect(LinkRule.derive(latest: .unreadable, heartbeatExists: true, launchedAt: launched, now: launched + 6) == .offline(lastSeen: nil))
        // 180 s is still connected; past it, offline.
        #expect(LinkRule.derive(latest: busy, heartbeatExists: true, launchedAt: launched, now: Fixture.seen + 180)
            == .connected(bridge: "0.3.0", seen: Fixture.seen))
        #expect(LinkRule.derive(latest: busy, heartbeatExists: true, launchedAt: launched, now: Fixture.seen + 181)
            == .offline(lastSeen: Fixture.seen))
        #expect(LinkRule.derive(latest: .unsupported(bridge: "1.0.0"), heartbeatExists: true, launchedAt: launched, now: launched)
            == .unsupported(bridge: "1.0.0"))
    }

    @Test func formats() {
        #expect(BenchFormat.ago(12) == "12 s ago")
        #expect(BenchFormat.ago(300) == "5 min ago")
        #expect(BenchFormat.ago(7200) == "2 h ago")
        #expect(BenchFormat.ago(-3) == "0 s ago")
        #expect(BenchFormat.clock(Fixture.date("2026-10-22T09:05:00+03:00"), timeZone: Fixture.tz) == "09:05")
        #expect(BenchFormat.weekdayClock(Fixture.date("2026-10-26T09:00:00+03:00"), timeZone: Fixture.tz) == "Mon 09:00")
    }

    @Test func urlScheme() {
        #expect(BenchURL.jobID(URL(string: "shelfbench://job/q-20261022T1630-7f3a")!) == "q-20261022T1630-7f3a")
        #expect(BenchURL.jobID(URL(string: "shelfbench://job/s-20261022T1640-b20d")!) == "s-20261022T1640-b20d")
        #expect(BenchURL.jobID(URL(string: "ShelfBench://JOB/q-20261022T1630-7f3a")!) == "q-20261022T1630-7f3a")
        #expect(BenchURL.jobID(URL(string: "shelfbench://job/q-20261022T1630-7f3a/x")!) == nil)
        #expect(BenchURL.jobID(URL(string: "shelfbench://job/not-an-id")!) == nil)
        #expect(BenchURL.jobID(URL(string: "shelfbench://job/q-20261022T1630-7f3a?x=1")!) == nil)
        #expect(BenchURL.jobID(URL(string: "shelfbench://other/q-20261022T1630-7f3a")!) == nil)
        #expect(BenchURL.jobID(URL(string: "shelf://job/q-20261022T1630-7f3a")!) == nil)
        #expect(BenchURL.url(job: "q-20261022T1630-7f3a")?.absoluteString == "shelfbench://job/q-20261022T1630-7f3a")
    }
}
