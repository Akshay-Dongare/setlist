#!/usr/bin/env bats
load helper

# Run zsh code with setlist sourced and the shared queue in a throwaway file. The widgets are plain
# functions here, so they set BUFFER and the test prints it — no line editor needed.
zq() { zsh -f -i -c "SETLIST_QUEUE='$BATS_TEST_TMPDIR/state/queue'; source '$REPO/setlist.plugin.zsh'; $1" 2>&1; }
# The same, with $1 run before setlist is sourced, for bindings it has to find in place.
zqpre() { zsh -f -i -c "SETLIST_QUEUE='$BATS_TEST_TMPDIR/state/queue'; $1; source '$REPO/setlist.plugin.zsh'; $2" 2>&1; }
# A second process adding to the queue, the way the Quick Action does.
add() { zsh -f -c "SETLIST_QUEUE='$BATS_TEST_TMPDIR/state/queue'; source '$REPO/setlist.plugin.zsh'; setlist add"; }

queue() { printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/q"; }

# Stand in for the clipboard and for zle, so a test never reads the real clipboard.
clip() { printf '%s' "$1" > "$BATS_TEST_TMPDIR/clip"; }
pb() { printf "SETLIST_PASTE=\"cat '%s/clip'\"" "$BATS_TEST_TMPDIR"; }
ZLE='zle() { (( $# )) || return 0; [[ $1 == -M ]] && { print -r -- "msg: $2"; return 0; }; print -r -- "zle $*"; }'

WF="$BATS_TEST_DIRNAME/../macos/Add to setlist.workflow/Contents"

@test "keeps each command verbatim and skips blank lines and comments" {
  printf 'a  b\n\n   \n# comment\n  # indented comment\n  keep  indent \n"q" $HOME\nno newline' > "$BATS_TEST_TMPDIR/q"
  run zq "setlist '$BATS_TEST_TMPDIR/q'; for i in 1 2 3 4 5; do setlist-next; print -r -- \"[\$BUFFER]\"; done"
  [ "$status" -eq 0 ] || return 1
  [ "${lines[0]}" = "[a  b]" ] || return 1
  [ "${lines[1]}" = "[  keep  indent ]" ] || return 1
  [ "${lines[2]}" = '["q" $HOME]' ] || return 1
  [ "${lines[3]}" = "[no newline]" ] || return 1
  [ "${lines[4]}" = "[no newline]" ] || return 1
}

@test "next stops at the last command, prev stops at the first" {
  queue one two three
  run zq "setlist '$BATS_TEST_TMPDIR/q'; setlist-next; setlist-next; setlist-next; setlist-next; print \$BUFFER; setlist-prev; setlist-prev; setlist-prev; setlist-prev; print \$BUFFER"
  [ "${lines[0]}" = "three" ] || return 1
  [ "${lines[1]}" = "one" ] || return 1
}

@test "the cursor lands at the end of the typed command" {
  queue 'echo hello' two
  run zq "setlist '$BATS_TEST_TMPDIR/q'; setlist-next; print \$CURSOR; setlist-next; setlist-prev; print \$CURSOR"
  [ "${lines[0]}" = "10" ] || return 1
  [ "${lines[1]}" = "10" ] || return 1
}

@test "prev before the first next clears the buffer" {
  queue one two
  run zq "setlist '$BATS_TEST_TMPDIR/q'; BUFFER=typed; setlist-prev; print -r -- \"[\$BUFFER]\""
  [ "$output" = "[]" ] || return 1
}

@test "setlist shows the position and reset returns to the start" {
  queue one two three
  run zq "setlist; setlist '$BATS_TEST_TMPDIR/q'; setlist; setlist-next; setlist-next; setlist; setlist reset; setlist; setlist-next; print \$BUFFER"
  [ "${lines[0]}" = "setlist: queue is empty" ] || return 1
  [ "${lines[1]}" = "setlist: 0/3" ] || return 1
  [ "${lines[2]}" = "next: one" ] || return 1
  [ "${lines[3]}" = "setlist: 2/3" ] || return 1
  [ "${lines[4]}" = "next: three" ] || return 1
  [ "${lines[5]}" = "setlist: 0/3" ] || return 1
  [ "${lines[6]}" = "next: one" ] || return 1
  [ "${lines[7]}" = "one" ] || return 1
}

@test "reset with an empty queue fails" {
  run zq "setlist reset"
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"queue is empty"* ]] || return 1
}

@test "Ctrl-N, Ctrl-P and Ctrl-Q are bound from the start" {
  run zq "bindkey '^N'; bindkey '^P'; bindkey '^Q'"
  [ "${lines[0]}" = '"^N" setlist-next' ] || return 1
  [ "${lines[1]}" = '"^P" setlist-prev' ] || return 1
  [ "${lines[2]}" = '"^Q" setlist-add' ] || return 1
}

@test "with an empty queue Ctrl-N and Ctrl-P run the widgets they replaced" {
  run zq "$ZLE; BUFFER=typed; setlist-next; setlist-prev; print -r -- \"[\$BUFFER]\""
  [ "${lines[0]}" = "zle down-line-or-history" ] || return 1
  [ "${lines[1]}" = "zle up-line-or-history" ] || return 1
  [ "${lines[2]}" = "[typed]" ] || return 1
}

@test "they pass through to a custom widget, a bindkey -s string, or nothing" {
  run zqpre "bindkey '^N' history-search-forward; bindkey -s '^P' 'hello'" "$ZLE; setlist-next; setlist-prev"
  [ "${lines[0]}" = "zle history-search-forward" ] || return 1
  [ "${lines[1]}" = "zle -U hello" ] || return 1
  run zqpre "bindkey -r '^N'" "$ZLE; setlist-next; print rc=\$?"
  [ "$output" = "rc=1" ] || return 1
}

@test "re-sourcing keeps the widget to pass through to" {
  run zq "source '$REPO/setlist.plugin.zsh'; $ZLE; setlist-next"
  [ "$output" = "zle down-line-or-history" ] || return 1
}

@test "a queue loaded in one shell is there in another" {
  queue one two
  zq "setlist '$BATS_TEST_TMPDIR/q'" >/dev/null
  run zq "setlist; setlist-next; print \$BUFFER"
  [ "${lines[0]}" = "setlist: 0/2" ] || return 1
  [ "${lines[2]}" = "one" ] || return 1
}

@test "off empties the queue for every shell" {
  queue one
  zq "setlist '$BATS_TEST_TMPDIR/q'" >/dev/null
  zq "setlist off" >/dev/null
  run zq "setlist; $ZLE; setlist-next; setlist off; print ok"
  [ "${lines[0]}" = "setlist: queue is empty" ] || return 1
  [ "${lines[1]}" = "zle down-line-or-history" ] || return 1
  [ "${lines[2]}" = "ok" ] || return 1
}

@test "setlist add queues standard input, one command per line" {
  printf 'echo a\n\n# note\n  echo "b c"\n' | add > "$BATS_TEST_TMPDIR/out"
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = "setlist: queued 2, now 0/2" ] || return 1
  run zq "setlist-next; print -r -- \"[\$BUFFER]\"; setlist-next; print -r -- \"[\$BUFFER]\""
  [ "${lines[0]}" = "[echo a]" ] || return 1
  [ "${lines[1]}" = '[  echo "b c"]' ] || return 1
}

@test "setlist add with nothing to queue fails and changes nothing" {
  run add <<< $'\n# only a comment\n'
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"nothing to queue"* ]] || return 1
  [ ! -e "$BATS_TEST_TMPDIR/state/queue" ] || return 1
}

@test "a command added from outside comes next for a shell mid-queue" {
  queue one two
  run zq "setlist '$BATS_TEST_TMPDIR/q'; setlist-next; setlist-next; print 'echo three' | zsh -f -c \"SETLIST_QUEUE='$BATS_TEST_TMPDIR/state/queue'; source '$REPO/setlist.plugin.zsh'; setlist add\" >/dev/null; setlist; setlist-next; print \$BUFFER"
  [ "${lines[0]}" = "setlist: 2/3" ] || return 1
  [ "${lines[1]}" = "next: echo three" ] || return 1
  [ "${lines[2]}" = "echo three" ] || return 1
}

@test "a queue replaced from another shell starts from the top here" {
  queue one two three
  printf 'x\ny\n' > "$BATS_TEST_TMPDIR/q2"
  run zq "setlist '$BATS_TEST_TMPDIR/q'; setlist-next; setlist-next; zsh -f -c \"SETLIST_QUEUE='$BATS_TEST_TMPDIR/state/queue'; source '$REPO/setlist.plugin.zsh'; setlist '$BATS_TEST_TMPDIR/q2'\"; setlist; setlist-next; print \$BUFFER"
  [ "${lines[0]}" = "setlist: 0/2" ] || return 1
  [ "${lines[2]}" = "x" ] || return 1
}

@test "the queue lives under the XDG state directory by default" {
  run env HOME="$BATS_TEST_TMPDIR" XDG_STATE_HOME= zsh -f -c "source '$REPO/setlist.plugin.zsh'; print -r -- \$SETLIST_QUEUE"
  [ "$output" = "$BATS_TEST_TMPDIR/.local/state/setlist/queue" ] || return 1
  run env HOME="$BATS_TEST_TMPDIR" XDG_STATE_HOME="$BATS_TEST_TMPDIR/xdg" zsh -f -c "source '$REPO/setlist.plugin.zsh'; print -r -- \$SETLIST_QUEUE"
  [ "$output" = "$BATS_TEST_TMPDIR/xdg/setlist/queue" ] || return 1
}

@test "a missing or empty file fails and leaves the queue alone" {
  queue one two
  printf '# only\n\n' > "$BATS_TEST_TMPDIR/empty"
  run zq "setlist '$BATS_TEST_TMPDIR/q'; setlist-next; setlist '$BATS_TEST_TMPDIR/nope'; setlist '$BATS_TEST_TMPDIR/empty'; setlist '$BATS_TEST_TMPDIR'; setlist"
  [[ "$output" == *"setlist: cannot read $BATS_TEST_TMPDIR/nope"* ]] || return 1
  [[ "$output" == *"setlist: no commands in $BATS_TEST_TMPDIR/empty"* ]] || return 1
  [[ "$output" == *"setlist: cannot read $BATS_TEST_TMPDIR"$'\n'* ]] || return 1
  [[ "$output" == *"setlist: 1/2"$'\n'"next: two" ]] || return 1
}

@test "each failed load returns 1" {
  printf '# only\n' > "$BATS_TEST_TMPDIR/empty"
  run zq "setlist '$BATS_TEST_TMPDIR/nope' 2>/dev/null; print \$?; setlist '$BATS_TEST_TMPDIR/empty' 2>/dev/null; print \$?; setlist '$BATS_TEST_TMPDIR' 2>/dev/null; print \$?"
  [ "$output" = $'1\n1\n1' ] || return 1
}

@test "errors go to stderr and the position to stdout" {
  queue one
  run zsh -f -i -c "SETLIST_QUEUE='$BATS_TEST_TMPDIR/state/queue'; source '$REPO/setlist.plugin.zsh'; { setlist '$BATS_TEST_TMPDIR/nope'; setlist reset; setlist; setlist '$BATS_TEST_TMPDIR/q'; setlist; } 2>/dev/null"
  [ "$output" = $'setlist: queue is empty\nsetlist: 0/1\nnext: one' ] || return 1
}

@test "a file named off loads by path" {
  printf 'hi\n' > "$BATS_TEST_TMPDIR/off"
  run zq "cd '$BATS_TEST_TMPDIR'; setlist ./off; setlist-next; print \$BUFFER"
  [ "$output" = "hi" ] || return 1
}

@test "-h and --help print the commands, the keys bound here and the queue's path" {
  cat > "$BATS_TEST_TMPDIR/want" <<EOF
setlist: a command queue typed at the zsh prompt

usage:
  setlist FILE     replace the queue with a file's commands
  setlist          show the position and the next command
  setlist reset    go back to the start
  setlist add      queue standard input, e.g. pbpaste | setlist add
  setlist off      empty the queue
  setlist -h       show this help

keys:
  Ctrl-N           type the next command; Enter runs it
  Ctrl-P           type the previous command
  Ctrl-Q           queue the typed line, or the clipboard
                   when the line is empty

queue: $BATS_TEST_TMPDIR/state/queue
docs:  https://github.com/Akshay-Dongare/setlist
EOF
  zq "setlist -h; print rc=\$?" > "$BATS_TEST_TMPDIR/got"
  echo "rc=0" >> "$BATS_TEST_TMPDIR/want"
  diff "$BATS_TEST_TMPDIR/want" "$BATS_TEST_TMPDIR/got" || return 1
  zq "setlist --help; print rc=\$?" > "$BATS_TEST_TMPDIR/got"
  diff "$BATS_TEST_TMPDIR/want" "$BATS_TEST_TMPDIR/got" || return 1
}

@test "help goes to stdout, and leaves the queue and the position alone" {
  run zsh -f -i -c "SETLIST_QUEUE='$BATS_TEST_TMPDIR/state/queue'; source '$REPO/setlist.plugin.zsh'; setlist -h 2>&1 >/dev/null"
  [ -z "$output" ] || return 1
  [ ! -e "$BATS_TEST_TMPDIR/state" ] || return 1
  queue one two three
  run zq "setlist '$BATS_TEST_TMPDIR/q'; setlist-next; setlist-next; setlist -h >/dev/null; setlist --help >/dev/null; setlist"
  [ "$output" = $'setlist: 2/3\nnext: three' ] || return 1
}

@test "help shortens a queue path under HOME to ~, and only there" {
  run zsh -f -i -c "source '$REPO/setlist.plugin.zsh'; setlist -h"
  [ "${lines[13]}" = 'queue: ~/.local/state/setlist/queue' ] || return 1
  run zsh -f -i -c "SETLIST_QUEUE='${HOME}x/queue'; source '$REPO/setlist.plugin.zsh'; setlist -h"
  [ "${lines[13]}" = "queue: ${HOME}x/queue" ] || return 1
}

@test "a file named -h or --help loads by path" {
  printf 'dash\n' > "$BATS_TEST_TMPDIR/-h"
  printf 'long\n' > "$BATS_TEST_TMPDIR/--help"
  run zq "cd '$BATS_TEST_TMPDIR'; setlist ./-h; setlist-next; print \$BUFFER; setlist ./--help; setlist-next; print \$BUFFER"
  [ "$output" = $'dash\nlong' ] || return 1
}

@test "a CRLF file loads without the carriage returns" {
  printf 'one\r\n\r\n# c\r\ntwo\r\n' > "$BATS_TEST_TMPDIR/q"
  run zq "setlist '$BATS_TEST_TMPDIR/q'; setlist; setlist-next; print -r -- \"[\$BUFFER]\"; setlist-next; print -r -- \"[\$BUFFER]\""
  [ "${lines[0]}" = "setlist: 0/2" ] || return 1
  [ "${lines[1]}" = "next: one" ] || return 1
  [ "${lines[2]}" = "[one]" ] || return 1
  [ "${lines[3]}" = "[two]" ] || return 1
}

@test "flow control is off so Ctrl-Q reaches the shell" {
  run zq "[[ -o flowcontrol ]] && print on || print off"
  [ "$output" = "off" ] || return 1
}

@test "the three widgets are registered with zle" {
  run zq 'zmodload zsh/zleparameter; print -r -- $widgets[setlist-add] $widgets[setlist-next] $widgets[setlist-prev]'
  [ "$output" = "user:setlist-add user:setlist-next user:setlist-prev" ] || return 1
}

@test "Ctrl-Q queues the line verbatim and clears it" {
  clip 'from clipboard'
  run zq "$(pb); BUFFER='  echo \"a  b\" \$HOME '; setlist-add; print -r -- \"rc=\$? [\$BUFFER]\"; setlist; setlist-next; print -r -- \"[\$BUFFER]\""
  [ "${lines[0]}" = "rc=0 []" ] || return 1
  [ "${lines[1]}" = "setlist: 0/1" ] || return 1
  [ "${lines[2]}" = 'next:   echo "a  b" $HOME ' ] || return 1
  [ "${lines[3]}" = '[  echo "a  b" $HOME ]' ] || return 1
}

@test "Ctrl-Q on an empty line queues the clipboard, one command per line" {
  clip $'docker build -t x .\r\n\n# note\n  curl http://h/  \nlast'
  run zq "$(pb); BUFFER=''; setlist-add; setlist; for i in 1 2 3; do setlist-next; print -r -- \"[\$BUFFER]\"; done"
  [ "${lines[0]}" = "setlist: 0/3" ] || return 1
  [ "${lines[1]}" = "next: docker build -t x ." ] || return 1
  [ "${lines[2]}" = "[docker build -t x .]" ] || return 1
  [ "${lines[3]}" = "[  curl http://h/  ]" ] || return 1
  [ "${lines[4]}" = "[last]" ] || return 1
}

@test "Ctrl-Q on a line of only spaces reads the clipboard" {
  clip 'echo clip'
  run zq "$(pb); BUFFER='   '; setlist-add; setlist-next; print -r -- \"[\$BUFFER]\""
  [ "$output" = "[echo clip]" ] || return 1
}

@test "Ctrl-Q with nothing to queue fails and leaves the queue empty" {
  clip $'\n# only a comment\n'
  run zq "$(pb); BUFFER=''; setlist-add; print rc=\$?; setlist"
  [ "${lines[0]}" = "rc=1" ] || return 1
  [ "${lines[1]}" = "setlist: queue is empty" ] || return 1
}

@test "Ctrl-Q appends to a loaded queue without moving the position" {
  queue one two
  run zq "setlist '$BATS_TEST_TMPDIR/q'; setlist-next; setlist-next; BUFFER=three; setlist-add; setlist; setlist-next; print \$BUFFER"
  [ "${lines[0]}" = "setlist: 2/3" ] || return 1
  [ "${lines[1]}" = "next: three" ] || return 1
  [ "${lines[2]}" = "three" ] || return 1
}

@test "backslashes and a mid-line CR survive loading" {
  printf '%s\n' "printf 'a\\tb\\n'" 'ls \' > "$BATS_TEST_TMPDIR/q"
  printf 'echo a\rb\r\n' >> "$BATS_TEST_TMPDIR/q"
  run zq "setlist '$BATS_TEST_TMPDIR/q'; setlist; for i in 1 2 3; do setlist-next; print -r -- \"[\$BUFFER]\"; done"
  [ "${lines[0]}" = "setlist: 0/3" ] || return 1
  [ "${lines[1]}" = "next: printf 'a\\tb\\n'" ] || return 1
  [ "${lines[2]}" = "[printf 'a\\tb\\n']" ] || return 1
  [ "${lines[3]}" = '[ls \]' ] || return 1
  [ "${lines[4]}" = $'[echo a\rb]' ] || return 1
}

@test "a file that is not UTF-8 still has its comments skipped" {
  printf '# windows \x93quoted\x94\r\necho one\r\n  # caf\xe9\r\necho caf\xe9\r\n' > "$BATS_TEST_TMPDIR/q"
  run env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 zsh -f -i -c "SETLIST_QUEUE='$BATS_TEST_TMPDIR/state/queue'; source '$REPO/setlist.plugin.zsh'; setlist '$BATS_TEST_TMPDIR/q'; print \${#SETLIST_LIST}"
  [ "$output" = "2" ] || return 1
}

@test "loading and queuing leave the caller's variables alone" {
  queue one '# c'
  run zq "line=L file=F rest=R reply=(Y) MATCH=M t=T; setlist '$BATS_TEST_TMPDIR/q'; BUFFER=x; setlist-add; setlist-next; print -r -- \"\$line \$file \$rest \$reply \$MATCH \$t\""
  [ "$output" = "L F R Y M T" ] || return 1
}

@test "loading a file after moving starts it from the top" {
  queue one two three
  printf 'x\ny\n' > "$BATS_TEST_TMPDIR/q2"
  run zq "setlist '$BATS_TEST_TMPDIR/q'; setlist-next; setlist-next; setlist '$BATS_TEST_TMPDIR/q2'; setlist; setlist-next; print \$BUFFER"
  [ "${lines[0]}" = "setlist: 0/2" ] || return 1
  [ "${lines[1]}" = "next: x" ] || return 1
  [ "${lines[2]}" = "x" ] || return 1
}

@test "re-sourcing setlist keeps the queue and the position" {
  queue one two three
  run zq "setlist '$BATS_TEST_TMPDIR/q'; setlist-next; setlist-next; source '$REPO/setlist.plugin.zsh'; setlist; setlist-next; print \$BUFFER"
  [ "${lines[0]}" = "setlist: 2/3" ] || return 1
  [ "${lines[1]}" = "next: three" ] || return 1
  [ "${lines[2]}" = "three" ] || return 1
}

@test "Ctrl-Q queues a comment-looking or multi-line line as one command" {
  clip ''
  run zq "$(pb); BUFFER='# keep me'; setlist-add; print rc=\$?; BUFFER=\$'a\n  b'; setlist-add; setlist; setlist-next; print -r -- \"[\$BUFFER]\"; setlist-next; print -r -- \"[\$BUFFER]\""
  [ "${lines[0]}" = "rc=0" ] || return 1
  [ "${lines[1]}" = "setlist: 0/2" ] || return 1
  [ "${lines[2]}" = "next: # keep me" ] || return 1
  [ "${lines[3]}" = "[# keep me]" ] || return 1
  [ "${lines[4]}" = "[a" ] || return 1
  [ "${lines[5]}" = "  b]" ] || return 1
}

@test "Ctrl-Q with nothing to queue leaves a blank line as it was" {
  clip $'# only\n'
  run zq "$(pb); BUFFER=\$' \\t '; setlist-add; print rc=\$?; [[ \$BUFFER == \$' \\t ' ]] && print unchanged; setlist"
  [ "${lines[0]}" = "rc=1" ] || return 1
  [ "${lines[1]}" = "unchanged" ] || return 1
  [ "${lines[2]}" = "setlist: queue is empty" ] || return 1
}

@test "Ctrl-Q refuses at a continuation prompt" {
  clip 'echo clip'
  run zq "$(pb); PREBUFFER=\$'for i in 1; do\n'; BUFFER='echo \$i'; setlist-add; print -r -- \"rc=\$? [\$BUFFER]\"; setlist"
  [ "${lines[0]}" = 'rc=1 [echo $i]' ] || return 1
  [ "${lines[1]}" = "setlist: queue is empty" ] || return 1
}

@test "Ctrl-Q reports below the prompt" {
  clip ''
  run zq "$(pb); $ZLE; BUFFER=hi; setlist-add; BUFFER=; setlist-add; PREBUFFER=x; setlist-add"
  [ "${lines[0]}" = "msg: setlist: queued 1, now 0/1" ] || return 1
  [ "${lines[1]}" = "msg: setlist: nothing to queue" ] || return 1
  [ "${lines[2]}" = "msg: setlist: finish or cancel the multi-line command first" ] || return 1
}

@test "Ctrl-Q after off starts a fresh queue" {
  queue one two
  run zq "setlist '$BATS_TEST_TMPDIR/q'; setlist-next; setlist off; BUFFER=a; setlist-add; BUFFER=b; setlist-add; setlist; setlist-next; print \$BUFFER"
  [ "${lines[0]}" = "setlist: 0/2" ] || return 1
  [ "${lines[1]}" = "next: a" ] || return 1
  [ "${lines[2]}" = "a" ] || return 1
}

@test "Ctrl-N and Ctrl-P report the position, and say so at either end" {
  queue one two
  run zq "$ZLE; setlist '$BATS_TEST_TMPDIR/q'; setlist-next; setlist-next; setlist-next; print -r -- \"[\$BUFFER]\"; setlist-prev; setlist-prev; print -r -- \"[\$BUFFER]\""
  [ "${lines[0]}" = "msg: setlist 1/2" ] || return 1
  [ "${lines[1]}" = "msg: setlist 2/2" ] || return 1
  [ "${lines[2]}" = "msg: setlist 2/2, end of queue" ] || return 1
  [ "${lines[3]}" = "[two]" ] || return 1
  [ "${lines[4]}" = "msg: setlist 1/2" ] || return 1
  [ "${lines[5]}" = "msg: setlist 1/2, start of queue" ] || return 1
  [ "${lines[6]}" = "[one]" ] || return 1
}

@test "setlist prints the next command, and says when the queue has ended" {
  queue 'echo one' 'echo two'
  run zq "setlist '$BATS_TEST_TMPDIR/q'; setlist; setlist-next; setlist-next; setlist"
  [ "${lines[0]}" = "setlist: 0/2" ] || return 1
  [ "${lines[1]}" = "next: echo one" ] || return 1
  [ "${lines[2]}" = "setlist: 2/2" ] || return 1
  [ "${lines[3]}" = "next: (end of queue)" ] || return 1
}

@test "a line with quotes and \$PWD comes back byte-for-byte" {
  printf '%s\n' "cd \"\$PWD/a b\" && echo 'it'\''s' \"\$PWD\" \$(pwd) \`date\`" > "$BATS_TEST_TMPDIR/q"
  run zq "cd /; setlist '$BATS_TEST_TMPDIR/q'; setlist-next; print -rn -- \"\$BUFFER\" | od -An -c | tr -s ' '"
  expected="$(printf '%s' "cd \"\$PWD/a b\" && echo 'it'\''s' \"\$PWD\" \$(pwd) \`date\`" | od -An -c | tr -s ' ')"
  [ "$output" = "$expected" ] || return 1
}

@test "the function and widget names are free in a clean zsh" {
  run zsh -f -i -c 'zmodload zsh/zleparameter; for n in setlist setlist-next setlist-prev setlist-add _setlist_read _setlist_load _setlist_append _setlist_store _setlist_pass _setlist_bind; do whence -w $n; (( ${+widgets[$n]} )) && print "widget $n"; done; true'
  [ "$output" = "$(printf '%s: none\n' setlist setlist-next setlist-prev setlist-add _setlist_read _setlist_load _setlist_append _setlist_store _setlist_pass _setlist_bind)" ] || return 1
}

@test "the Quick Action is a valid text service" {
  on_macos || skip "plutil is macOS only"
  plutil -lint -s "$WF/Info.plist" "$WF/document.wflow" || return 1
  [ "$(plutil -extract NSServices.0.NSSendTypes.0 raw -o - "$WF/Info.plist")" = "public.utf8-plain-text" ] || return 1
  [ "$(plutil -extract NSServices.0.NSMenuItem.default raw -o - "$WF/Info.plist")" = "Add to setlist" ] || return 1
  [ "$(plutil -extract workflowMetaData.serviceInputTypeIdentifier raw -o - "$WF/document.wflow")" = "com.apple.Automator.text" ] || return 1
  [ "$(plutil -extract actions.0.action.ActionParameters.inputMethod raw -o - "$WF/document.wflow")" = "0" ] || return 1
}

@test "a longer queue loaded from another shell starts from the top here" {
  queue one two
  printf 'w\nx\ny\nz\n' > "$BATS_TEST_TMPDIR/q2"
  run zq "setlist '$BATS_TEST_TMPDIR/q'; setlist-next; setlist-next; zsh -f -c \"SETLIST_QUEUE='$BATS_TEST_TMPDIR/state/queue'; source '$REPO/setlist.plugin.zsh'; setlist '$BATS_TEST_TMPDIR/q2'\"; setlist"
  [ "${lines[0]}" = "setlist: 0/4" ] || return 1
}

@test "a queue file shortened in place by hand starts from the top" {
  queue one two three
  run zq "setlist '$BATS_TEST_TMPDIR/q'; setlist-next; setlist-next; printf 'x\\0y\\0' > \$SETLIST_QUEUE; setlist"
  [ "${lines[0]}" = "setlist: 0/2" ] || return 1
}

@test "a position past the end of a hand-edited queue is pulled back to it" {
  queue a b c
  run zq "setlist '$BATS_TEST_TMPDIR/q'; setlist-next; setlist-next; setlist-next; printf 'one much longer command\\0' > \$SETLIST_QUEUE; setlist"
  [ "${lines[0]}" = "setlist: 1/1" ] || return 1
  [ "${lines[1]}" = "next: (end of queue)" ] || return 1
}

# octal modes of the queue's directory and file, with a loose umask in the caller
modes() { printf '%s' "zmodload zsh/stat; zstat -o +mode -- \${SETLIST_QUEUE:h}; zstat -o +mode -- \$SETLIST_QUEUE"; }

@test "a queue can hold tokens, so its directory is created 700 and its file 600" {
  queue one
  run zq "umask 022; setlist '$BATS_TEST_TMPDIR/q'; $(modes)"
  [ "${lines[0]}" = "040700" ] || return 1
  [ "${lines[1]}" = "0100600" ] || return 1
}

@test "Ctrl-Q and setlist add create the queue 600 as well" {
  run zq "umask 022; BUFFER=one; setlist-add; $(modes)"
  [ "${lines[0]}" = "040700" ] || return 1
  [ "${lines[1]}" = "0100600" ] || return 1
  rm -rf "$BATS_TEST_TMPDIR/state"
  echo two | zsh -f -c "umask 022; SETLIST_QUEUE='$BATS_TEST_TMPDIR/state/queue'; source '$REPO/setlist.plugin.zsh'; setlist add" >/dev/null
  run zq "$(modes)"
  [ "${lines[0]}" = "040700" ] || return 1
  [ "${lines[1]}" = "0100600" ] || return 1
}

@test "an existing directory keeps its mode" {
  mkdir -m 755 "$BATS_TEST_TMPDIR/state"
  queue one
  run zq "umask 022; setlist '$BATS_TEST_TMPDIR/q'; $(modes)"
  [ "${lines[0]}" = "040755" ] || return 1
  [ "${lines[1]}" = "0100600" ] || return 1
}

@test "the caller's umask is left as it was" {
  queue one
  run zq "umask 022; setlist '$BATS_TEST_TMPDIR/q'; BUFFER=x; setlist-add; umask"
  [ "$output" = "022" ] || return 1
}
