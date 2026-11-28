#!/usr/bin/env bats
load helper

# zsh with setlist sourced after $1, then $2; the widgets are plain functions here
zk() { zsh -f -i -c "SETLIST_QUEUE='$BATS_TEST_TMPDIR/state/queue'; $1; source '$REPO/setlist.plugin.zsh'; $2" 2>&1; }
ZLE='zle() { (( $# )) || return 0; [[ $1 == -M ]] && { print -r -- "msg: $2"; return 0; }; print -r -- "zle $*"; }'

@test "the keys are bound in emacs, viins and vicmd, so a later bindkey -v keeps them" {
  run zk "" "bindkey -v; for m in emacs viins vicmd; do bindkey -M \$m '^N'; bindkey -M \$m '^P'; bindkey -M \$m '^Q'; done"
  [ "$output" = "$(printf '"^%s" setlist-%s\n' N next P prev Q add N next P prev Q add N next P prev Q add)" ] || return 1
}

@test "the key variables move each action to another key" {
  run zk "SETLIST_KEY_NEXT='^X^N' SETLIST_KEY_PREV='\\ep' SETLIST_KEY_ADD='^Xq'" \
    "bindkey -M emacs '^X^N'; bindkey -M emacs '^[p'; bindkey -M emacs '^Xq'; bindkey -M emacs '^N'; bindkey -M emacs '^Q'"
  [ "${lines[0]}" = '"^X^N" setlist-next' ] || return 1
  [ "${lines[1]}" = '"^[p" setlist-prev' ] || return 1
  [ "${lines[2]}" = '"^Xq" setlist-add' ] || return 1
  [ "${lines[3]}" = '"^N" down-line-or-history' ] || return 1
  [ "${lines[4]}" = '"^Q" push-line' ] || return 1
}

@test "an empty key variable leaves that key alone" {
  run zk "SETLIST_KEY_ADD=" "bindkey -M emacs '^Q'; bindkey -M viins '^Q'; bindkey -M emacs '^N'"
  [ "${lines[0]}" = '"^Q" push-line' ] || return 1
  [ "${lines[1]}" = '"^Q" vi-quoted-insert' ] || return 1
  [ "${lines[2]}" = '"^N" setlist-next' ] || return 1
}

@test "SETLIST_NO_BIND defines the widgets and binds nothing" {
  run zk "SETLIST_NO_BIND=1" 'zmodload zsh/zleparameter; print -r -- $widgets[setlist-next] $widgets[setlist-prev] $widgets[setlist-add]; bindkey -M emacs "^N"; bindkey -M emacs "^Q"; bindkey -M vicmd "^P"; [[ -o flowcontrol ]] && print flowcontrol on'
  [ "${lines[0]}" = "user:setlist-next user:setlist-prev user:setlist-add" ] || return 1
  [ "${lines[1]}" = '"^N" down-line-or-history' ] || return 1
  [ "${lines[2]}" = '"^Q" push-line' ] || return 1
  [ "${lines[3]}" = '"^P" up-history' ] || return 1
  [ "${lines[4]}" = "flowcontrol on" ] || return 1
}

@test "SETLIST_KEYMAPS picks the keymaps, as an array or a string" {
  run zk "SETLIST_KEYMAPS=(emacs)" "bindkey -M emacs '^N'; bindkey -M viins '^N'; bindkey -M vicmd '^N'"
  [ "$output" = "$(printf '%s\n' '"^N" setlist-next' '"^N" self-insert' '"^N" down-history')" ] || return 1
  run zk "SETLIST_KEYMAPS='viins vicmd'" "bindkey -M emacs '^N'; bindkey -M viins '^N'; bindkey -M vicmd '^N'"
  [ "$output" = "$(printf '%s\n' '"^N" down-line-or-history' '"^N" setlist-next' '"^N" setlist-next')" ] || return 1
}

@test "an unknown keymap fails with the variable to fix and binds the rest" {
  run zk "SETLIST_KEYMAPS=(emacs nosuch)" "bindkey -M emacs '^N'"
  [ "${lines[0]}" = "setlist: no keymap 'nosuch' to bind in; remove it from SETLIST_KEYMAPS or create it first with bindkey -N" ] || return 1
  [ "${lines[1]}" = '"^N" setlist-next' ] || return 1
}

@test "flow control is turned off only when Ctrl-Q or Ctrl-S is bound" {
  run zk "" '[[ -o flowcontrol ]] && print on || print off'
  [ "$output" = "off" ] || return 1
  run zk "SETLIST_KEY_ADD='^Xq'" '[[ -o flowcontrol ]] && print on || print off'
  [ "$output" = "on" ] || return 1
  run zk "SETLIST_KEY_ADD='^Xq' SETLIST_KEY_PREV='^S'" '[[ -o flowcontrol ]] && print on || print off'
  [ "$output" = "off" ] || return 1
  run zk "SETLIST_KEY_ADD=\$'\\x11\\x01'" '[[ -o flowcontrol ]] && print on || print off'
  [ "$output" = "off" ] || return 1
  run zk "SETLIST_KEYMAPS=(vicmd)" '[[ -o flowcontrol ]] && print on || print off'
  [ "$output" = "off" ] || return 1
}

@test "with an empty queue each keymap falls through to its own old binding" {
  run zk "bindkey -s -M viins '^N' 'vi-string'" "$ZLE; KEYMAP=main; cmd() { setlist-next; setlist-prev; }; cmd; bindkey -v; cmd; KEYMAP=vicmd; cmd"
  [ "${lines[0]}" = "zle down-line-or-history" ] || return 1
  [ "${lines[1]}" = "zle up-line-or-history" ] || return 1
  [ "${lines[2]}" = "zle -U vi-string" ] || return 1
  [ "${lines[3]}" = "zle self-insert" ] || return 1
  [ "${lines[4]}" = "zle down-history" ] || return 1
  [ "${lines[5]}" = "zle up-history" ] || return 1
}

@test "a keymap setlist did not bind falls through to nothing" {
  run zk "SETLIST_KEYMAPS=(emacs)" "$ZLE; KEYMAP=vicmd; setlist-next; print rc=\$?"
  [ "$output" = "rc=1" ] || return 1
}

@test "re-sourcing keeps every keymap's old binding" {
  run zk "" "source '$REPO/setlist.plugin.zsh'; $ZLE; KEYMAP=vicmd; setlist-prev; KEYMAP=main; setlist-prev"
  [ "${lines[0]}" = "zle up-history" ] || return 1
  [ "${lines[1]}" = "zle up-line-or-history" ] || return 1
}

@test "a key moved by a later source is unbound from its old place" {
  run zk "" "SETLIST_KEY_NEXT='^X^N'; source '$REPO/setlist.plugin.zsh'; bindkey -M emacs '^N'; bindkey -M vicmd '^N'; bindkey -M emacs '^X^N'"
  [ "${lines[0]}" = '"^N" down-line-or-history' ] || return 1
  [ "${lines[1]}" = '"^N" down-history' ] || return 1
  [ "${lines[2]}" = '"^X^N" setlist-next' ] || return 1
}

# The three key lines of the help
keylines() { printf '%s\n' "$output" | sed -n '/^keys:$/,/^$/p' | sed '1d;$d'; }

@test "help names each action's key as it is bound in the keymap in use" {
  run zk "" "setlist -h"
  [ "$(keylines)" = "$(printf '%s\n' \
    '  Ctrl-N           type the next command; Enter runs it' \
    '  Ctrl-P           type the previous command' \
    '  Ctrl-Q           queue the typed line, or the clipboard' \
    '                   when the line is empty')" ] || return 1
  run zk "" "bindkey -v; setlist -h"
  [ "$(keylines | sed -n 1p)" = '  Ctrl-N           type the next command; Enter runs it' ] || return 1
}

@test "help shows a moved key in bindkey notation and an unbound action as (no key)" {
  run zk "SETLIST_KEY_NEXT='^X^N' SETLIST_KEY_PREV='\\ep' SETLIST_KEY_ADD=" "setlist -h"
  [ "$(keylines)" = "$(printf '%s\n' \
    '  ^X^N             type the next command; Enter runs it' \
    '  ^[p              type the previous command' \
    '  (no key)         queue the typed line, or the clipboard' \
    '                   when the line is empty')" ] || return 1
}

@test "help finds keys bound by hand, lists every one, and notices keys a reset removed" {
  run zk "SETLIST_NO_BIND=1" "bindkey '^[n' setlist-next; bindkey '^N' setlist-next; setlist -h"
  [ "$(keylines | sed -n 1p)" = '  Ctrl-N, ^[n      type the next command; Enter runs it' ] || return 1
  [ "$(keylines | sed -n 2p)" = '  (no key)         type the previous command' ] || return 1
  run zk "" "bindkey -d; setlist -h"
  [ "$(keylines | sed -n 1p)" = '  (no key)         type the next command; Enter runs it' ] || return 1
  [ "$(keylines | sed -n 3p)" = '  (no key)         queue the typed line, or the clipboard' ] || return 1
}

@test "help reads Ctrl-X only for a single control letter, and lists keys from the keymap in use" {
  run zk "SETLIST_KEY_NEXT='^Xn' SETLIST_KEY_PREV='^_' SETLIST_KEYMAPS=(vicmd)" "setlist -h"
  [ "$(keylines | sed -n 1p)" = '  (no key)         type the next command; Enter runs it' ] || return 1
  run zk "SETLIST_KEYMAPS=(emacs)" "bindkey -v; setlist -h"
  [ "$(keylines | sed -n 1p)" = '  (no key)         type the next command; Enter runs it' ] || return 1
  run zk "SETLIST_KEY_NEXT='^n'" "setlist -h"
  [ "$(keylines | sed -n 1p)" = '  Ctrl-N           type the next command; Enter runs it' ] || return 1
  run zk "SETLIST_KEY_NEXT='^Xn' SETLIST_KEY_PREV='^_'" "setlist -h"
  [ "$(keylines | sed -n 1p)" = '  ^Xn              type the next command; Enter runs it' ] || return 1
  [ "$(keylines | sed -n 2p)" = '  ^_               type the previous command' ] || return 1
}
