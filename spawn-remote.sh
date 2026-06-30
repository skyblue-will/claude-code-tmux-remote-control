#!/usr/bin/env bash
# spawn-remote.sh: start a headless Claude Code session inside a detached tmux
# session with Remote Control enabled, then print the three ways back in.
#
# Reachable via:
#   - Browser / app:  the https://claude.ai/code/session_... URL this prints
#   - Local tmux:     tmux attach -t <name>
#   - SSH:            ssh <user>@<host> -t tmux attach -t <name>
#
# Usage:
#   spawn-remote.sh <name> [dir] [seed-prompt]
#     name         tmux session name and Remote Control session name. Required.
#     dir          working directory for the session. Default: current dir.
#     seed-prompt  optional first message typed into Claude on launch.
#
# Requirements: tmux and the `claude` CLI on PATH.

set -euo pipefail

NAME="${1:?usage: spawn-remote.sh <name> [dir] [seed-prompt]}"
DIR="${2:-$PWD}"
SEED="${3:-}"

command -v tmux   >/dev/null || { echo "tmux not on PATH"   >&2; exit 1; }
command -v claude >/dev/null || { echo "claude not on PATH" >&2; exit 1; }

# Refuse if a session with this exact name is already alive. The leading '='
# forces an exact match. A bare `-t NAME` prefix-matches, so `-t foo` would
# also hit an existing `foobar`.
if tmux has-session -t "=$NAME" 2>/dev/null; then
  echo "Session '$NAME' already exists. Attach with: tmux attach -t $NAME" >&2
  exit 1
fi

# 1) Start a detached tmux session running a shell, with the working dir set.
#    -d  detached: runs in the background; we drive it with send-keys.
#    -s  session name (how you attach).
#    -c  directory Claude starts in.
tmux new-session -d -s "$NAME" -c "$DIR"

# 2) Build the claude command. The flags that matter:
#      --remote-control "<name>"        enable Remote Control and name the RC
#                                       session exactly, so the app and URL map
#                                       to a name you chose, not a generated one.
#      --dangerously-skip-permissions   run tool calls without prompting, so the
#                                       session works unattended. Use only in a
#                                       trusted or sandboxed environment.
CMD="claude --remote-control \"$NAME\" --dangerously-skip-permissions"

# 3) Feed the first prompt. This is the part that's easy to get wrong.
#    send-keys hands its argument to the shell as literal keystrokes, and the
#    shell then re-parses that line. A seed prompt is arbitrary text (spaces,
#    quotes, $, backticks, newlines), so it must be quoted to survive one round
#    of shell parsing as a single argument. printf '%q' emits a shell-safe
#    rendering that re-parses back to exactly the original: no word-splitting,
#    no command substitution. Without it, a space splits the prompt and a
#    $(...) would run before Claude ever sees it.
if [[ -n "$SEED" ]]; then
  SEED_ESC=$(printf '%q' "$SEED")
  CMD="$CMD $SEED_ESC"
fi

# Type the command + Enter into the session's shell.
tmux send-keys -t "$NAME" "$CMD" Enter

# 4) Capture the Remote Control URL. Claude prints a
#    https://claude.ai/code/session_... link at boot; poll the pane for it
#    (it can take a few seconds to appear, and may scroll up, hence -S -200).
echo "Waiting for Remote Control URL..."
URL=""
for _ in $(seq 1 15); do
  sleep 1
  URL=$(tmux capture-pane -t "$NAME" -p -S -200 2>/dev/null \
        | grep -oE 'https://claude\.ai/code/session_[a-zA-Z0-9_-]+' \
        | tail -1) || true   # no match must not trip set -e/pipefail
  [[ -n "$URL" ]] && break
done

HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}'); [[ -z "$HOST_IP" ]] && HOST_IP="<host>"

# 5) Report the three routes back in. All point at the same live session.
echo
echo "Session '$NAME' is live. Three ways in:"
echo "  Browser/app:  ${URL:-"(not captured in 15s, run: tmux capture-pane -t $NAME -p)"}"
echo "  Local tmux:   tmux attach -t $NAME"
echo "  SSH:          ssh ${USER:-$(whoami)}@${HOST_IP} -t tmux attach -t $NAME"
