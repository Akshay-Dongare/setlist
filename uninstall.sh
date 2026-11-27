#!/bin/sh
# uninstall.sh: remove the "Add to setlist" Quick Action that install.sh put in ~/Library/Services.
# The plugin and the queue stay; `setlist off` empties the queue.
set -eu

usage() { echo "usage: uninstall.sh [--dry-run]"; echo "  --dry-run  say what would change, change nothing"; }
DRY=
case ${1-} in
  '') ;;
  --dry-run) DRY=1 ;;
  -h | --help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

if [ "$(uname -s)" != Darwin ]; then
  echo "setlist: nothing to uninstall here; remove the desktop hotkey in your desktop's settings."
  exit 0
fi

DEST="$HOME/Library/Services/Add to setlist.workflow"
PBS=${SETLIST_PBS:-/System/Library/CoreServices/pbs}
tilde() { case $1 in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

if [ ! -e "$DEST" ]; then
  echo "setlist: \"Add to setlist\" is not installed"
  exit 0
fi
if [ -n "$DRY" ]; then
  echo "setlist: would remove $(tilde "$DEST")"
  exit 0
fi
rm -rf "$DEST"
"$PBS" -update
echo "setlist: removed $(tilde "$DEST")"
