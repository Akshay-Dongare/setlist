# Changelog

## 0.1.1 - 2026-11-27

- `setlist -h` and `setlist --help` print the commands, each action's keys as they are bound in
  the keymap in use, and the queue file's path. Before, `-h` was read as a file name.
- `bin/add-to-setlist -h` and `--help` print its usage; an unknown argument prints the same usage
  on standard error, before anything is read or queued.

## 0.1.0 - 2026-11-26

First release.

- Ctrl-N and Ctrl-P type the next and previous queued command at the prompt; with an empty queue
  they fall through to what they did before, per keymap.
- Ctrl-Q queues the line, or the clipboard on an empty line: pbpaste, wl-paste, xclip, xsel,
  powershell.exe on WSL, or `SETLIST_PASTE`.
- `setlist <file>`, `setlist add`, `setlist reset`, `setlist off`, and `setlist` for the position.
- One queue file for every terminal, created with mode 600 in a 700 directory.
- Keys bound in emacs, viins and vicmd; configurable with `SETLIST_KEY_*` and `SETLIST_KEYMAPS`,
  or left unbound with `SETLIST_NO_BIND`. Flow control is turned off only when Ctrl-Q or Ctrl-S
  is bound.
- `bin/add-to-setlist` queues standard input or, with `--selection`, the primary selection, and
  shows a notification.
- `install.sh` and `uninstall.sh` add and remove the macOS "Add to setlist" Quick Action.
- Tested on zsh 4.3.11 through 5.9, on macOS and Linux.
