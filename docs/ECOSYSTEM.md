---
title: Shelf Bench and its neighbours
description: Where Shelf Bench sits next to shelf-bridge and Shelf, and who does what.
created_by: opencode
created: 2026-10-25T13:35:00+03:00
---

# Shelf Bench and its neighbours

## The three apps

**Shelf Bench** (this repo) is a macOS window for coding agents. It starts your own Claude Code,
Codex or shell sessions on its own tmux server, and it shows shelf-bridge's jobs, their live
terminals, the Mac's state and the agent limits. It reads Bridge's status; it does not control
Bridge (`App/Sources/System/StatusFeed.swift:5-7`, `BenchCore/Sources/BenchCore/Sessions.swift:4-7`).

**[shelf-bridge](https://github.com/Ted2xmen/shelf-bridge)** is an open-source background agent.
It runs agent jobs in tmux, publishes a status (a notification plus `heartbeat.json`), and writes
logs. Shelf Bench links to its `ShelfBridgeCore` library for the protocol types, pinned by revision
(`BenchCore/Package.swift:13-15`).

**Shelf** is a closed-source App Store app. For Shelf Bench it is only the other end of the
Bridge's contract: the side that sends signed commands to shelf-bridge. Shelf Bench does not talk
to Shelf.

The contract between them is
[protocol v2](https://github.com/Ted2xmen/shelf-bridge/blob/main/docs/protocol/v2.md) (version 2).
Shelf Bench accepts only `v == 2` and asks you to update shelf-bridge otherwise
(`BenchCore/Sources/BenchCore/Status.swift:22`, `BenchCore/Sources/BenchCore/Sidebar.swift:165-166`).

## Who does what

| Task | Shelf Bench | shelf-bridge |
| --- | --- | --- |
| Run queued agent jobs | No | Yes |
| Publish status | No; reads it (`App/Sources/System/StatusFeed.swift:23-37`) | Yes |
| Send commands (stop, run, retry) | Never; the only post is an unsigned ping that makes Bridge publish (`App/Sources/System/StatusFeed.swift:39-44`) | Receives them |
| Write queue files or Bridge's folders | Never; it only reads Bridge's files (`App/Sources/System/Files.swift:6-7`, `App/Sources/System/Files.swift:25-26`, `App/Sources/System/Files.swift:79-99`) | Yes |
| Sign anything, hold a pairing key | No; no Keychain use in the code | Holds the key, checks signatures |
| Show a job's live terminal | Yes, through a grouped tmux view (`BenchCore/Sources/BenchCore/Tmux.swift:58-68`) | Owns the tmux session |
| Start your own attended sessions | Yes, on `tmux -L shelf-bench` (`BenchCore/Sources/BenchCore/Sessions.swift:87-106`) | Never sees them |
| Open a job from a notification click | Handles `shelfbench://job/<id>` (`BenchCore/Sources/BenchCore/BenchURL.swift:9-15`) | Opens that URL when Shelf Bench is installed |

Shelf Bench also works with no Bridge at all: sessions, recent folders and an install hint
(`BenchCore/Sources/BenchCore/Sidebar.swift:161-164`). See
[ARCHITECTURE.md](ARCHITECTURE.md) for details.

## Sources

- `App/Sources/System/StatusFeed.swift:5-7`, `:23-37`, `:39-44`
- `App/Sources/System/Files.swift:6-7`, `:25-26`, `:79-99`
- `BenchCore/Package.swift:13-15`
- `BenchCore/Sources/BenchCore/Status.swift:22`
- `BenchCore/Sources/BenchCore/Sidebar.swift:161-166`
- `BenchCore/Sources/BenchCore/Sessions.swift:4-7`, `:87-106`
- `BenchCore/Sources/BenchCore/Tmux.swift:58-68`
- `BenchCore/Sources/BenchCore/BenchURL.swift:9-15`
- shelf-bridge (pinned revision `f815abd`): `Sources/ShelfBridgeCore/Notices.swift:76-95` (notification click), `Sources/ShelfBridgeCore/ShelfChannel.swift:19-21`, `:64` (status publish) and `:68-90` (ping)
