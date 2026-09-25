-- Options and their defaults.
local M = {}

M.defaults = {
  -- Arms the pane and tab keys. Bound only inside loom terminals.
  prefix = "<C-b>",
  -- Global keys that show or hide the float. Empty to bind your own.
  toggle = { "<C-/>", "<C-\\>" },
  -- Float size as a fraction of the editor, or whole cells when above 1.
  width = 0.88,
  height = 0.82,
  border = "rounded",
  -- Round "pill" ends on the active tab. Needs a Nerd Font.
  pills = true,
  -- Hide the float when focus moves to a window outside it.
  hide_on_leave = true,
  -- Give inactive panes a slightly darker background.
  dim_inactive = true,
  shell = nil, -- nil means vim.o.shell
  env = { NVIM_TERMINAL = "1" },
  -- How often to read each visible terminal's foreground program, in ms.
  poll_ms = 1200,
  -- Pill colours as "#rrggbb". nil derives each one from the colour scheme.
  colors = {
    active = nil, -- the active tab
    active_fg = nil, -- text on any filled pill
    inactive = nil, -- the other tabs
    inactive_fg = nil,
    session = nil, -- the session pill
    prefix = nil, -- the pill shown while the prefix waits for a key
    dim = nil, -- inactive pane background; unset on transparent schemes
  },
  -- Inside tmux, set the pane option @loom while a loom pane has focus, so a
  -- tmux binding can hand a shared prefix key (such as C-a) to loom.
  tmux = true,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
