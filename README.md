# Managing multiple terminals remotely with Claude Code

Run as many Claude Code terminals as you want on a machine, and reach each one
from anywhere, including your phone: the Claude.ai web app, the desktop app, SSH,
or a local terminal. They keep running when you disconnect.

## Workbenches

A workbench is just a terminal. It's the name I give them, because that's how one
feels to use: a single space where you bring together agents, tools, and context
to do a piece of work. That's why I use this. You build your own architecture on
top of it.

Each one is a remote-controlled session you spawn on demand, and any terminal can
spawn more from inside itself. The only limit is RAM. The rest of this is how to
build one.

## The whole thing in one command

```bash
tmux new-session -d -s myagent -c ~/myproject
tmux send-keys -t myagent \
  'claude --remote-control "myagent" --dangerously-skip-permissions' Enter
```

A detached tmux session named `myagent`, running Claude Code with Remote Control
on. The rest of this README covers the flags, how to hand it a first prompt
safely, and how to get back in.

## The flags

| Flag | What it does |
|---|---|
| `--remote-control [name]` | Turn on Remote Control and optionally name the session. A named session maps the app and URL to a name you chose. |
| `--remote-control-session-name-prefix <prefix>` | Auto-generate the name from a prefix instead (Claude appends a unique suffix). The default prefix is the hostname. |
| `--dangerously-skip-permissions` | Run tool calls without prompting, so the session works unattended. Use it only in a trusted or sandboxed environment. |
| `--allow-dangerously-skip-permissions` | A softer form that makes the skip available without turning it on by default. |
| `--plugin-dir <path>` | Load a plugin (custom skills, persona, commands) from a directory or `.zip` for this session. Repeatable. Optional. |

Two ways to name the Remote Control session:

- **Named**: `--remote-control "myagent"` gives the session exactly that name. Map
  it one-to-one to your tmux session.
- **Prefix**: `--remote-control-session-name-prefix myagent` produces
  `myagent-<suffix>`. Useful when a script starts several at once and you want
  unique names.

## tmux: the detached session

```bash
tmux new-session -d -s <name> -c <dir>
```

- `-d` starts the session detached, in the background, so it keeps running with
  nothing attached.
- `-s <name>` sets the session name you attach by.
- `-c <dir>` sets the directory Claude starts in.

You can pass the command as a final argument to `new-session`
(`tmux new-session -d -s n -c d "claude ..."`). That works with no opening prompt,
but it makes feeding a first prompt awkward. See below.

## Feeding the first prompt

To start Claude and hand it an opening message, start a shell in the tmux session
and type the command into it with `send-keys`:

```bash
SEED='Audit this repo for TODOs and summarise what you find.'
SEED_ESC=$(printf '%q' "$SEED")
tmux send-keys -t myagent \
  "claude --remote-control \"myagent\" --dangerously-skip-permissions $SEED_ESC" Enter
```

`send-keys` sends its argument to the shell as literal keystrokes, and the shell
parses that line. A seed prompt is arbitrary text: spaces, quotes, `$`, backticks,
newlines. Without quoting, spaces split it into separate arguments, and `$(...)`
or backticks run as command substitution before Claude sees them.

`printf '%q'` produces a shell-safe version of the string that parses back to the
original as a single argument, with no splitting and no substitution. Quote the
seed; don't drop it in raw.

With no seed prompt, the simpler form is fine and Claude just starts interactive:
`tmux new-session -d -s myagent -c ~/myproject "claude --remote-control myagent --dangerously-skip-permissions"`.

## Getting back in

### Browser or app

At boot, Claude prints a Remote Control link:

```
https://claude.ai/code/session_XXXXXXXX
```

Open it in the web app or on your phone to drive the session. To read it from a
script, poll the pane until it appears:

```bash
for _ in $(seq 1 15); do
  sleep 1
  URL=$(tmux capture-pane -t myagent -p -S -200 \
        | grep -oE 'https://claude\.ai/code/session_[a-zA-Z0-9_-]+' | tail -1)
  [[ -n "$URL" ]] && break
done
echo "$URL"
```

`capture-pane -p` prints the pane text; `-S -200` includes the last 200 scrollback
lines, in case the link scrolled off. Give it a few seconds to register.

### Local tmux

```bash
tmux attach -t myagent
```

### SSH

```bash
ssh <user>@<host> -t tmux attach -t myagent
```

`-t` forces a TTY so tmux has a real terminal to attach to. Detach with `Ctrl-b d`
and the session keeps running. All three routes reach the same live session.

## Reference script

[`spawn-remote.sh`](spawn-remote.sh) is the recipe as one runnable script. It
checks prereqs, refuses to clobber an existing session, starts the detached tmux
session, feeds an optional seed prompt with the quoting above, captures the URL,
and prints the three ways to attach.

```bash
chmod +x spawn-remote.sh

./spawn-remote.sh <name> [dir] [seed-prompt]

# examples
./spawn-remote.sh myagent
./spawn-remote.sh myagent ~/myproject
./spawn-remote.sh myagent ~/myproject 'Find and fix the failing test.'
```

An agent can run it too, which is how one session starts the others.

## Requirements and notes

- tmux and the `claude` CLI on `PATH`.
- Run it on an always-on machine, such as a cheap VPS, so the terminals stay
  reachable any time, even when your own computer is off.
- `--dangerously-skip-permissions` lets the agent run tools without asking. Only
  use it where you trust the environment.
- A blank `tmux capture-pane` from a running Claude session is normal; the
  full-screen UI doesn't render into the captured buffer. The boot URL still shows
  in the early scrollback, which is why the script polls right after launch.
