#!/usr/bin/env bats
load helper

# The ways plugin managers and .zshrc files load a plugin; each must give the same setlist.
q() { printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/q"; }
SHOW="setlist \"\$q\"; setlist-next; setlist-next; setlist-prev; print -r -- \"[\$BUFFER]\"; setlist; bindkey '^N'"
EXPECT=$'[one]\nsetlist: 1/2\nnext: two\n"^N" setlist-next'

# BUFFER and CURSOR exist before any widget runs, as they do in zle
run_as() { zsh -f -i -c "q='$BATS_TEST_TMPDIR/q' SETLIST_QUEUE='$BATS_TEST_TMPDIR/state/queue' BUFFER= CURSOR=0; $1; $SHOW" 2>&1; }

@test "a plain source of setlist.plugin.zsh" {
  q one two
  run run_as "source '$REPO/setlist.plugin.zsh'"
  [ "$output" = "$EXPECT" ] || return 1
}

@test "a source through a symlink, from another directory" {
  q one two
  ln -s "$REPO/setlist.plugin.zsh" "$BATS_TEST_TMPDIR/linked.zsh"
  run run_as "cd /; source '$BATS_TEST_TMPDIR/linked.zsh'"
  [ "$output" = "$EXPECT" ] || return 1
}

@test "a source from inside a function, as zinit does, keeps the state global" {
  q one two
  run run_as "load() { source '$REPO/setlist.plugin.zsh'; }; load; print -r -- \${(t)SETLIST_LIST} \${(t)_setlist_saved}"
  [ "${lines[0]}" = "array association" ] || return 1
  [ "${output#*$'\n'}" = "$EXPECT" ] || return 1
}

@test "the oh-my-zsh custom plugin layout: plugins/setlist/setlist.plugin.zsh" {
  q one two
  mkdir -p "$BATS_TEST_TMPDIR/custom/plugins"
  ln -s "$REPO" "$BATS_TEST_TMPDIR/custom/plugins/setlist"
  run run_as "ZSH_CUSTOM='$BATS_TEST_TMPDIR/custom'; plugins=(setlist); for p in \$plugins; do source \$ZSH_CUSTOM/plugins/\$p/\$p.plugin.zsh; done"
  [ "$output" = "$EXPECT" ] || return 1
}

@test "options a user may set do not change what setlist does" {
  q one '  # skipped' two
  run run_as "setopt ksh_arrays sh_word_split no_unset warn_create_global extended_glob rc_expand_param no_multibyte; source '$REPO/setlist.plugin.zsh'"
  [ "$output" = "$EXPECT" ] || return 1
  run zsh -f -i -c "setopt ksh_arrays sh_word_split no_unset warn_create_global extended_glob; SETLIST_QUEUE='$BATS_TEST_TMPDIR/state/queue'; BUFFER= CURSOR=0; source '$REPO/setlist.plugin.zsh'; zle() { (( \$# )) || return 0; [[ \$1 == -M ]] && print -r -- \"msg: \$2\" || print -r -- \"zle \$*\"; }; setlist off; setlist-next; BUFFER='a b'; setlist-add; setlist-next; print -r -- \"[\$BUFFER]\"; print one | setlist add"
  [ "$output" = $'zle down-line-or-history\nmsg: setlist: queued 1, now 0/1\nmsg: setlist 1/1\n[a b]\nsetlist: queued 1, now 1/2' ] || return 1
}

@test "every name setlist defines is free in a clean zsh" {
  names='zmodload zsh/zleparameter; print -rl -- ${(k)functions} ${(k)widgets} ${(k)parameters}'
  zsh -f -i -c "$names" | LC_ALL=C sort -u > "$BATS_TEST_TMPDIR/before"
  zsh -f -i -c "source '$REPO/setlist.plugin.zsh'; $names" | LC_ALL=C sort -u > "$BATS_TEST_TMPDIR/after"
  run comm -13 "$BATS_TEST_TMPDIR/before" "$BATS_TEST_TMPDIR/after"
  [ "$output" = "$(printf '%s\n' SETLIST_I SETLIST_INODE SETLIST_LIST SETLIST_QUEUE SETLIST_SIZE _setlist_append _setlist_bind _setlist_bound _setlist_clipboard _setlist_help _setlist_load _setlist_pass _setlist_read _setlist_saved _setlist_store setlist setlist-add setlist-next setlist-prev)" ] || return 1
}
