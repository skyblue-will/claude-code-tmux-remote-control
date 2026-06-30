# Driving Claude Code remotely with tmux

A small, self-contained recipe for running **Claude Code as a headless, always-on
session** you can reach from anywhere — the browser/app, SSH, or a local terminal.
Two pieces working together do the whole job:

- **tmux** keeps the session alive in the background, detached from any terminal.
- **Claude Code's Remote Control** exposes that same session at a `claude.ai/code`
  URL, so you can drive it from the web app or your phone.

Start one, walk away, pick it up from your phone, drop back to the terminal later —
the *same* session throughout.

## The whole thing in one command

```bash
tmux new-session -d -s myagent -c ~/myproject
tmux send-keys -t myagent \
  'claude --remote-control "myagent" --dangerously-skip-permissions' Enter
```

That's it: a detached tmux session named `myagent`, running Claude Code with
Remote Control on. Everything below is just (a) the flags, plainly; (b) how to
feed it a first prompt *safely*; and (c) how to get back in.

## The flags that matter

| Flag | What it does |
|---|---|
| `--remote-control [name]` | Turn on Remote Control and (optionally) name the session. Named → the app/URL maps to a name you chose. |
| `--remote-control-session-name-prefix <prefix>` | Alternative: auto-generate the RC name from a prefix (Claude appends a unique suffix). Default prefix is the hostname. |
| `--dangerously-skip-permissions` | Don't prompt for each tool call — the session runs unattended. This is what makes headless work. **Only in a trusted / sandboxed environment.** |
| `--allow-dangerously-skip-permissions` | Softer variant: *makes* the skip available without enabling it by default. |
| `--plugin-dir <path>` | Load a plugin (custom skills / persona / commands) from a directory or `.zip`, for this session only. Repeatable. Optional. |

**Two Remote Control forms — pick one:**

- **Named** — `--remote-control "myagent"`: the RC session is exactly `myagent`.
  Predictable; map it 1:1 to your tmux session name.
- **Prefix** — `--remote-control-session-name-prefix myagent`: Claude generates
  `myagent-<unique-suffix>`. Good when a script launches several at once and you
  want no name collisions.

## tmux: the detached session

```bash
tmux new-session -d -s <name> -c <dir>
```

- `-d` — **detached**: start it in the background, don't attach our terminal.
  This is what makes it a server-side, always-on session.
- `-s <name>` — the session name (you'll attach by it).
- `-c <dir>` — the working directory Claude starts in.

You *can* pass the command to run as a final argument to `new-session`
(`tmux new-session -d -s n -c d "claude …"`). That works when there's no opening
prompt, but it makes feeding a *first prompt* awkward — see the next section.

## Feeding the first prompt (the bit people get wrong)

To start Claude *and* hand it an opening message, the robust pattern is: start a
**shell** in the tmux session, then **type the command into it** with `send-keys`.

```bash
SEED='Audit this repo for TODOs and summarise what you find.'
SEED_ESC=$(printf '%q' "$SEED")
tmux send-keys -t myagent \
  "claude --remote-control \"myagent\" --dangerously-skip-permissions $SEED_ESC" Enter
```

Why `printf '%q'`? `send-keys` sends its argument to the shell as **literal
keystrokes**, and the shell then parses that line. A seed prompt is arbitrary
text — spaces, quotes, `$`, backticks, newlines. Without quoting:

- spaces split it into many arguments (Claude sees only the first word);
- `$(…)` or backticks would **execute** as command substitution before Claude
  ever sees them.

`printf '%q'` emits a shell-safe rendering of the string that re-parses back to
*exactly* the original, as a single argument — no splitting, no substitution.
It's the difference between a prompt that arrives intact and one that's mangled
(or a shell-injection footgun). **Quote the seed; never interpolate it raw.**

(No seed prompt? The simpler launch-as-argument form is fine — Claude just starts
interactive: `tmux new-session -d -s myagent -c ~/myproject "claude --remote-control myagent --dangerously-skip-permissions"`.)

## Getting back in

### 1. The browser / app URL

At boot, Claude prints a Remote Control link:

```
https://claude.ai/code/session_XXXXXXXX
```

Open it in the web app (or on your phone) to drive the session. To grab it from a
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

`capture-pane -p` prints the pane's text; `-S -200` includes the last 200
scrollback lines (the link may have scrolled up). Give it a few seconds — the
link appears once Remote Control registers.

### 2. Local tmux

```bash
tmux attach -t myagent
```

### 3. SSH from anywhere

```bash
ssh <user>@<host> -t tmux attach -t myagent
```

`-t` forces a TTY so tmux has a real terminal to attach to. Same session, now in
front of you; detach again with `Ctrl-b d` and it keeps running.

All three routes point at the **same live session** — switch between them freely.

## Reference script

[`spawn-remote.sh`](spawn-remote.sh) is the whole recipe as one runnable script:
it validates prereqs, refuses to clobber an existing session, starts the detached
tmux session, feeds an optional seed prompt (quoted correctly), captures the URL,
and prints all three attach routes.

```bash
chmod +x spawn-remote.sh

./spawn-remote.sh <name> [dir] [seed-prompt]

# examples
./spawn-remote.sh myagent
./spawn-remote.sh myagent ~/myproject
./spawn-remote.sh myagent ~/myproject 'Find and fix the failing test.'
```

## Requirements & caveats

- **tmux** and the **`claude`** CLI on `PATH`.
- `--dangerously-skip-permissions` lets the agent run tools without asking. That's
  the point of unattended/headless — but only do it where you trust the
  environment (a sandbox, your own VM). Don't point it at anything you'd mind an
  automated agent touching.
- A **blank `tmux capture-pane`** for a *running* Claude session is normal —
  Claude's full-screen UI doesn't render into the captured buffer. The boot URL
  still appears in the early scrollback, which is why we poll right after launch.
