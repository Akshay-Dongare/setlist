# pty.zsh ZDOTDIR KEYS...: run an interactive zsh in a pseudo-terminal with ZDOTDIR/.zshrc and no
# global rc files, type each KEYS argument once the prompt is up, and print what the terminal showed.
# An argument @pause waits half a second, so a lone Esc is not read as the start of a sequence.
# Each carriage return in KEYS adds a prompt to wait for; ten seconds without one is a failure.
zmodload zsh/zpty zsh/datetime zsh/zselect || exit 2
emulate -L zsh

local dotdir=$1 buf= chunk keys
local -i want=1 deadline
shift
zpty t "ZDOTDIR=${(q)dotdir} PS1='<ready> ' PS2='<more> ' TERM=xterm zsh -d -i" || exit 2

# how many prompts buf shows
prompts() { local s=$buf; REPLY=0; while [[ $s == *'<ready> '* ]]; do s=${s#*'<ready> '}; (( REPLY++ )); done; }

# wait for the want-th prompt, collecting the terminal output in buf
ready() {
  deadline=$(( EPOCHSECONDS + 10 ))
  while prompts; (( REPLY < want )); do
    if zpty -r -t t chunk; then buf+=$chunk
    elif (( EPOCHSECONDS > deadline )); then print -r -- "$buf"; print "pty: TIMEOUT"; zpty -d t; exit 1
    else zselect -t 5; fi
  done
}

ready
for keys in "$@"; do
  if [[ $keys == @pause ]]; then zselect -t 50; continue; fi
  zpty -w -n t "$keys"
  want+=${#${keys//[^$'\r']}}
done
ready
zpty -w -n t $'exit\r'
deadline=$(( EPOCHSECONDS + 5 ))
while (( EPOCHSECONDS <= deadline )); do
  if zpty -r -t t chunk; then buf+=$chunk; else zselect -t 5; fi
  zpty -t t || break
done
zpty -d t 2>/dev/null
print -r -- "${buf//$'\r'}"
