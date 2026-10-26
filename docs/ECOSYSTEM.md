---
title: Runner Desk and its neighbours
description: Where Runner Desk sits next to shelf-runner and Shelf, and who does what.
created_by: opencode
created: 2026-10-25T13:35:00+03:00
---

# Runner Desk and its neighbours

## The three apps

**Runner Desk** (this repo) is a macOS window for coding agents. It starts your own Claude Code,
Codex or shell sessions on its own tmux server, and it shows shelf-runner's jobs, their live
terminals, the Mac's state and the agent limits. It reads the runner's status; it does not control
the runner (`App/Sources/System/StatusFeed.swift:5-7`, `DeskCore/Sources/DeskCore/Sessions.swift:4-7`).

**[shelf-runner](https://github.com/Ted2xmen/shelf-runner)** is an open-source background runner.
It runs agent jobs in tmux, publishes a status (a notification plus `heartbeat.json`), and writes
logs. Runner Desk links to its `ShelfRunnerCore` library for the protocol types, pinned by revision
(`DeskCore/Package.swift:13-15`).

**Shelf** is a closed-source App Store app. For Runner Desk it is only the other end of the
runner's contract: the side that sends signed commands to shelf-runner. Runner Desk does not talk
to Shelf.

The contract between them is
[protocol v1](https://github.com/Ted2xmen/shelf-runner/blob/main/docs/protocol/v1.md) (version 1).
Runner Desk accepts only `v == 1` and asks you to update shelf-runner otherwise
(`DeskCore/Sources/DeskCore/Status.swift:22`, `DeskCore/Sources/DeskCore/Sidebar.swift:165-166`).

## Who does what

| Task | Runner Desk | shelf-runner |
| --- | --- | --- |
| Run queued agent jobs | No | Yes |
| Publish status | No; reads it (`App/Sources/System/StatusFeed.swift:23-37`) | Yes |
| Send commands (stop, run, retry) | Never; the only post is an unsigned ping that makes the runner publish (`App/Sources/System/StatusFeed.swift:39-44`) | Receives them |
| Write queue files or the runner's folders | Never; it only reads the runner's files (`App/Sources/System/Files.swift:6-7`, `App/Sources/System/Files.swift:25-26`, `App/Sources/System/Files.swift:79-99`) | Yes |
| Sign anything, hold a pairing key | No; no Keychain use in the code | Holds the key, checks signatures |
| Show a job's live terminal | Yes, through a grouped tmux view (`DeskCore/Sources/DeskCore/Tmux.swift:58-68`) | Owns the tmux session |
| Start your own attended sessions | Yes, on `tmux -L runner-desk` (`DeskCore/Sources/DeskCore/Sessions.swift:87-106`) | Never sees them |
| Open a job from a notification click | Handles `runnerdesk://job/<id>` (`DeskCore/Sources/DeskCore/DeskURL.swift:9-15`) | Opens that URL when Runner Desk is installed |

Runner Desk also works with no runner at all: sessions, recent folders and an install hint
(`DeskCore/Sources/DeskCore/Sidebar.swift:161-164`). See
[ARCHITECTURE.md](ARCHITECTURE.md) for details.

## Sources

- `App/Sources/System/StatusFeed.swift:5-7`, `:23-37`, `:39-44`
- `App/Sources/System/Files.swift:6-7`, `:25-26`, `:79-99`
- `DeskCore/Package.swift:13-15`
- `DeskCore/Sources/DeskCore/Status.swift:22`
- `DeskCore/Sources/DeskCore/Sidebar.swift:161-166`
- `DeskCore/Sources/DeskCore/Sessions.swift:4-7`, `:87-106`
- `DeskCore/Sources/DeskCore/Tmux.swift:58-68`
- `DeskCore/Sources/DeskCore/DeskURL.swift:9-15`
- shelf-runner (pinned revision `e41a716`): `Sources/ShelfRunnerCore/Notices.swift:76-94` (notification click), `Sources/ShelfRunnerCore/Bridge.swift:64-69` (status publish and ping)
