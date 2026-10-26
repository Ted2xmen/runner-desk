import Foundation
import Testing
import ShelfBridgeCore
@testable import BenchCore

@Suite struct SidebarTests {
    let now = Fixture.seen + 20
    var online: BridgeLink { .connected(bridge: "0.3.0", seen: Fixture.seen) }

    func busy(expanded: Set<String> = []) throws -> SidebarModel {
        SidebarBuilder.build(status: try Fixture.status("status-busy"), link: online, now: now, expanded: expanded, timeZone: Fixture.tz)
    }

    @Test func connectionLine() throws {
        let m = try busy()
        let slots = StatusV2.Slots(max: 2, perFolder: 1, running: 2)
        #expect(m.connection == .connected(bridge: "0.3.0", seen: Fixture.seen, slots: slots))
        #expect(m.connection.text == "shelf-bridge running")
        #expect(m.connection.tone == .green)
        #expect(m.connection.accessibilityLabel == "shelf-bridge running, version 0.3.0")
        #expect(m.connection.help(now: now) == """
            shelf-bridge: the background service that runs agent jobs (not Shelf pairing).
            Version 0.3.0
            Last heard 20 s ago
            Slots: 2 of 2 in use, 1 per folder
            """)
        #expect(m.connection.showsAge)
        let off = SidebarBuilder.build(status: try Fixture.status("status-busy"), link: .offline(lastSeen: Fixture.seen),
                                       now: Fixture.seen + 300, timeZone: Fixture.tz)
        #expect(off.connection == .offline(bridge: "0.3.0", lastSeen: Fixture.seen))
        #expect(off.connection.text == "shelf-bridge offline")
        #expect(off.connection.tone == .rose)
        #expect(off.connection.help(now: Fixture.seen + 300).contains("\nLast heard 5 min ago\n"))
        #expect(off.connection.help(now: Fixture.seen + 300).hasSuffix("Check it with shelf-bridge doctor."))
        let unread = ConnectionLine.offline(bridge: nil, lastSeen: nil)
        #expect(!unread.showsAge && unread.accessibilityLabel == "shelf-bridge offline")
        #expect(unread.help(now: now).contains("Its heartbeat cannot be read"))
        #expect(ConnectionLine.looking.text == "Looking for shelf-bridge…")
        #expect(ConnectionLine.absent.text == "No shelf-bridge")
        #expect(ConnectionLine.absent.help(now: now).hasSuffix("autonomous jobs need it."))
        #expect(ConnectionLine.unsupported(bridge: "1.0.0").text == "Update shelf-bridge")
        #expect(ConnectionLine.unsupported(bridge: "1.0.0").accessibilityLabel == "Update shelf-bridge, version 1.0.0")
    }

    /// The clock alone does not change the model: the ages are written at draw time, so a
    /// stored model set every second notifies nobody while nothing else moved.
    @Test func theModelDoesNotMoveWithTheSecond() throws {
        let status = try Fixture.status("status-busy")
        let a = SidebarBuilder.build(status: status, link: online, now: now, timeZone: Fixture.tz)
        let b = SidebarBuilder.build(status: status, link: online, now: now + 1, timeZone: Fixture.tz)
        #expect(a == b)
        #expect(a.connection.help(now: now) != b.connection.help(now: now + 1))
    }

    @Test func needsYouIsShelfsScope() throws {
        let m = try busy()
        // asking (stalled + asking), first run, failed:1, failed:timeout; in Bridge's order.
        #expect(m.needsYou.map(\.id) == ["q-20261022T1610-0a0b", "q-20261022T1633-2d4e", "q-20261022T1200-2222", "q-20261021T0900-4444"])
        #expect(m.needsYou.map(\.label.text) == ["Asks you", "First run: approve", "Failed", "Stopped: took too long"])
        #expect(m.askingCount == 1)
    }

    @Test func notSignedIsInNeedsYou() throws {
        let m = SidebarBuilder.build(status: try Fixture.status("status-unpaired"), link: online, now: now, timeZone: Fixture.tz)
        #expect(m.needsYou.map(\.label) == [Label("Not signed", .amber)])
        #expect(m.needsYou.allSatisfy { !$0.isFromShelf })
    }

    @Test func stalledWithoutAQuestionStaysInItsFolder() throws {
        var s = try Fixture.status("status-busy")
        s.jobs[1].asking = false
        let m = SidebarBuilder.build(status: s, link: online, now: now, timeZone: Fixture.tz)
        #expect(!m.needsYou.contains { $0.id == "q-20261022T1610-0a0b" })
        let pantheon = m.folders.first { $0.name == "Pantheon" }
        #expect(pantheon?.active.first?.label == Label("May be stalled", .amber))
    }

    @Test func foldersGroupAndKeepTheLastTwoFinished() throws {
        let m = try busy()
        #expect(m.folders.map(\.name) == ["SHELF-TEST", "Pantheon"])
        let test = m.folders[0]
        // First run (2d4e), failed:1 (2222) and failed:timeout (4444) are in Needs you and here.
        #expect(test.active.map(\.id) == ["q-20261022T1630-7f3a", "q-20261022T1633-2d4e", "q-20261022T1631-0b2c",
                                          "q-20261022T1632-1c3d", "q-20261022T1625-4d4d"])
        #expect(test.finished.map(\.id) == ["q-20261022T1405-1111", "q-20261022T1300-5555"])
        #expect(test.finishedTotal == 5)
        #expect(test.inNeedsYou == 3)
        #expect(test.showsFinishedToggle)
        #expect(test.finished.map(\.time) == ["14:19", "13:03"])

        let open = try busy(expanded: ["/Users/test/SHELF-TEST"])
        #expect(open.folders[0].finished.map(\.id) == ["q-20261022T1405-1111", "q-20261022T1300-5555", "q-20261022T1200-2222",
                                                       "q-20261022T1100-3333", "q-20261021T0900-4444"])
        #expect(open.folders[0].isExpanded)
    }

    @Test func needsYouJobsStayInTheirFolder() throws {
        // Expanded: an older ended job sits behind "Show all", like any other.
        let m = try busy(expanded: ["/Users/test/SHELF-TEST", "/Users/test/Pantheon"])
        let inFolders = Set(m.folders.flatMap { $0.active + $0.finished }.map(\.id))
        #expect(m.needsYou.allSatisfy { inFolders.contains($0.id) })
        let pantheon = m.folders.first { $0.name == "Pantheon" }
        #expect(pantheon?.active.map(\.id) == ["q-20261022T1610-0a0b", "q-20261022T1612-3c3c", "q-20261022T1626-5e5e"])
        #expect(pantheon?.inNeedsYou == 1)
        #expect(pantheon?.emptyLine == nil)
    }

    @Test func offlineFoldersListEveryJob() throws {
        // Offline Needs you is empty, so nothing is held back from the folders.
        let m = SidebarBuilder.build(status: try Fixture.status("status-busy"), link: .offline(lastSeen: Fixture.seen),
                                     now: Fixture.seen + 300, timeZone: Fixture.tz)
        #expect(m.folders.allSatisfy { $0.inNeedsYou == 0 })
        #expect(m.folders[0].finishedTotal == 5)
    }

    @Test func aJobFolderMissingFromFoldersStillShows() throws {
        var s = try Fixture.status("status-idle")
        s.folders = []
        let m = SidebarBuilder.build(status: s, link: online, now: now, timeZone: Fixture.tz)
        #expect(m.folders.map(\.name) == ["Pantheon"])
    }

    @Test func rowWords() throws {
        let rows = try busy().allRows
        func row(_ id: String) -> JobRow? { rows.first { $0.id == id } }
        let running = row("q-20261022T1630-7f3a")
        #expect(running?.label == Label("Running", .green))
        #expect(running?.time == "4 min")
        #expect(running?.now == "Wrote docs/release-1.4.md")
        #expect(running?.agent == "Claude")
        #expect(row("q-20261022T1631-0b2c")?.label == Label("Waits for memory", .muted))
        #expect(row("q-20261022T1631-0b2c")?.agent == "Codex")
        #expect(row("q-20261022T1632-1c3d")?.label.text == "Waits for a free slot")
        #expect(row("q-20261022T1612-3c3c")?.label.text == "Waits for the folder")
        #expect(row("q-20261022T1625-4d4d")?.label.text == "Waits for the Codex limit")
        #expect(row("q-20261022T1626-5e5e")?.label.text == "Paused")
        #expect(row("q-20261022T1405-1111")?.label == Label("Done", .green))
        #expect(row("q-20261022T1405-1111")?.now == nil)
        #expect(rows.allSatisfy { $0.isFromShelf })
    }

    @Test func offlineIsUnknownAndQuiet() throws {
        let m = SidebarBuilder.build(status: try Fixture.status("status-offline-stale"), link: .offline(lastSeen: Fixture.date("2026-10-22T09:12:44+03:00")),
                                     now: now, timeZone: Fixture.tz)
        #expect(m.needsYou.isEmpty)
        #expect(m.askingCount == 0)
        #expect(m.limits.isEmpty)
        #expect(m.mac.allSatisfy { $0.value == "Unknown" })
        let active = m.folders.flatMap(\.active)
        #expect(!active.isEmpty && active.allSatisfy { $0.label == .unknown && $0.now == nil })
        // Ended jobs cannot change: they keep their word.
        #expect(m.folders[0].finished.first?.label == Label("Done", .green))
    }

    @Test func thisMacAndLimits() throws {
        let m = try busy()
        #expect(m.mac.map(\.value) == ["Low", "48.2 GB free", "64 %", "Fine"])
        #expect(m.mac.map(\.tone) == [.amber, .plain, .plain, .plain])
        #expect(m.limits.map(\.agent) == ["Claude", "Codex"])
        #expect(m.limits[0].bars.map(\.percent) == [34, 61])
        #expect(m.limits[0].bars.map(\.resets) == ["resets 19:00", "resets Tue 10:00"])
        #expect(m.limits[0].source == "status line")
        #expect(m.limits[0].sourceLine(now: now) == "status line · 2 min ago")
        #expect(m.limits[1].bars.map(\.window) == ["Week"])
        #expect(m.limits[1].bars.map(\.short) == ["wk"])
        #expect(m.limits[1].sourceLine(now: now).hasPrefix("session · "))
        #expect(m.scheduled.map(\.next) == ["Mon 09:00"])
    }

    @Test func limitTones() throws {
        var s = try Fixture.status("status-busy")
        s.limits[0].fiveHour = 75
        s.limits[0].week = 90
        let bars = SidebarBuilder.build(status: s, link: online, now: now, timeZone: Fixture.tz).limits[0].bars
        #expect(bars.map(\.tone) == [.amber, .rose])
    }

    @Test func linkStatesWithoutJobs() {
        let looking = SidebarBuilder.build(status: nil, link: .looking, now: now)
        #expect(looking.isLooking && looking.connection == .looking)
        let absent = SidebarBuilder.build(status: nil, link: .absent, now: now)
        #expect(absent.showsBridgeFooter && absent.connection == .absent && absent.folders.isEmpty)
        let update = SidebarBuilder.build(status: nil, link: .unsupported(bridge: "1.0.0"), now: now)
        #expect(update.connection == .unsupported(bridge: "1.0.0"))
    }
}
