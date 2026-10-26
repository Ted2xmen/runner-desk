# Shelf Bench

One window for your coding agents: what they are doing, what they ask, how much limit is left.
Click a job and answer it in its live terminal.

Shelf Bench is a macOS workbench for coding agents. Start your own Claude Code, Codex or shell session
in any folder (New session, Cmd-N), and follow [shelf-bridge](https://github.com/Ted2xmen/shelf-bridge)
jobs when Bridge is installed. The sidebar lists sessions and jobs by folder (Needs you on top);
the right side shows the selected one's live terminal, or a finished job's result and log; the
status bar shows Bridge, This Mac and the agent limits. It never starts unattended work and
never answers an agent for you.

> **Status: 0.1.0, not released.** No signed build or Homebrew cask yet; build it from source.
> Bridge jobs have no actions yet (Stop, Run, Retry come later): stop a job with Ctrl-C in its
> terminal.

## Sessions

A session runs on Shelf Bench's own tmux server (`tmux -L shelf-bench`, with Shelf Bench's own
`tmux.conf` in `~/Library/Application Support/Shelf Bench/`), out of sight: no status line, no
prefix key, every key goes to the agent. It is separate from your own tmux server, your
`~/.tmux.conf` and Bridge's sessions. Sessions go on when Shelf Bench quits and come back when
it opens; they end with End session, or when you log out of macOS.

- Agents start through your login shell (`$SHELL -l`), so they are found where your shell finds
  them. When an agent exits, the session shows its exit code with Restart and End session.
- Several sessions can share a folder, with any mix of agents. Two agents may edit the same files.
- The mouse wheel scrolls back through tmux's history; while scrolled back, keys go to the
  scrollback, press `q` or Esc to return. Dragging selects and copies.
- "Open in Terminal" attaches Terminal to the same session. There is no prefix key, so close the
  Terminal window to leave; the session goes on.

## How Bridge jobs show

Each job you select opens its own grouped tmux session (`view-<id>`) on Bridge's session, so
two views and your own `tmux attach` never change each other's window. Deselecting the job or
quitting Bench closes the view; the job goes on. "Open in Terminal" and "Copy tmux command" give the
same kind of view for Terminal.

## Requirements

- macOS 14 (Sonoma) or later
- `tmux` (`brew install tmux`); the path and socket come from shelf-bridge's
  `~/.config/shelf-bridge/config.toml` `[tmux]` when set
- shelf-bridge for jobs (optional: sessions work without it)

## Build from source

```sh
brew install xcodegen
scripts/gate.sh        # tests, generates ShelfBench.xcodeproj, builds the app
open ~/Library/Caches/shelf-bench-dd/Build/Products/Debug/Shelf\ Bench.app
```

`shelfbench://job/<id>` opens a job. shelf-bridge opens it when you click one of its notifications
and Shelf Bench is installed.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): code structure, how Bench watches shelf-bridge, the
  two tmux servers, files and state, tests.
- [docs/ECOSYSTEM.md](docs/ECOSYSTEM.md): Shelf Bench, shelf-bridge and Shelf, and who does what.

## License

MIT, see [LICENSE](LICENSE). Uses [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT),
[shelf-bridge](https://github.com/Ted2xmen/shelf-bridge)'s `ShelfBridgeCore` (MIT) and
[Hugeicons](https://hugeicons.com) Free icons (MIT, `design/icons/LICENSE-hugeicons.md`) and
the Claude mark from [Simple Icons](https://simpleicons.org) (CC0) and the Codex mark from
[LobeHub Icons](https://github.com/lobehub/lobe-icons) (MIT). Claude is a trademark of Anthropic, Codex
of OpenAI; the marks only name the agent (`design/icons/agents/README.md`).
