#!/usr/bin/env bats
load helper

# Real keypresses: an interactive zsh in a pseudo-terminal loads a throwaway .zshrc that sets
# $1, sources setlist, then runs $2. A command that prints $((...)) shows the result only if it ran.
rc() {
  mkdir -p "$BATS_TEST_TMPDIR/dot"
  printf '%s\n' "SETLIST_QUEUE='$BATS_TEST_TMPDIR/state/queue'" "${1-}" \
    "source '$REPO/setlist.plugin.zsh'" "${2-}" > "$BATS_TEST_TMPDIR/dot/.zshrc"
}
keys() { zsh -f "$REPO/tests/pty.zsh" "$BATS_TEST_TMPDIR/dot" "$@"; }
queue() {
  printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/q"
  zsh -f -c "SETLIST_QUEUE='$BATS_TEST_TMPDIR/state/queue'; source '$REPO/setlist.plugin.zsh'; setlist '$BATS_TEST_TMPDIR/q'"
}
count() { grep -c -- "$1" <<< "$output" || true; }

@test "pty: Ctrl-N types the next command and Enter runs it" {
  rc; queue 'print -r -- ran:$((6*7))'
  run keys $'\x0e' $'\r'
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"setlist 1/1"* ]] || return 1
  [ "$(count 'ran:42')" -eq 1 ] || return 1
}

@test "pty: Ctrl-P steps back to the previous command" {
  rc; queue 'print -r -- one:$((1+0))' 'print -r -- two:$((1+1))'
  run keys $'\x0e' $'\x0e' $'\x10' $'\r'
  [ "$(count 'one:1')" -eq 1 ] || return 1
  [ "$(count 'two:2')" -eq 0 ] || return 1
}

@test "pty: Ctrl-Q reaches zsh through the terminal and queues the line" {
  rc
  run keys 'print -r -- q:$((2+2))' $'\x11' $'\x0e' $'\r'
  [[ "$output" == *"setlist: queued 1, now 0/1"* ]] || return 1
  [ "$(count 'q:4')" -eq 1 ] || return 1
}

@test "pty: with flow control back on, the terminal swallows Ctrl-Q" {
  rc "" "setopt flowcontrol"
  run keys 'print -r -- q:$((2+2))' $'\x11' $'\r'
  [ "$(count 'queued')" -eq 0 ] || return 1
  [ ! -s "$BATS_TEST_TMPDIR/state/queue" ] || return 1
}

@test "pty: after a later bindkey -v the keys work in insert and command mode" {
  rc "" "bindkey -v"
  queue 'print -r -- ins:$((3+4))' 'print -r -- cmd:$((4+4))'
  run keys $'\x0e' $'\r' $'\e' @pause $'\x0e' $'\r'
  [ "$(count 'ins:7')" -eq 1 ] || return 1
  [ "$(count 'cmd:8')" -eq 1 ] || return 1
}

@test "pty: with an empty queue Ctrl-P is history up again" {
  rc
  run keys $'print -r -- h:$((3*3))\r' $'\x10' $'\r'
  [ "$(count 'h:9')" -eq 2 ] || return 1
}

@test "pty: SETLIST_NO_BIND leaves the keys to zsh" {
  rc "SETLIST_NO_BIND=1"; queue 'print -r -- ran:$((6*7))'
  run keys $'print -r -- h:$((3*3))\r' $'\x10' $'\r'
  [ "$(count 'h:9')" -eq 2 ] || return 1
  [ "$(count 'ran:42')" -eq 0 ] || return 1
}

@test "pty: setlist -h at a real prompt names the keys the line editor has" {
  rc
  run keys $'setlist -h\r'
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"  Ctrl-N           type the next command; Enter runs it"* ]] || return 1
  [[ "$output" == *"  Ctrl-Q           queue the typed line, or the clipboard"* ]] || return 1
  rc "SETLIST_KEY_NEXT='^Xn'" "bindkey -v"
  run keys $'setlist -h\r'
  [[ "$output" == *"  ^Xn              type the next command; Enter runs it"* ]] || return 1
  [[ "$output" == *"  Ctrl-P           type the previous command"* ]] || return 1
}
