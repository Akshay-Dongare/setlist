# setlist

Type queued commands at your own zsh prompt, one keypress at a time. For live demos, screencasts
and walkthroughs: Ctrl-N puts the next command on the line, and you press Enter. Nothing runs by
itself.

```
$ cat demo.txt
# build and run the image
docker build -t demo .
docker run --rm -v "$PWD":/app demo ls /app

# clean up
docker image rm demo

$ setlist demo.txt
$ setlist
setlist: 0/3
next: docker build -t demo .
```

Press Ctrl-N and the prompt reads `docker build -t demo .`, with `setlist 1/3` below it. Press
Enter to run it. Run anything else you like in between: the next Ctrl-N carries on where the
queue left off.

## Why

During a demo you want each command exactly as written, but typed into your real shell, with
your aliases, completion, history and prompt, and with room to answer a question and come back.
Typing live invites typos, and pasting from notes means switching windows. Tools that replay a
script run it in a session of their own. setlist only fills the line you are already on.

The queue is one file shared by every terminal, and you can fill it three ways:

- `setlist demo.txt` replaces it with a file's commands.
- Ctrl-Q queues the line you have typed, or the clipboard when the line is empty.
- On macOS, the **Add to setlist** Quick Action queues the text selected in any app (a browser, a
  PDF, your notes) with one keyboard shortcut. On Linux, a desktop hotkey does the same with the
  selected text.

## Install

setlist runs on macOS and Linux and is tested on zsh 4.3.11 through 5.9. Pick one:

**Plain `source`.** Clone it anywhere, then add the `source` line to `~/.zshrc`:

```zsh
git clone https://github.com/Akshay-Dongare/setlist ~/.local/share/setlist
source ~/.local/share/setlist/setlist.plugin.zsh
```

To pin a release, add `--branch v0.1.0` to the clone.

**oh-my-zsh.** Clone it into your custom plugins, then add `setlist` to `plugins=(...)` in
`~/.zshrc`:

```zsh
git clone https://github.com/Akshay-Dongare/setlist ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/setlist
```

**antidote.** Add this line to `~/.zsh_plugins.txt`:

```
Akshay-Dongare/setlist
```

**zinit.** Add this line to `~/.zshrc`:

```zsh
zinit light Akshay-Dongare/setlist
```

**sheldon.** Run `sheldon add setlist --github Akshay-Dongare/setlist`.

Then open a new terminal. For the macOS Quick Action, also run `./install.sh` in the checkout;
see [Queue from any app](#queue-from-any-app).

## Commands

```
setlist demo.txt   replace the queue with a file's commands
setlist            show the position and the next command
setlist reset      go back to the start
setlist add        queue standard input, e.g. pbpaste | setlist add
setlist off        empty the queue
```

To load a file named `reset`, `off` or `add`, give a path: `setlist ./off`. A missing file, an
unreadable one, or one with no commands fails with a message and leaves the queue as it was; so do
Ctrl-Q and `setlist add` with nothing to queue.

## Keys

**Ctrl-N and Ctrl-P** replace the line with the next or the previous command, put the cursor at
the end, and show the position below the prompt: `setlist 3/8`. They never run anything. Ctrl-N
stops at the last command and Ctrl-P at the first, and pressing either again there says so:
`setlist 8/8, end of queue`. Before the first Ctrl-N the position is 0, so Ctrl-P there clears the
line.

**Ctrl-Q** queues the whole line, verbatim, and clears it. That includes a multi-line command and
a line that starts with `#`. Type the command, or bring it back with the arrow keys or Ctrl-R
first. On an empty line Ctrl-Q queues the clipboard instead, one command per line. Below the
prompt it shows how many commands it queued and the new position, e.g.
`setlist: queued 3, now 0/3`. At a continuation prompt such as `for>` it refuses: finish or
cancel the command first.

**With an empty queue** Ctrl-N and Ctrl-P do what they did before setlist loaded: run the widget
they replaced, type a `bindkey -s` string, or nothing. So outside a demo they are still history
down and up. They stay bound while the queue is empty because the Quick Action can fill it while
a prompt is already waiting, and zsh cannot rebind a key during a prompt.

**Keymaps.** The keys are bound in the `emacs`, `viins` and `vicmd` keymaps, so they work whether
you run `bindkey -e` or `bindkey -v`, before or after setlist loads. In vi command mode Ctrl-N
types the next command just as in insert mode. Each keymap falls back to its own old binding.

**Flow control.** A terminal normally takes Ctrl-Q and Ctrl-S for flow control, so zsh never
sees them. When setlist binds either key, it runs `unsetopt flowcontrol`, which turns flow control
off while you edit a command line only. Programs you run keep it. If you move every setlist key
away from Ctrl-Q and Ctrl-S, flow control stays as it was.

## File format

One command per line. Lines are kept verbatim, indentation and quoting included; only a trailing
carriage return is dropped, so files saved on Windows work. Nothing is expanded at load time:
`$PWD` stays literal until you press Enter. Blank lines and lines whose first non-blank character
is `#` are skipped. A file does not have to be UTF-8.

## One queue for every terminal

The queue is the file `$XDG_STATE_HOME/setlist/queue`, or `~/.local/state/setlist/queue` when
`XDG_STATE_HOME` is unset, so whatever you queue is there in every terminal. Each command ends in
a NUL byte, so a multi-line command stays whole. A queue can hold tokens you typed into commands,
so setlist creates its directory with mode 700 and the file with mode 600.

Each shell keeps its own position. Queuing more never moves it, so anything added after the end
comes next. Replacing the file or making it shorter starts every shell from the top again.

## Configuration

Set these before setlist loads, e.g. above the `source` line or the plugin manager line:

```zsh
SETLIST_QUEUE=~/demo/queue      # the queue file
SETLIST_KEY_NEXT='^N'           # each key in bindkey notation; '' leaves the action unbound
SETLIST_KEY_PREV='^P'
SETLIST_KEY_ADD='^Q'
SETLIST_KEYMAPS=(emacs viins vicmd)   # the keymaps to bind in
SETLIST_NO_BIND=1               # define the widgets but bind no keys
SETLIST_PASTE='tmux save-buffer -'    # a command that prints the clipboard
```

Set `SETLIST_QUEUE` in `~/.zshenv`, not `~/.zshrc`, so the Quick Action and the Linux hotkey use
the same file as your terminals.

With `SETLIST_NO_BIND`, bind the three widgets yourself:

```zsh
bindkey '^[n' setlist-next
bindkey '^[p' setlist-prev
bindkey '^[q' setlist-add
```

Keys you bind yourself have no old binding to fall back to, so with an empty queue they do
nothing.

**The clipboard.** Ctrl-Q on an empty line reads the clipboard with the first of these it finds:
`$SETLIST_PASTE`, `pbpaste` (macOS), `wl-paste` (Wayland), `xclip` or `xsel` (X11), and
`powershell.exe` (WSL). Without any of them it says what to install.

## Queue from any app

**macOS.** `./install.sh`, run in the setlist checkout, puts the **Add to setlist** Quick Action
in `~/Library/Services`. Select commands in any app and choose Services > Add to setlist from the
app's menu or the right-click menu: the selection goes into the queue, one command per line, and
a notification says how many commands it queued. The clipboard is not touched.

macOS keeps Quick Action shortcuts in its own settings, so set one by hand: System Settings >
Keyboard > Keyboard Shortcuts > Services > Text > Add to setlist. Choose a combination no app
uses, such as Ctrl-Option-Cmd-Q.

The Quick Action records the checkout's full path, because Automator runs it without your shell
setup. If you move the checkout, or your plugin manager does, run `./install.sh` again.
`./install.sh --dry-run` shows what it would change, and `./uninstall.sh` removes it. The checkout
is wherever you cloned it, or:

```zsh
cd ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/setlist   # oh-my-zsh
cd $(antidote path Akshay-Dongare/setlist)              # antidote
cd ${ZINIT[PLUGINS_DIR]}/Akshay-Dongare---setlist       # zinit
```

**Linux.** `bin/add-to-setlist --selection` queues the primary selection, which is the text you
last highlighted, and shows the result with `notify-send`. It reads the selection with `wl-paste`
on Wayland, or `xclip` or `xsel` on X11. Bind it to a key in your desktop's keyboard settings, as
a custom shortcut that runs a command. `./install.sh` on Linux installs nothing and prints the
full command to bind. In a sway or i3 config:

```
bindsym $mod+Ctrl+q exec ~/.local/share/setlist/bin/add-to-setlist --selection
```

`add-to-setlist` with no argument queues its standard input, as `setlist add` does. Set
`SETLIST_QUIET=1` to skip the notification.

## Limitations

- It works only in zsh, at an interactive prompt. Inside `ssh`, a REPL or any other program the
  keys do nothing, unless setlist is installed on that host too.
- A plugin that resets keymaps after setlist loads removes its keys. Load setlist after it.
- A widget that tracks its own previous press, such as `history-search-backward`, starts its
  search over on each press when Ctrl-N or Ctrl-P reaches it through setlist.
- Ctrl-Q replaces `push-line` in emacs mode, which is still on Esc-q, and `vi-quoted-insert` in
  vi insert mode, which is still on Ctrl-V.
- On WSL, text selected in Windows apps never reaches the Linux primary selection, so use Ctrl-Q
  with the clipboard there.

## Similar tools

Bart Schaefer described the same mechanism on zsh-workers in April 2014: a widget that sets
`$BUFFER` from an array, bound to a key, so you can go off-script and resume the demo
([the post](https://www.zsh.org/mla/workers/2014/msg00356.html)). It was never packaged, and
setlist was built independently of it.

[doitlive](https://github.com/sloria/doitlive) reads a file of commands and replays them in a
fake terminal session as you type random characters. [demo-magic](https://github.com/paxtonhare/demo-magic)
is a bash script whose `pe` function simulates typing each command and runs it when you press
Enter. [TypeCue](https://github.com/alexpolonsky/TypeCue) is a macOS menu bar app that types each
block of a prepared script into any app as real keystrokes, one block per hotkey press.

setlist works inside zsh's own line editor. The command appears at your real prompt, with no
session or runner of its own and no simulated keystrokes, so it needs no accessibility permission.
You can go off-script, step back and resume at any point, queue commands from any app, and use one
queue in every terminal.

## Development

```
make check   # parse the zsh files, lint the installers, validate the Quick Action
make test    # run the bats suite
```

The tests need [bats-core](https://github.com/bats-core/bats-core) 1.5 or later, and
[ShellCheck](https://www.shellcheck.net) for `make check`. Key bindings are tested with real
keypresses in a pseudo-terminal. No test reads your real clipboard or queue, or writes to your
`~/Library/Services`.

## License

MIT. See [LICENSE](LICENSE).
