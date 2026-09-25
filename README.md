# loom.nvim

A floating terminal for Neovim with tmux-style tabs and split panes.

## why loom exists

built on day four of the week, with 67% of the Claude limit left and ZERO
chill. your favourite movie is Inception, and a voice in your head says "we
need to go deeper." you already run neovim inside tmux. so why not tmux inside
neovim?

*"the circle is now complete."* *this is the way.*

There are great neovim terminals out there. but this is the AI era. your soul
is already corrupted, and you never settle for anything less.

*"Size matters not."* one small float holds EVERYTHING, and your dev server
keeps running while you work.

<!-- demo video goes here -->

Inspired by Superlogical's terminal multiplexer demo.

## Install

lazy.nvim:

```lua
{
  "rashedInt32/loom.nvim",
  lazy = false,
  opts = {},
}
```

Needs Neovim 0.11 or newer and a Nerd Font for the icons.

## Use

`<C-/>` or `<C-\>` shows and hides the float.

Inside a loom terminal, press `<C-b>`, then one key:

| Key | Action |
| --- | --- |
| `c` | new tab |
| `n` `p` | next, previous tab |
| `1`-`9` | go to tab |
| `,` | rename tab |
| `&` | close tab |
| `_` or `%` | split side by side |
| `-` or `"` | split top and bottom |
| `h` `j` `k` `l` | move between panes |
| `H` `J` `K` `L` | resize |
| `o` | next pane |
| `z` | zoom the pane |
| `x` | close the pane |
| `R` | restart the pane |
| `s` `S` | pick a session, new session |
| `[` | scroll mode |
| `d` `q` | hide |
| `?` | key help |

Press `<C-b>` twice to send it to the program. Click a tab to switch to it.

In scroll mode you are in Neovim normal mode in the terminal. `i` goes back to
typing, `q` hides, and `gf` opens the file under the cursor.

Each project gets its own session, named after its git root. A tab shows its
running program, a dot while it works or after it fails, and a port badge when
a server announces one.

## Commands

```
:Loom                 toggle
:Loom new [cmd]       new tab, optionally running cmd
:Loom vsplit [cmd]    split side by side
:Loom split [cmd]     split top and bottom
:Loom session [name]  pick or open a session
```

## Options

```lua
{
  prefix = "<C-b>",
  toggle = { "<C-/>", "<C-\\>" },
  width = 0.88,        -- fraction of the editor, or cells above 1
  height = 0.82,
  border = "rounded",
  pills = true,        -- rounded active tab, needs a Nerd Font
  hide_on_leave = true,
  dim_inactive = true,
  shell = nil,         -- defaults to 'shell'
  env = { NVIM_TERMINAL = "1" },
  poll_ms = 1200,      -- how often to read each visible pane's program
  colors = {           -- "#rrggbb"; unset ones come from the colour scheme
    active = nil, active_fg = nil, inactive = nil, inactive_fg = nil,
    session = nil, prefix = nil, dim = nil,
  },
  tmux = true,         -- set the pane option @loom while a loom pane has focus
}
```

Colours follow your colour scheme, and a transparent scheme stays transparent.

## Sharing the tmux prefix

To use tmux's prefix, such as `C-a`, for loom too, set `prefix = "<C-a>"` and
add this to `tmux.conf`. tmux then hands `C-a` to loom while a loom pane has
focus:

```tmux
unbind C-b
set -g prefix None
bind -n C-a if -F '#{&&:#{@loom},#{==:#{pane_current_command},nvim}}' 'send-keys C-a' 'switch-client -T prefix'
bind C-a send-keys C-a
```

Everywhere else `C-a` stays the tmux prefix.

## Tests

```
make test
```
