#!/usr/bin/env bats
load helper
bats_require_minimum_version 1.5.0

# bin/add-to-setlist with a PATH of stubs plus the tools it needs. A notifier stub records what it
# was asked to show in $BATS_TEST_TMPDIR/shown.
setup_file() { export ZSH="$(command -v zsh)"; }
ha() {
  fakepath mkdir mv rm cat zsh
  env -i HOME="$HOME" PATH="$FAKEBIN" SETLIST_QUEUE="$BATS_TEST_TMPDIR/state/queue" "$@"
}
shown() { cat "$BATS_TEST_TMPDIR/shown" 2>/dev/null; }
queued() { zsh -f -c "SETLIST_QUEUE='$BATS_TEST_TMPDIR/state/queue'; source '$REPO/setlist.plugin.zsh'; _setlist_load; print -rl -- \$SETLIST_LIST"; }
OSA='printf "%s|" "$@" > "'"$BATS_TEST_TMPDIR"'/shown"'
NOSEL='add-to-setlist: no selection tool found; install wl-clipboard (Wayland), xclip or xsel (X11)'

@test "standard input is queued and the result is shown as a notification" {
  stub osascript "$OSA"
  run ha "$REPO/bin/add-to-setlist" <<< $'echo a\n# note\n  echo "b c"'
  [ "$status" -eq 0 ] || return 1
  [ "$output" = "setlist: queued 2, now 0/2" ] || return 1
  [ "$(queued)" = $'echo a\n  echo "b c"' ] || return 1
  [ "$(shown)" = "-e|on run argv|-e|display notification (item 1 of argv) with title \"setlist\"|-e|end run|setlist: queued 2, now 0/2|" ] || return 1
}

@test "notify-send shows it where there is no osascript" {
  stub notify-send 'printf "%s|" "$@" > "'"$BATS_TEST_TMPDIR"'/shown"'
  run ha "$REPO/bin/add-to-setlist" <<< 'echo a'
  [ "$(shown)" = "setlist|setlist: queued 1, now 0/1|" ] || return 1
}

@test "SETLIST_QUIET skips the notification, and no notifier is no error" {
  stub osascript "$OSA"
  run ha SETLIST_QUIET=1 "$REPO/bin/add-to-setlist" <<< 'echo a'
  [ "$status" -eq 0 ] || return 1
  [ -z "$(shown)" ] || return 1
  rm "$BATS_TEST_TMPDIR/bin/osascript"
  run ha "$REPO/bin/add-to-setlist" <<< 'echo b'
  [ "$status" -eq 0 ] || return 1
  [ "$output" = "setlist: queued 1, now 0/2" ] || return 1
}

@test "nothing to queue fails, on stderr and in the notification" {
  stub osascript "$OSA"
  run ha "$REPO/bin/add-to-setlist" <<< $'\n# only a comment'
  [ "$status" -eq 1 ] || return 1
  [ "$output" = "setlist: nothing to queue" ] || return 1
  [[ "$(shown)" == *"|setlist: nothing to queue|" ]] || return 1
  run --separate-stderr ha SETLIST_QUIET=1 "$REPO/bin/add-to-setlist" <<< ''
  [ -z "$output" ] || return 1
  [ "$stderr" = "setlist: nothing to queue" ] || return 1
}

@test "--selection reads the primary selection: wl-paste, then xclip, then xsel" {
  stub wl-paste '[ "$*" = "--primary --no-newline" ] && printf "echo wl" || echo "bad args: $*"'
  stub xclip '[ "$*" = "-selection primary -out" ] && echo "echo xclip" || echo "bad args: $*"'
  stub xsel '[ "$*" = "--primary --output" ] && echo "echo xsel" || echo "bad args: $*"'
  run ha WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 SETLIST_QUIET=1 "$REPO/bin/add-to-setlist" --selection
  run ha DISPLAY=:0 SETLIST_QUIET=1 "$REPO/bin/add-to-setlist" --selection
  rm "$BATS_TEST_TMPDIR/bin/xclip"
  run ha DISPLAY=:0 SETLIST_QUIET=1 "$REPO/bin/add-to-setlist" --selection
  [ "$(queued)" = $'echo wl\necho xclip\necho xsel' ] || return 1
}

@test "--selection with no selection tool says what to install" {
  stub notify-send 'printf "%s|" "$@" > "'"$BATS_TEST_TMPDIR"'/shown"'
  stub xclip 'echo wrong'
  run ha "$REPO/bin/add-to-setlist" --selection
  [ "$status" -eq 1 ] || return 1
  [ "$output" = "$NOSEL" ] || return 1
  [ "$(shown)" = "setlist|$NOSEL|" ] || return 1
  [ ! -e "$BATS_TEST_TMPDIR/state/queue" ] || return 1
}

@test "an unknown argument prints the usage" {
  run ha "$REPO/bin/add-to-setlist" --nope
  [ "$status" -eq 2 ] || return 1
  [ "$output" = "usage: add-to-setlist [--selection]" ] || return 1
}

@test "it runs through a symlink to it, as a hotkey path might" {
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
  ln -s "$REPO/bin/add-to-setlist" "$BATS_TEST_TMPDIR/elsewhere/add-to-setlist"
  run ha SETLIST_QUIET=1 "$BATS_TEST_TMPDIR/elsewhere/add-to-setlist" <<< 'echo linked'
  [ "$(queued)" = "echo linked" ] || return 1
}

@test "SETLIST_QUEUE set in ~/.zshenv reaches it, as it reaches every shell" {
  printf 'SETLIST_QUEUE=%q\n' "$BATS_TEST_TMPDIR/custom/queue" > "$HOME/.zshenv"
  fakepath mkdir mv rm cat zsh
  run env -i HOME="$HOME" PATH="$FAKEBIN" SETLIST_QUIET=1 "$REPO/bin/add-to-setlist" <<< 'echo env'
  [ -s "$BATS_TEST_TMPDIR/custom/queue" ] || return 1
}
