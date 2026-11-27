# setlist: type queued commands at your zsh prompt, one keypress at a time.
# https://github.com/Akshay-Dongare/setlist (MIT)
#   Ctrl-N  Ctrl-P    type the next or previous command; with an empty queue, what they did before
#   Ctrl-Q            queue the line, or the clipboard when the line is empty
#   setlist <file>    replace the queue with a file's commands    setlist ./off   load a file named "off"
#   setlist           position and next      setlist reset   back to the start
#   setlist add       queue standard input   setlist off     empty the queue

# One queue for every shell, so a command queued from another app is next in all of them.
: ${SETLIST_QUEUE:=${XDG_STATE_HOME:-$HOME/.local/state}/setlist/queue}

zmodload -F zsh/stat b:zstat

typeset -ga SETLIST_LIST
typeset -gi SETLIST_I SETLIST_INODE SETLIST_SIZE
# "keymap:widget" -> the bindkey -L line the key had before setlist, and the key setlist bound
typeset -gA _setlist_saved _setlist_bound

# The file -> SETLIST_LIST; entries end in NUL. A replaced or shrunk file restarts this shell's
# position, an appended one keeps it.
_setlist_load() {
  emulate -L zsh
  local -A st
  SETLIST_LIST=()
  st=(inode 0 size 0)
  if [[ -f $SETLIST_QUEUE ]]; then
    zstat -H st -- $SETLIST_QUEUE 2>/dev/null
    SETLIST_LIST=("${(@0)$(<$SETLIST_QUEUE)}")
    SETLIST_LIST=("${(@)SETLIST_LIST:#}")
  fi
  (( st[inode] == SETLIST_INODE && st[size] >= SETLIST_SIZE )) || SETLIST_I=0
  SETLIST_INODE=st[inode] SETLIST_SIZE=st[size]
  (( SETLIST_I > ${#SETLIST_LIST} )) && SETLIST_I=${#SETLIST_LIST}
  return 0
}

# A queue can hold tokens typed into commands, so a new directory is 700 and a new file 600. An
# existing directory keeps its mode; the umask changes only in a subshell.
_setlist_append() { # entries -> added to the end of the file
  emulate -L zsh
  mkdir -p -m 700 -- ${SETLIST_QUEUE:h} || return 1
  ( umask 077 && print -rn -- "${(pj:\0:)@}"$'\0' >> $SETLIST_QUEUE )
}

_setlist_store() { # entries -> the file, replaced in one rename
  emulate -L zsh
  mkdir -p -m 700 -- ${SETLIST_QUEUE:h} || return 1
  ( umask 077 && print -rn -- "${(pj:\0:)@}"$'\0' > $SETLIST_QUEUE.$$ ) &&
    mv -f -- $SETLIST_QUEUE.$$ $SETLIST_QUEUE
}

# stdin to $reply: one command per line, verbatim bar a trailing CR, no blanks or # comments
_setlist_read() {
  emulate -L zsh
  local line rest
  reply=()
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    rest=${line#"${line%%[![:space:]]*}"}
    [[ -z $rest || $rest == '#'* ]] && continue
    reply+=("$line")
  done
}

# With an empty queue a key does what it did before setlist: run a widget, type a bindkey -s
# string, or nothing. $1 is the widget; the saved line is the one for the keymap in use.
_setlist_pass() {
  emulate -L zsh
  local -a t
  local -i s=0
  local map=${KEYMAP:-main}
  [[ $map == main ]] && map=${${(z)"$(bindkey -lL main)"}[3]}
  t=("${(@Q)${(z)_setlist_saved[$map:$1]}}")
  shift t
  while [[ ${t[1]} == -* ]]; do
    case ${t[1]} in (-s) s=1 ;; (-M) shift t ;; esac
    shift t
  done
  if (( s )); then zle -U "${t[2]}"
  elif [[ -n ${t[2]} && ${t[2]} != undefined-key ]]; then zle "${t[2]}"
  else return 1; fi
}

# Replace the line with the next or previous command; at either end stay put and say so.
setlist-next() {
  emulate -L zsh
  local edge=
  _setlist_load
  (( ${#SETLIST_LIST} )) || { _setlist_pass setlist-next; return }
  if (( SETLIST_I < ${#SETLIST_LIST} )); then (( ++SETLIST_I )); else edge=', end of queue'; fi
  BUFFER=${SETLIST_LIST[SETLIST_I]}; CURSOR=${#BUFFER}
  zle && zle -M "setlist $SETLIST_I/${#SETLIST_LIST}$edge"
  return 0
}
setlist-prev() {
  emulate -L zsh
  local edge=
  _setlist_load
  (( ${#SETLIST_LIST} )) || { _setlist_pass setlist-prev; return }
  if (( SETLIST_I > 1 )); then (( --SETLIST_I )); else edge=', start of queue'; fi
  BUFFER=${SETLIST_LIST[SETLIST_I]}; CURSOR=${#BUFFER}
  zle && zle -M "setlist $SETLIST_I/${#SETLIST_LIST}$edge"
  return 0
}

# The command that prints the clipboard, in $reply: $SETLIST_PASTE, else the first tool this
# desktop has. Fails when there is none.
_setlist_clipboard() {
  emulate -L zsh
  if [[ -n $SETLIST_PASTE ]]; then reply=(eval "$SETLIST_PASTE")
  elif (( $+commands[pbpaste] )); then reply=(pbpaste)
  elif [[ -n $WAYLAND_DISPLAY ]] && (( $+commands[wl-paste] )); then reply=(wl-paste --no-newline)
  elif [[ -n $DISPLAY ]] && (( $+commands[xclip] )); then reply=(xclip -selection clipboard -out)
  elif [[ -n $DISPLAY ]] && (( $+commands[xsel] )); then reply=(xsel --clipboard --output)
  elif (( $+commands[powershell.exe] )); then reply=(powershell.exe -NoProfile -Command Get-Clipboard)
  else reply=(); return 1; fi
}

setlist-add() {
  emulate -L zsh
  local -a reply
  if [[ -n $PREBUFFER ]]; then
    zle && zle -M "setlist: finish or cancel the multi-line command first"
    return 1
  elif [[ $BUFFER == *[![:space:]]* ]]; then
    reply=("$BUFFER")
  elif _setlist_clipboard; then
    _setlist_read <<< "$("${reply[@]}" 2>/dev/null)"
  else
    zle && zle -M "setlist: no clipboard tool found; install wl-clipboard (Wayland), xclip or xsel (X11), or set SETLIST_PASTE to a command that prints the clipboard"
    return 1
  fi
  if (( ! ${#reply} )); then
    zle && zle -M "setlist: nothing to queue"
    return 1
  fi
  _setlist_append "${reply[@]}" || return 1
  BUFFER=
  _setlist_load
  zle && zle -M "setlist: queued ${#reply}, now $SETLIST_I/${#SETLIST_LIST}"
  return 0
}

# Bind each action's key in each keymap, saving what the key did before. The first save wins, so
# re-sourcing never records setlist's own widgets as the ones to fall through to. A key moved by
# a later source gets its old binding back. Succeeds when Ctrl-Q or Ctrl-S is bound: the terminal
# swallows those keys as flow control unless the line editor turns it off.
_setlist_bind() {
  emulate -L zsh
  local m w key cur flow=
  local -a t maps
  local -A keys
  keys=(setlist-next "${SETLIST_KEY_NEXT-^N}" setlist-prev "${SETLIST_KEY_PREV-^P}"
        setlist-add "${SETLIST_KEY_ADD-^Q}")
  maps=(${(f)"$(bindkey -l)"})
  for m in ${=${SETLIST_KEYMAPS:-emacs viins vicmd}}; do
    if (( ! ${maps[(Ie)$m]} )); then
      print -u2 -r -- "setlist: no keymap '$m' to bind in; remove it from SETLIST_KEYMAPS or create it first with bindkey -N"
      continue
    fi
    for w in setlist-next setlist-prev setlist-add; do
      key=${keys[$w]}
      if [[ -n ${_setlist_bound[$m:$w]} && ${_setlist_bound[$m:$w]} != $key ]]; then
        eval "${_setlist_saved[$m:$w]}"
        unset "_setlist_saved[$m:$w]" "_setlist_bound[$m:$w]"
      fi
      [[ -n $key ]] || continue
      cur=$(bindkey -L -M $m -- $key)
      [[ $cur == *" $w" ]] || _setlist_saved[$m:$w]=$cur
      bindkey -M $m -- $key $w
      _setlist_bound[$m:$w]=$key
      t=("${(@Q)${(z)"$(bindkey -L -M $m -- $key)"}}")
      [[ ${t[-2]} == '^'[QS]* ]] && flow=off
    done
  done
  [[ -n $flow ]]
}

zle -N setlist-next
zle -N setlist-prev
zle -N setlist-add
[[ -o zle && -z ${SETLIST_NO_BIND-} ]] && _setlist_bind && unsetopt flowcontrol

setlist() {
  emulate -L zsh
  local -a reply
  case ${1-} in
    '')
      _setlist_load
      if (( ${#SETLIST_LIST} )); then
        print -r -- "setlist: $SETLIST_I/${#SETLIST_LIST}"
        if (( SETLIST_I < ${#SETLIST_LIST} )); then
          print -r -- "next: ${SETLIST_LIST[SETLIST_I+1]}"
        else
          print -r -- "next: (end of queue)"
        fi
      else
        print -r -- "setlist: queue is empty"
      fi ;;
    reset)
      _setlist_load
      (( ${#SETLIST_LIST} )) || { print -u2 -r -- "setlist: queue is empty"; return 1 }
      SETLIST_I=0 ;;
    off)
      rm -f -- $SETLIST_QUEUE
      _setlist_load ;;
    add)
      _setlist_read
      (( ${#reply} )) || { print -u2 -r -- "setlist: nothing to queue"; return 1 }
      _setlist_append "${reply[@]}" || return 1
      _setlist_load
      print -r -- "setlist: queued ${#reply}, now $SETLIST_I/${#SETLIST_LIST}" ;;
    *)
      local file=$1
      [[ -r $file && ! -d $file ]] || { print -u2 -r -- "setlist: cannot read $file"; return 1 }
      _setlist_read < "$file"
      (( ${#reply} )) || { print -u2 -r -- "setlist: no commands in $file"; return 1 }
      _setlist_store "${reply[@]}" || return 1
      _setlist_load ;;
  esac
}
