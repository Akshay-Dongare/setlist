#!/usr/bin/env bats
load helper

# Ctrl-Q on an empty line, in a zsh whose PATH has only the stubs a test wrote and the tools
# setlist needs. $1 is environment, then the queue is printed one command per line.
zc() {
  fakepath mkdir mv rm cat
  env -i HOME="$HOME" PATH="$FAKEBIN" "$@" "$ZSH" -f -i -c "SETLIST_QUEUE='$BATS_TEST_TMPDIR/state/queue'; source '$REPO/setlist.plugin.zsh'; zle() { (( \$# )) || return 0; [[ \$1 == -M ]] && print -r -- \"msg: \$2\"; }; BUFFER=; setlist-add; print rc=\$?; for c in \$SETLIST_LIST; do print -r -- \"[\$c]\"; done" 2>&1
}
setup_file() { export ZSH="$(command -v zsh)"; }

NOTOOL='msg: setlist: no clipboard tool found; install wl-clipboard (Wayland), xclip or xsel (X11), or set SETLIST_PASTE to a command that prints the clipboard'

@test "SETLIST_PASTE overrides any clipboard tool" {
  stub pbpaste 'echo wrong'
  run zc SETLIST_PASTE='print -r -- "echo right"; print -r -- "echo two"'
  [ "${lines[1]}" = "rc=0" ] || return 1
  [ "${lines[2]}" = "[echo right]" ] || return 1
  [ "${lines[3]}" = "[echo two]" ] || return 1
}

@test "pbpaste is the clipboard where it exists" {
  stub pbpaste 'printf "echo mac\n"'
  stub xclip 'echo wrong'
  run zc DISPLAY=:0
  [ "${lines[2]}" = "[echo mac]" ] || return 1
}

@test "on Wayland wl-paste is read without its trailing newline, before xclip" {
  stub wl-paste '[ "$*" = "--no-newline" ] && printf "echo wl" || echo "bad args: $*"'
  stub xclip 'echo wrong'
  run zc WAYLAND_DISPLAY=wayland-0 DISPLAY=:0
  [ "${lines[2]}" = "[echo wl]" ] || return 1
}

@test "on X11 xclip is read, then xsel" {
  stub xclip '[ "$*" = "-selection clipboard -out" ] && echo "echo xclip" || echo "bad args: $*"'
  stub xsel '[ "$*" = "--clipboard --output" ] && echo "echo xsel" || echo "bad args: $*"'
  run zc DISPLAY=:0
  [ "${lines[2]}" = "[echo xclip]" ] || return 1
  rm "$BATS_TEST_TMPDIR/bin/xclip" "$BATS_TEST_TMPDIR/state/queue"
  run zc DISPLAY=:0
  [ "${lines[2]}" = "[echo xsel]" ] || return 1
}

@test "a tool for a display that is not there is skipped" {
  stub wl-paste 'echo wrong'
  stub xclip 'echo "echo xclip"'
  run zc DISPLAY=:0
  [ "${lines[2]}" = "[echo xclip]" ] || return 1
  run zc
  [ "${lines[0]}" = "$NOTOOL" ] || return 1
}

@test "on WSL the Windows clipboard comes through powershell.exe, CRs dropped" {
  stub powershell.exe '[ "$*" = "-NoProfile -Command Get-Clipboard" ] && printf "echo win\r\necho two\r\n" || echo "bad args: $*"'
  run zc
  [ "${lines[2]}" = "[echo win]" ] || return 1
  [ "${lines[3]}" = "[echo two]" ] || return 1
}

@test "with no clipboard tool Ctrl-Q says what to install and queues nothing" {
  run zc
  [ "${lines[0]}" = "$NOTOOL" ] || return 1
  [ "${lines[1]}" = "rc=1" ] || return 1
  [ "${#lines[@]}" -eq 2 ] || return 1
  [ ! -e "$BATS_TEST_TMPDIR/state/queue" ] || return 1
}

@test "a clipboard tool that fails queues nothing and shows none of its errors" {
  stub wl-paste 'echo "Nothing is copied" >&2; exit 1'
  run zc WAYLAND_DISPLAY=wayland-0
  [ "${lines[0]}" = "msg: setlist: nothing to queue" ] || return 1
  [ "${lines[1]}" = "rc=1" ] || return 1
  [[ "$output" != *"Nothing is copied"* ]] || return 1
}
