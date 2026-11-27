# Every test runs with a throwaway HOME, ZDOTDIR and state directory, so nothing reads or writes
# the real queue, the real clipboard or ~/Library/Services.

setup() { setup_helper_env; }

setup_helper_env() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home" ZDOTDIR="$BATS_TEST_TMPDIR/home"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/home/.local/state"
  unset SETLIST_QUEUE SETLIST_PASTE SETLIST_QUIET SETLIST_KEY_NEXT SETLIST_KEY_PREV SETLIST_KEY_ADD
  unset SETLIST_KEYMAPS SETLIST_NO_BIND WAYLAND_DISPLAY DISPLAY WSL_DISTRO_NAME
  export NO_COLOR=1
  mkdir -p "$HOME"
  # Ahead of the real tools on PATH, so a regression can never read the real clipboard or post a
  # real notification; a test that wants one of these writes its own stub with fakepath and stub.
  local t guard="$BATS_TEST_TMPDIR/guard"
  mkdir -p "$guard"
  for t in pbpaste wl-paste xclip xsel powershell.exe osascript notify-send; do
    printf '#!/bin/sh\necho "test reached the real %s" >&2\nexit 99\n' "$t" > "$guard/$t"
    chmod +x "$guard/$t"
  done
  export PATH="$guard:$PATH"
  cd "$BATS_TEST_TMPDIR"
}

# A PATH holding only the named system tools plus stubs written with stub(), so a test controls
# exactly which clipboard tools exist.
fakepath() {
  FAKEBIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$FAKEBIN"
  local t p
  for t in "$@"; do
    p="$(command -v "$t")" || { echo "fakepath: no $t on this machine" >&2; return 1; }
    ln -sf "$p" "$FAKEBIN/$t"
  done
}

# stub NAME BODY: a script on the fake PATH that runs BODY with sh
stub() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\n%s\n' "$2" > "$BATS_TEST_TMPDIR/bin/$1"
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

on_macos() { [ "$(uname -s)" = Darwin ]; }
