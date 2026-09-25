# loom.nvim spec

A floating terminal for Neovim that behaves like a small tmux. One toggle key
opens a float that holds many terminals, as tabs and split panes. A dev server
keeps running in one pane while you work in another. Nothing stops when the
float hides.

## Why

Today the float is one `Snacks.terminal`. When a server runs there, the only
shell is busy. The choices are to open another pane outside Neovim, or to stop
the server, run the command, and start the server again. Snacks can open a
second float, but moving between floats is awkward.

Existing plugins (nvzone/floaterm, dawsers/floaterm.nvim, vim-floaterm,
toggleterm) put a plain terminal over Neovim. None of them splits panes inside
the float, and none of them looks designed.

## Ideas taken from Superlogical

From the pre-alpha demo (youtube.com/watch?v=XyxShCZrGiw) and superlogical.com:

| Superlogical | loom |
| --- | --- |
| Opens in "less than half a bounce" | Toggle shows the float in one redraw. Terminals already exist, so nothing boots. |
| Feels like a normal terminal, no mode to learn | Typing goes straight to the shell. Only the prefix key is taken. |
| Terminals keep running when the client quits | Hiding the float never stops a process. Surviving a Neovim restart is phase 3. |
| Named sessions | One session per project root, plus named sessions on demand. |
| Native scrolling and selection | Neovim terminal scrollback, mouse wheel, visual selection, and a scroll position indicator. |
| Horizontal tabs, vertical as an option | A horizontal tab bar. A vertical tab rail is an option. |

## Look

- A centred float, 88% wide and 82% high by default, with a rounded border.
- The border title shows the session name. The border footer shows a short key
  hint that changes while the prefix is armed.
- A one-line tab bar at the top of the float. Each tab shows an icon for the
  running program, a name, a status dot, and a port badge when a server
  listens.
  - Status dot: running, finished with 0, failed with a non-zero code.
  - Activity: a tab that printed while you were elsewhere shows a marker.
- Panes are separated by thin lines, tmux style. The active pane's separators
  use the accent colour. Inactive panes are slightly dimmed.
- Every colour links to the current colour scheme, so it matches rose-pine
  and follows a scheme switch.

## Model

```
session  (name, root)
  └─ tabs[]  (name override, layout, active pane, zoomed?)
       └─ layout  binary tree of splits
            ├─ split  (vertical | horizontal, ratio, a, b)
            └─ leaf   (terminal id)
terminal (buf, job, cmd, cwd, status, exit_code, port, activity, program)
```

A session is keyed by name. The default session name is the basename of the
git root of Neovim's working directory, so every project and every worktree
gets its own.

## Keys

`<C-/>` and `<C-\>` toggle the float, as today.

Inside a loom terminal, `<C-b>` arms the prefix, then one key:

| Key | Action |
| --- | --- |
| `c` | new tab |
| `n` / `p` | next / previous tab |
| `1` to `9` | go to tab N |
| `,` | rename tab |
| `&` | close tab |
| `_` or `%` | split side by side |
| `-` or `"` | split top and bottom |
| `h` `j` `k` `l` or arrows | move to the pane in that direction |
| `o` | next pane |
| `H` `J` `K` `L` | resize the active pane |
| `z` | zoom the active pane to fill the float, again to restore |
| `x` | close the active pane |
| `R` | restart the active pane's command |
| `s` | pick a session |
| `S` | new named session |
| `[` | scroll mode: Neovim normal mode in the terminal |
| `d` or `q` | hide the float |
| `?` | key help overlay |
| `<C-b>` | send a literal `<C-b>` to the shell |

In scroll mode, `q` hides, `i` returns to typing, and `gf` opens the file
under the cursor in the editor, like the current snacks setup.

Mouse: clicking a tab switches to it. The wheel scrolls the pane under it.

## Behaviour

- Hiding closes the windows only. Buffers and jobs keep running.
- Focusing a window outside loom hides the float, like a popup. Option
  `hide_on_leave = false` keeps it open.
- Resizing Neovim re-lays out the float.
- A pane whose process exits stays in place and shows its exit code, so the
  output can be read. `R` restarts it. `x` closes it.
- Closing the last pane of a tab closes the tab. Closing the last tab hides the
  float. The next toggle opens a fresh shell.
- The program shown in a tab is the terminal's foreground process, polled only
  while the float is visible.
- Ports are detected from output such as `http://localhost:3000` or
  `port 5173`.

## API

```lua
require("loom").setup(opts)
require("loom").toggle()
require("loom").new_tab({ cmd = "pnpm dev", name = "dev" })
require("loom").split("vertical" | "horizontal", { cmd = ... })
require("loom").session(name)
```

## Options

```lua
{
  prefix = "<C-b>",
  toggle = { "<C-/>", "<C-\\>" },
  width = 0.88,
  height = 0.82,
  border = "rounded",
  tabs = "top",          -- "top" | "left"
  hide_on_leave = true,
  dim_inactive = true,
  shell = vim.o.shell,
  env = { NVIM_TERMINAL = "1" },
}
```

## Phases

1. **Core.** Float, tabs, split panes, prefix keys, status, ports, program
   icons, per-project sessions, help overlay, mouse tab clicks.
2. **Restore.** Save each session's tabs, layout, names, and commands to
   `stdpath("state")`. After a Neovim restart the layout comes back, and
   commands marked `autostart` run again.
3. **Durable processes.** Processes survive a Neovim restart. That needs a
   process outside Neovim, such as a hidden tmux socket or a small pty daemon.
   Its design is left until phases 1 and 2 are in daily use.

## Not in scope

- Remote hosts and session sharing. Superlogical's cross-machine features need
  a server, which is out of scope for an editor plugin.
- Jev. A later option may use it to label a pane's state, such as "ready",
  "compiling", or "crashed", from its last lines. Phase 1 uses exit codes and
  patterns only.

## Done when

- A server runs in one pane while commands run in another, in the same float.
- Hiding and showing the float never interrupts a process.
- Every key in the table works from terminal mode.
- The float matches the colour scheme and looks designed, checked on a real
  screen capture.
- Headless tests cover the layout tree, detection, state, and rendering.
