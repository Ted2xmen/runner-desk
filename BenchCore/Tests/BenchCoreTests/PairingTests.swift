import Foundation
import Testing
import ShelfBridgeCore
@testable import BenchCore

@Suite struct PairingTests {
    let now = Fixture.seen + 20
    var online: BridgeLink { .connected(bridge: "0.3.0", seen: Fixture.seen) }

    @Test func pairedWithAJobFromShelf() throws {
        let m = SidebarBuilder.build(status: try Fixture.status("status-busy"), link: online, now: now,
                                     shelfRunning: true, timeZone: Fixture.tz)
        let line = try #require(m.pairing)
        // The newest signed job: the slot hold at 16:29:40, newer than any start.
        #expect(line == PairingLine(keyId: "630dcd29", lastJob: .at(Fixture.date("2026-10-22T16:29:40+03:00")),
                                    unsigned: 0, shelfRunning: true))
        #expect(line.state == .paired)
        #expect(line.isPaired)
        #expect(line.text == "Paired with Shelf")
        #expect(line.tone == .plain)
        #expect(line.showsAge)
        #expect(line.help(now: now) == """
            Pairing lets Shelf hand jobs to shelf-bridge.
            Bridge key: 630dcd29
            Shelf is open
            Last job from Shelf: 1 min ago
            Shelf Bench can't read Shelf's key; a job from Shelf proves the pairing works.
            """)
        #expect(line.accessibilityLabel(now: now) == "Paired with Shelf, Shelf is open, last job from Shelf: 1 min ago")
    }

    @Test func unpaired() throws {
        let m = SidebarBuilder.build(status: try Fixture.status("status-unpaired"), link: online, now: now, timeZone: Fixture.tz)
        let line = try #require(m.pairing)
        #expect(line == PairingLine(keyId: nil, lastJob: .none, unsigned: 0, shelfRunning: false))
        #expect(line.state == .unpaired)
        #expect(line.text == "Not paired with Shelf")
        #expect(line.tone == .muted)
        #expect(!line.showsAge)
        #expect(line.help(now: now) == """
            Pairing lets Shelf hand jobs to shelf-bridge.
            Shelf is not running
            No job from Shelf in the last 24 hours
            Bridge has no pairing key. Run shelf-bridge pair and paste the code in Shelf.
            """)
        #expect(line.accessibilityLabel(now: now) == "Not paired with Shelf, Shelf is not running, no job from Shelf in the last 24 hours")
    }

    /// A key, but no signed job: Bench cannot tell whether Shelf holds the same key, so it does not
    /// claim the pairing.
    @Test func keyWithoutProof() throws {
        var status = try Fixture.status("status-unpaired")
        status.keyId = "a1b2c3d4"
        let line = try #require(PairingLine.derive(status: status, link: online, shelfRunning: false))
        #expect(line.state == .keyOnly)
        #expect(!line.isPaired)
        #expect(line.text == "Waiting for a job from Shelf")
        #expect(line.tone == .muted)
        #expect(line.help(now: now) == """
            Pairing lets Shelf hand jobs to shelf-bridge.
            Bridge key: a1b2c3d4
            Shelf is not running
            No job from Shelf in the last 24 hours
            1 job waits for a signature: not from Shelf, or Shelf holds another key.
            Shelf Bench can't see Shelf's key. Check Shelf > Settings > Agents, or hand a job to an agent from Shelf to confirm.
            """)
        #expect(line.accessibilityLabel(now: now) == "Waiting for a job from Shelf, Shelf is not running, no job from Shelf in the last 24 hours")
    }

    /// A key and no job at all in the status: still unproven.
    @Test func keyWithNoJobs() throws {
        var status = try Fixture.status("status-busy")
        status.jobs = []
        let line = try #require(PairingLine.derive(status: status, link: online, shelfRunning: true))
        #expect(line.state == .keyOnly)
        #expect(line.unsignedLine == nil)
    }

    /// A signed job with no time yet still proves the pairing.
    @Test func pendingJobFromShelf() throws {
        var status = try Fixture.status("status-busy")
        status.jobs = status.jobs.filter { $0.state == "needs-approval" }
        let line = try #require(PairingLine.derive(status: status, link: online, shelfRunning: true))
        #expect(line.lastJob == .pending)
        #expect(line.state == .paired)
        #expect(!line.showsAge)
        #expect(line.lastJobLine(now: now) == "A job from Shelf is waiting to start")
    }

    /// Without Bridge's status there is nothing to be paired with: the segment hides.
    @Test func hiddenWithoutABridge() throws {
        let status = try Fixture.status("status-busy")
        #expect(SidebarBuilder.build(status: nil, link: .looking, now: now).pairing == nil)
        #expect(SidebarBuilder.build(status: nil, link: .absent, now: now).pairing == nil)
        #expect(SidebarBuilder.build(status: nil, link: .unsupported(bridge: "9.0.0"), now: now).pairing == nil)
        #expect(SidebarBuilder.build(status: nil, link: .offline(lastSeen: nil), now: now).pairing == nil)
        // Offline the key in the last status still stands.
        let off = SidebarBuilder.build(status: status, link: .offline(lastSeen: Fixture.seen), now: Fixture.seen + 300, timeZone: Fixture.tz)
        #expect(off.pairing?.keyId == "630dcd29")
    }

    /// Only the tooltip moves with the clock; Shelf opening or closing changes the model.
    @Test func theModelDoesNotMoveWithTheSecond() throws {
        let status = try Fixture.status("status-busy")
        let a = SidebarBuilder.build(status: status, link: online, now: now, timeZone: Fixture.tz)
        let b = SidebarBuilder.build(status: status, link: online, now: now + 1, timeZone: Fixture.tz)
        #expect(a == b)
        let open = SidebarBuilder.build(status: status, link: online, now: now, shelfRunning: true, timeZone: Fixture.tz)
        #expect(open != a)
    }
}
