# Runner Desk

One window for your coding agents: what they are doing, what they ask, how much limit is left.
Click a job and answer it in its live terminal.

Runner Desk is a macOS app for [shelf-runner](https://github.com/Ted2xmen/shelf-runner) jobs. The
sidebar lists the runner's jobs by folder (Needs you on top), This Mac and the agent limits; the
right side shows the selected job's tmux window in an embedded terminal, or the finished job's
result and log. It never starts unattended work and never answers an agent for you: the runner
runs the jobs, you answer them.

> **Status: 0.1.0, first slice (D1), not released.** No signed build or Homebrew cask yet; build it
> from source. D1 has no actions (Stop, Run, Retry come later): stop a job with Ctrl-C in its
> terminal.

## How the terminal works

Each job you select opens its own grouped tmux session (`view-<id>`) on the runner's session, so
two views and your own `tmux attach` never change each other's window. Deselecting the job or
quitting Desk closes the view; the job goes on. "Open in Terminal" and "Copy tmux command" give the
same kind of view for Terminal.

## Requirements

- macOS 14 (Sonoma) or later
- `tmux` (`brew install tmux`); the path and socket come from shelf-runner's
  `~/.config/shelf-runner/config.toml` `[tmux]` when set
- shelf-runner for jobs (Desk opens without it and says so)

## Build from source

```sh
brew install xcodegen
scripts/gate.sh        # tests, generates RunnerDesk.xcodeproj, builds the app
open ~/Library/Caches/runner-desk-dd/Build/Products/Debug/Runner\ Desk.app
```

`runnerdesk://job/<id>` opens a job (Shelf's "Open in Desk", the runner's notifications).

## License

MIT, see [LICENSE](LICENSE). Uses [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT),
[shelf-runner](https://github.com/Ted2xmen/shelf-runner)'s `ShelfRunnerCore` (MIT) and
[Hugeicons](https://hugeicons.com) Free icons (MIT, `design/icons/LICENSE-hugeicons.md`).
