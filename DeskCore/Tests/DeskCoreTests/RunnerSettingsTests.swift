import Foundation
import Testing
import ShelfRunnerCore
@testable import DeskCore

@Suite struct RunnerSettingsTests {
    let now = Fixture.seen + 20
    var online: RunnerLink { .connected(runner: "0.3.0", seen: Fixture.seen) }

    func settings(_ status: StatusV1?, _ link: RunnerLink, home: String = "/Users/test") -> RunnerSettings {
        let sidebar = SidebarBuilder.build(status: status, link: link, now: now, shelfRunning: true, timeZone: Fixture.tz)
        return RunnerSettings.derive(sidebar: sidebar, status: status, home: home)
    }

    @Test func running() throws {
        let s = settings(try Fixture.status("status-busy"), online)
        #expect(s.connection.text == "shelf-runner running")
        #expect(s.statusLines == ["Version 0.3.0", "Slots: 2 of 2 in use, 1 per folder"])
        #expect(s.connection.ageLine(now: now) == "Last heard 20 s ago")
        #expect(s.pausedLine == nil)
        #expect(s.statusNote == nil)
        #expect(s.statusCommand == nil)
        #expect(s.pairing?.state == .paired)
        #expect(s.pairingNote == "Runner Desk can't read Shelf's key; a job from Shelf proves the pairing works.")
        #expect(s.pairingCommand == nil)
        #expect(s.folders == [
            SettingsFolderRow(id: "/Users/test/SHELF-TEST", display: "~/SHELF-TEST", detail: "1 running \u{00B7} 4 waiting"),
            SettingsFolderRow(id: "/Users/test/Pantheon", display: "~/Pantheon", detail: "1 running \u{00B7} 2 waiting"),
        ])
        #expect(s.emptyFolders == nil)
    }

    @Test func pausedAndUnpaired() throws {
        var status = try Fixture.status("status-unpaired")
        status.paused = true
        let s = settings(status, online)
        #expect(s.pausedLine == "Paused: no new jobs start; running jobs go on.")
        #expect(s.pairing?.state == .unpaired)
        #expect(s.pairingNote == "The runner has no pairing key. Run this, then paste the SR1- code in Shelf > Settings > Agents.")
        #expect(s.pairingCommand?.text == "shelf-runner pair")
        #expect(s.folders?.map(\.detail) == ["1 waiting"])
    }

    @Test func keyOnly() throws {
        var status = try Fixture.status("status-unpaired")
        status.keyId = "a1b2c3d4"
        let s = settings(status, online)
        #expect(s.pairing?.text == "Waiting for a job from Shelf")
        #expect(s.pairingNote?.hasPrefix("Runner Desk can't see Shelf's key.") == true)
        #expect(s.pairingCommand == nil)
    }

    @Test func noFolders() throws {
        var status = try Fixture.status("status-idle")
        status.folders = []
        status.jobs = []
        let s = settings(status, online)
        #expect(s.folders == [])
        #expect(s.emptyFolders?.title == "No folders yet")
        #expect(s.emptyFolders?.command.text == "shelf-runner enable <folder>")
    }

    @Test func idleFolder() throws {
        var status = try Fixture.status("status-idle")
        status.jobs = []
        #expect(settings(status, online).folders?.map(\.detail) == ["No active jobs", "No active jobs"])
    }

    /// Without a runner's status the state and its hint stay; pairing and folders hide.
    @Test func withoutARunner() throws {
        let absent = settings(nil, .absent)
        #expect(absent.connection == .absent)
        #expect(absent.statusCommand == .install)
        #expect(absent.statusNote == "Not installed or never started. Sessions work without it; autonomous jobs need it.")
        #expect(absent.pairing == nil && absent.folders == nil && absent.emptyFolders == nil)
        #expect(absent.statusLines.isEmpty)

        let looking = settings(nil, .looking)
        #expect(looking.statusNote == "Reading heartbeat.json")
        #expect(looking.pairing == nil && looking.folders == nil)

        let old = settings(nil, .unsupported(runner: "9.0.0"))
        #expect(old.statusLines == ["Version 9.0.0"])
        #expect(old.statusNote == "This runner speaks another protocol version than Runner Desk.")
        #expect(old.pairing == nil && old.folders == nil)
    }

    /// Offline the last status still stands, with the doctor hint.
    @Test func offline() throws {
        let s = settings(try Fixture.status("status-busy"), .offline(lastSeen: Fixture.seen))
        #expect(s.connection.text == "shelf-runner offline")
        #expect(s.statusCommand == .doctor)
        #expect(s.statusNote?.hasPrefix("No heartbeat for over") == true)
        #expect(s.connection.ageLine(now: now) == "Last heard 20 s ago")
        #expect(s.pairing != nil && s.folders?.count == 2)
    }

    @Test func homeIsWrittenAsTilde() {
        #expect(RunnerSettings.abbreviate("/Users/test", home: "/Users/test") == "~")
        #expect(RunnerSettings.abbreviate("/Users/test/a/b", home: "/Users/test/") == "~/a/b")
        #expect(RunnerSettings.abbreviate("/Users/testing/a", home: "/Users/test") == "/Users/testing/a")
        #expect(RunnerSettings.abbreviate("/opt/x", home: "") == "/opt/x")
    }
}
