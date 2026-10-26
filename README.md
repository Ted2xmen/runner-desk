# Runner Desk

One window for your coding agents: what they are doing, what they ask, how much limit is left.
Click a job and answer it in its live terminal.

Runner Desk is a macOS desk for coding agents. Start your own Claude Code, Codex or shell session
in any folder (New session, Cmd-N), and follow [shelf-runner](https://github.com/Ted2xmen/shelf-runner)
jobs when the runner is installed. The sidebar lists sessions and jobs by folder (Needs you on top);
the right side shows the selected one's live terminal, or a finished job's result and log; the
status bar shows the runner, This Mac and the agent limits. It never starts unattended work and
never answers an agent for you.

> **Status: 0.1.0, not released.** No signed build or Homebrew cask yet; build it from source.
> Runner jobs have no actions yet (Stop, Run, Retry come later): stop a job with Ctrl-C in its
> terminal.

## Sessions

A session runs on Runner Desk's own tmux server (`tmux -L runner-desk`, with Runner Desk's own
`tmux.conf` in `~/Library/Application Support/Runner Desk/`), out of sight: no status line, no
prefix key, every key goes to the agent. It is separate from your own tmux server, your
`~/.tmux.conf` and the runner's sessions. Sessions go on when Runner Desk quits and come back when
it opens; they end with End session, or when you log out of macOS.

- Agents start through your login shell (`$SHELL -l`), so they are found where your shell finds
  them. When an agent exits, the session shows its exit code with Restart and End session.
- Several sessions can share a folder, with any mix of agents. Two agents may edit the same files.
- The mouse wheel scrolls back through tmux's history; while scrolled back, keys go to the
  scrollback, press `q` or Esc to return. Dragging selects and copies.
- "Open in Terminal" attaches Terminal to the same session. There is no prefix key, so close the
  Terminal window to leave; the session goes on.

## How runner jobs show

Each job you select opens its own grouped tmux session (`view-<id>`) on the runner's session, so
two views and your own `tmux attach` never change each other's window. Deselecting the job or
quitting Desk closes the view; the job goes on. "Open in Terminal" and "Copy tmux command" give the
same kind of view for Terminal.

## Requirements

- macOS 14 (Sonoma) or later
- `tmux` (`brew install tmux`); the path and socket come from shelf-runner's
  `~/.config/shelf-runner/config.toml` `[tmux]` when set
- shelf-runner for jobs (optional: sessions work without it)

## Build from source

```sh
brew install xcodegen
scripts/gate.sh        # tests, generates RunnerDesk.xcodeproj, builds the app
open ~/Library/Caches/runner-desk-dd/Build/Products/Debug/Runner\ Desk.app
```

`runnerdesk://job/<id>` opens a job. shelf-runner opens it when you click one of its notifications
and Runner Desk is installed.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): code structure, how Desk watches shelf-runner, the
  two tmux servers, files and state, tests.
- [docs/ECOSYSTEM.md](docs/ECOSYSTEM.md): Runner Desk, shelf-runner and Shelf, and who does what.

## License

MIT, see [LICENSE](LICENSE). Uses [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT),
[shelf-runner](https://github.com/Ted2xmen/shelf-runner)'s `ShelfRunnerCore` (MIT) and
[Hugeicons](https://hugeicons.com) Free icons (MIT, `design/icons/LICENSE-hugeicons.md`) and
the Claude mark from [Simple Icons](https://simpleicons.org) (CC0) and the Codex mark from
[LobeHub Icons](https://github.com/lobehub/lobe-icons) (MIT). Claude is a trademark of Anthropic, Codex
of OpenAI; the marks only name the agent (`design/icons/agents/README.md`).
