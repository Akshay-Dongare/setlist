#!/bin/sh
# install.sh: put the "Add to setlist" Quick Action in ~/Library/Services, so text selected in any
# macOS app goes into the queue with one keyboard shortcut. The zsh plugin itself needs no install.
# Safe to re-run: a current Quick Action is left alone, one that runs another checkout is replaced.
# On Linux it installs nothing and prints the command to bind to a desktop hotkey.
set -eu

usage() { echo "usage: install.sh [--dry-run]"; echo "  --dry-run  say what would change, change nothing"; }
DRY=
case ${1-} in
  '') ;;
  --dry-run) DRY=1 ;;
  -h | --help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

ROOT=$(cd "$(dirname "$0")" && pwd -P)
ADD="$ROOT/bin/add-to-setlist"

if [ "$(uname -s)" != Darwin ]; then
  echo "setlist: nothing to install here; the Quick Action is for macOS."
  echo "To queue the text selected in any app, bind a desktop hotkey to:"
  echo "  $ADD --selection"
  exit 0
fi

NAME="Add to setlist.workflow"
SERVICES="$HOME/Library/Services"
DEST="$SERVICES/$NAME"
PBS=${SETLIST_PBS:-/System/Library/CoreServices/pbs}
tilde() { case $1 in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

# Automator runs this with the selection on stdin, PATH=/usr/bin:/bin and no zshrc, so it names
# the helper by its full path, single-quoted for zsh.
quoted=$(printf '%s' "$ADD" | sed "s/'/'\\\\''/g")
COMMAND="exec /bin/zsh '$quoted'"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/setlist.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cp -R "$ROOT/macos/$NAME" "$TMP/"
plutil -replace actions.0.action.ActionParameters.COMMAND_STRING -string "$COMMAND" \
  "$TMP/$NAME/Contents/document.wflow"
plutil -convert xml1 "$TMP/$NAME/Contents/document.wflow"
plutil -lint -s "$TMP/$NAME/Contents/Info.plist" "$TMP/$NAME/Contents/document.wflow"

if [ -d "$DEST" ] && diff -r "$TMP/$NAME" "$DEST" >/dev/null 2>&1; then
  echo "setlist: \"Add to setlist\" is already installed in $(tilde "$SERVICES")"
  exit 0
fi
if [ -e "$DEST" ]; then act=update done=updated; else act=install done=installed; fi
if [ -n "$DRY" ]; then
  echo "setlist: would $act \"Add to setlist\" in $(tilde "$SERVICES"), to run $ADD"
  exit 0
fi
mkdir -p "$SERVICES"
rm -rf "$DEST"
mv "$TMP/$NAME" "$DEST"
"$PBS" -update
echo "setlist: $done \"Add to setlist\" in $(tilde "$SERVICES"); it runs $ADD"
echo "Give it a shortcut in System Settings > Keyboard > Keyboard Shortcuts > Services > Text > Add to setlist"
