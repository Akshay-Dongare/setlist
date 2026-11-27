#!/usr/bin/env bats
load helper

# The Quick Action installer, always into the throwaway HOME, with pbs stubbed to log its calls.
WF='Library/Services/Add to setlist.workflow/Contents'
inst() { env SETLIST_PBS="$BATS_TEST_TMPDIR/pbs" "$@"; }
pbs_calls() { cat "$BATS_TEST_TMPDIR/pbs.log" 2>/dev/null; }
cmdstring() { plutil -extract actions.0.action.ActionParameters.COMMAND_STRING raw -o - "$HOME/$WF/document.wflow"; }
# a copy of the checkout at $1, so a test can install from an awkward path
copy_to() { mkdir -p "$1"; cp -R "$REPO/setlist.plugin.zsh" "$REPO/bin" "$REPO/macos" "$REPO/install.sh" "$REPO/uninstall.sh" "$1/"; }

setup() {
  setup_helper_env
  printf '#!/bin/sh\necho "$@" >> "%s/pbs.log"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/pbs"
  chmod +x "$BATS_TEST_TMPDIR/pbs"
}

@test "install writes the Quick Action with this checkout's path, and pbs re-reads Services" {
  on_macos || skip "macOS only"
  run inst "$REPO/install.sh"
  [ "$status" -eq 0 ] || return 1
  plutil -lint -s "$HOME/$WF/Info.plist" "$HOME/$WF/document.wflow" || return 1
  [ "$(cmdstring)" = "exec /bin/zsh '$(cd "$REPO" && pwd -P)/bin/add-to-setlist'" ] || return 1
  [ "$(pbs_calls)" = "-update" ] || return 1
  [[ "$output" == *'Keyboard Shortcuts > Services > Text > Add to setlist'* ]] || return 1
}

@test "the installed Quick Action is a text service with the selection on stdin" {
  on_macos || skip "macOS only"
  inst "$REPO/install.sh" >/dev/null
  [ "$(plutil -extract NSServices.0.NSSendTypes.0 raw -o - "$HOME/$WF/Info.plist")" = "public.utf8-plain-text" ] || return 1
  [ "$(plutil -extract NSServices.0.NSMenuItem.default raw -o - "$HOME/$WF/Info.plist")" = "Add to setlist" ] || return 1
  [ "$(plutil -extract workflowMetaData.serviceInputTypeIdentifier raw -o - "$HOME/$WF/document.wflow")" = "com.apple.Automator.text" ] || return 1
  [ "$(plutil -extract actions.0.action.ActionParameters.inputMethod raw -o - "$HOME/$WF/document.wflow")" = "0" ] || return 1
  [ "$(plutil -extract actions.0.action.ActionParameters.shell raw -o - "$HOME/$WF/document.wflow")" = "/bin/zsh" ] || return 1
}

@test "its command queues the selection the way Automator runs it, from an awkward path" {
  on_macos || skip "macOS only"
  dir="$BATS_TEST_TMPDIR/it's a dir/setlist"
  copy_to "$dir"
  inst "$dir/install.sh" >/dev/null
  script="$(cmdstring)"
  printf 'echo "$PWD"\n# skip\nls -la\n' | env -i HOME="$HOME" PATH=/usr/bin:/bin SETLIST_QUIET=1 /bin/zsh -c "$script"
  run env -i HOME="$HOME" zsh -f -c "source '$REPO/setlist.plugin.zsh'; print -r -- \$SETLIST_QUEUE; setlist"
  [ "${lines[0]}" = "$HOME/.local/state/setlist/queue" ] || return 1
  [ "${lines[1]}" = "setlist: 0/2" ] || return 1
  [ "${lines[2]}" = 'next: echo "$PWD"' ] || return 1
}

@test "a second install changes nothing and says so" {
  on_macos || skip "macOS only"
  inst "$REPO/install.sh" >/dev/null
  touch -t 200001010000 "$HOME/$WF/document.wflow"
  run inst "$REPO/install.sh"
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"already installed"* ]] || return 1
  [ "$(pbs_calls)" = "-update" ] || return 1
  [ "$(zsh -f -c "zmodload zsh/stat; zstat +mtime -- '$HOME/$WF/document.wflow'")" -lt 1000000000 ] || return 1
}

@test "installing from another checkout points the Quick Action there" {
  on_macos || skip "macOS only"
  copy_to "$BATS_TEST_TMPDIR/a"; copy_to "$BATS_TEST_TMPDIR/b"
  inst "$BATS_TEST_TMPDIR/a/install.sh" >/dev/null
  run inst "$BATS_TEST_TMPDIR/b/install.sh"
  [[ "$output" == *"updated"* ]] || return 1
  [ "$(cmdstring)" = "exec /bin/zsh '$(cd "$BATS_TEST_TMPDIR/b" && pwd -P)/bin/add-to-setlist'" ] || return 1
  [ "$(ls "$HOME/Library/Services")" = "Add to setlist.workflow" ] || return 1
}

@test "--dry-run says what it would do and changes nothing" {
  on_macos || skip "macOS only"
  run inst "$REPO/install.sh" --dry-run
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"would install"* ]] || return 1
  [ ! -e "$HOME/Library" ] || return 1
  [ -z "$(pbs_calls)" ] || return 1
}

@test "uninstall removes it once, then has nothing to do; its dry run changes nothing" {
  on_macos || skip "macOS only"
  inst "$REPO/install.sh" >/dev/null
  run inst "$REPO/uninstall.sh" --dry-run
  [[ "$output" == *"would remove"* ]] || return 1
  [ -d "$HOME/$WF" ] || return 1
  run inst "$REPO/uninstall.sh"
  [ "$status" -eq 0 ] || return 1
  [ ! -e "$HOME/Library/Services/Add to setlist.workflow" ] || return 1
  [ "$(pbs_calls)" = $'-update\n-update' ] || return 1
  run inst "$REPO/uninstall.sh"
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"not installed"* ]] || return 1
  [ "$(pbs_calls)" = $'-update\n-update' ] || return 1
}

@test "on Linux there is nothing to install, so it prints the command for a desktop hotkey" {
  stub uname 'echo Linux'
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" SETLIST_PBS="$BATS_TEST_TMPDIR/pbs" "$REPO/install.sh"
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"$(cd "$REPO" && pwd -P)/bin/add-to-setlist --selection"* ]] || return 1
  [ ! -e "$HOME/Library" ] || return 1
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" "$REPO/uninstall.sh"
  [ "$status" -eq 0 ] || return 1
}

@test "an unknown option prints the usage" {
  run "$REPO/install.sh" --nope
  [ "$status" -eq 2 ] || return 1
  [[ "$output" == "usage: install.sh [--dry-run]"* ]] || return 1
  run "$REPO/uninstall.sh" --nope
  [ "$status" -eq 2 ] || return 1
  [[ "$output" == "usage: uninstall.sh [--dry-run]"* ]] || return 1
}
