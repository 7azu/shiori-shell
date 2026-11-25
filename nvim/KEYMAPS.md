# Keymaps: nvim, tmux, keyboard

Main file: `~/.config/nvim/KEYMAPS.md` (in nvim: `Space ?`).

Notation:
- `Space ff` means press Space, f, f one after another.
- `Prefix` is the tmux prefix `Ctrl+Space`. Release it, then press the next key.
- Wait a moment after `Space`: which-key shows all possibilities.
- Forgot one? `Space fk` searches all keymaps (e.g. type "comment").

## Keyboard (global)

| Key             | Result            |
| --------------- | ----------------- |
| `CapsLock`      | Esc               |

On a German layout, brackets are on `AltGr` (`AltGr+s` / `d` = `[` / `]`, `AltGr+f` / `g` = `{` / `}`),
`/` is `Shift+7` and `:` is `Shift+.`.

## Windows and panes (nvim and tmux together)

| Key                   | What                                                         |
| --------------------- | ------------------------------------------------------------ |
| `Ctrl+h/j/k/l`        | To the window left/down/up/right, whether nvim or tmux       |
| `Alt+Shift+h/j/k/l`   | Move the tmux separator line                                 |
| `Prefix z`            | Pane full screen and back (zoom)                             |
| `Prefix v` / `s`      | Split the tmux pane side by side / on top of each other      |
| `Prefix x`            | Close the tmux pane (confirm with `y`)                       |
| `Prefix Ctrl+l`       | Clear the screen (in zsh/Claude, since `Ctrl+l` jumps)       |
| `Prefix c` / `n` / `p`| tmux window: new / next / previous                           |
| `Prefix w`            | Overview of all tmux windows                                 |
| `Prefix r`            | Reload the tmux config                                       |
| `Prefix d`            | Detach from tmux, it keeps running in the background         |

Project layout (only with the setting `folders.projects` and the `claude` CLI): when you open a file from
`<projects folder>/projects/<name>/` in nvim (or a folder with `Cargo.toml` etc. inside the projects folder), Claude and
a terminal in the project folder open on the right automatically.

### tmux copy mode (copy text from the terminal/Claude)

| Key              | What                                 |
| ---------------- | ------------------------------------ |
| `Prefix [`       | Start copy mode                      |
| `h/j/k/l`, `/`   | Move, search (as in vim)             |
| `Space`          | Start the selection                  |
| `v`              | Toggle block selection               |
| `Enter`          | Copy and leave copy mode             |
| `q`              | Cancel                               |

## Files and search

| Key         | What                                                |
| ----------- | --------------------------------------------------- |
| `Space ff`  | Files (nvim's current folder)                       |
| `Space f.`  | Files in the current file's folder                  |
| `Space fp`  | Files in the projects folder (`folders.projects`)   |
| `Space fr`  | Recently opened                                     |
| `Space fg`  | Search text in all files                            |
| `Space fb`  | Open buffers                                        |
| `Space fo`  | Functions/symbols of the file                       |
| `Space fd`  | All errors and warnings                             |
| `Space fk`  | Search keymaps                                      |
| `Space fh`  | Search nvim help                                    |
| `Space oc`  | Config: `~/.config` (everything)                    |
| `Space oh`  | Config: Hypr modules                                |
| `Space os`  | Config: Hypr scripts                                |
| `Space oq`  | Config: Quickshell                                  |
| `Space on`  | Config: nvim                                        |
| `Space e`   | Yazi (file explorer), `F1` in it = help             |
| `Space bd`  | Close buffer                                        |
| `]b` / `[b` | Next / previous buffer                              |

In the Telescope search:

| Key              | What                                                |
| ---------------- | --------------------------------------------------- |
| `Ctrl+j` / `k`   | Down / up                                           |
| `Enter`          | Open                                                |
| `Ctrl+v` / `x`   | Open in a split side by side / on top of each other |
| `Ctrl+u` / `d`   | Scroll the preview                                  |
| `Ctrl+c`         | Close (or `Esc` twice)                              |

## Jumping in code

| Key             | What                                                      |
| --------------- | --------------------------------------------------------- |
| `sl`            | Jump (Flash): type 1-2 characters, then the label letter  |
| `f`/`t` + char  | To the character in the line, `;` / `,` repeats           |
| `gd`            | Go to definition                                          |
| `grr`           | All references                                            |
| `gri`           | Go to implementation                                      |
| `grt`           | Go to type definition                                     |
| `gO`            | Outline of the file (functions etc.)                      |
| `Ctrl+o` / `Ctrl+i` | Back / forward (after a jump)                         |
| `%`             | To the matching bracket                                   |

## Errors, help for the code (LSP)

| Key            | What                                                 |
| -------------- | ---------------------------------------------------- |
| `K`            | Docs for the symbol under the cursor (`K` twice: into it) |
| `]d` / `[d`    | Next / previous error                                |
| `Ctrl+w d`     | Show the full error message under the cursor         |
| `gra`          | Code action (quick fix, e.g. add an import)          |
| `grn`          | Rename (everywhere)                                  |
| `Space th`     | Toggle inlay hints (gray types in the code)          |

## Completion (insert mode)

| Key               | What                                           |
| ----------------- | ---------------------------------------------- |
| `Tab`             | Accept the suggestion                          |
| `Ctrl+n` / `p`    | Open the menu, or next / previous              |
| `Ctrl+e`          | Close the menu                                 |
| `Ctrl+b` / `f`    | Scroll the docs of the suggestion              |
| `Ctrl+k`          | Toggle parameter help                          |

## Editing code

| Key              | What                                                      |
| ---------------- | --------------------------------------------------------- |
| `gcc`            | Comment the line out / back in                            |
| `gc` + motion    | Comment out, e.g. `gcip` (paragraph), in visual mode: `gc` |
| `Space m`        | Toggle a block single-/multi-line (e.g. list, parameters) |
| `Space cf`       | Format code (happens automatically on save)               |
| `[Space` / `]Space` | Empty line above / below the cursor                    |
| `v` then `an` / `in` | Grow / shrink the selection around a code block       |

### Surround (mini.surround)

| Key         | What                                                         |
| ----------- | ------------------------------------------------------------ |
| `sa` + motion + char | Surround, e.g. `saiw"` = put the word in `"`         |
| visual `sa` + char   | Surround the selection                               |
| `sd` + char | Delete, e.g. `sd(` or `sdq` (nearest quotes)                 |
| `sr` + old + new | Replace, e.g. `sr"'` (double by single quotes)          |
| `sdb` / `srb` | Delete / replace the nearest bracket (saves `AltGr` on German layouts) |
| `sh`        | Highlight the surrounding briefly                            |

`(` adds brackets with spaces inside, `)` without. The same goes for `[ ]` and `{ }`.

## Running and debugging

| Key              | What                                                |
| ---------------- | --------------------------------------------------- |
| `Space r`        | Compile and run the file (at the bottom)            |
| `Esc` / `q`      | Close the run window (ends the program)             |
| `Esc Esc`        | Normal mode in nvim terminals                       |
| `Space db`       | Toggle breakpoint                                   |
| `F5`  / `Space dc` | Start / continue debugging                        |
| `F10` / `Space dn` | Next line                                         |
| `F11` / `Space di` | Step into                                         |
| `F12` / `Space do` | Step out                                          |
| `Space dr`       | Run to cursor                                       |
| `Space de`       | Show value under cursor                             |
| `Space dq`       | Stop debugging                                      |
| `Space td`       | Toggle debug windows                                |

## Toggles (`Space t`)

| Key         | What                                  |
| ----------- | ------------------------------------- |
| `Space th`  | Inlay hints                           |
| `Space tf`  | Format on save                        |
| `Space td`  | Debug windows                         |
