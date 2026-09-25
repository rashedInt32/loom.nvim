-- Keys inside loom terminals: the prefix, then one action key.
local config = require("loom.config")

local M = {}

local function loom()
  return require("loom")
end

--- Action keys after the prefix. Values take no arguments.
M.actions = {
  c = function()
    loom().new_tab()
  end,
  n = function()
    loom().cycle_tab(1)
  end,
  p = function()
    loom().cycle_tab(-1)
  end,
  [","] = function()
    loom().rename()
  end,
  ["&"] = function()
    loom().close_tab()
  end,
  -- tmux's defaults, plus the common - and _ remaps: - stacks, _ goes side by side.
  ["%"] = function()
    loom().split("vertical")
  end,
  ["_"] = function()
    loom().split("vertical")
  end,
  ['"'] = function()
    loom().split("horizontal")
  end,
  ["-"] = function()
    loom().split("horizontal")
  end,
  o = function()
    loom().next_pane()
  end,
  z = function()
    loom().zoom()
  end,
  x = function()
    loom().close_pane()
  end,
  R = function()
    loom().restart()
  end,
  s = function()
    loom().pick_session()
  end,
  S = function()
    loom().new_session()
  end,
  ["["] = function()
    loom().scroll_mode()
  end,
  d = function()
    loom().hide()
  end,
  q = function()
    loom().hide()
  end,
  ["?"] = function()
    loom().help()
  end,
}

for _, d in ipairs({ "h", "j", "k", "l" }) do
  M.actions[d] = function()
    loom().move(d)
  end
  M.actions[d:upper()] = function()
    loom().resize(d)
  end
end
local arrows = { ["<Left>"] = "h", ["<Down>"] = "j", ["<Up>"] = "k", ["<Right>"] = "l" }
for i = 1, 9 do
  M.actions[tostring(i)] = function()
    loom().goto_tab(i)
  end
end

--- Resolve a key read by getcharstr() to an action, or nil.
function M.action_for(key)
  if M.actions[key] then
    return M.actions[key]
  end
  for name, d in pairs(arrows) do
    if key == vim.keycode(name) then
      return M.actions[d]
    end
  end
end

--- Arm the prefix, read one key, run its action.
function M.prefix()
  local ui = require("loom.ui")
  local was_terminal = vim.api.nvim_get_mode().mode == "t"
  ui.armed = true
  if ui.session then
    ui.render(ui.session)
  end
  vim.cmd("redraw")
  local ok, key = pcall(vim.fn.getcharstr)
  ui.armed = false
  if not ok or key == vim.keycode("<Esc>") then
    if ui.session and ui.visible then
      ui.render(ui.session, { focus = true, insert = was_terminal })
    end
    return
  end
  if key == vim.keycode(config.options.prefix) then
    -- Prefix twice sends it to the program, like tmux.
    local id = ui.current_pane()
    local t = id and require("loom.term").get(id)
    if t then
      vim.fn.chansend(t.job, key)
    end
    ui.render(ui.session, { focus = true, insert = was_terminal })
    return
  end
  local fn = M.action_for(key)
  if fn then
    fn()
  elseif ui.session and ui.visible then
    ui.render(ui.session, { focus = true, insert = was_terminal })
  end
end

local function open_file_under_cursor()
  local file = vim.fn.expand("<cfile>")
  local line = tonumber(vim.fn.expand("<cWORD>"):match(":(%d+)"))
  local found = file ~= "" and vim.fn.findfile(file, "**") or ""
  if found == "" and vim.fn.filereadable(file) == 1 then
    found = file
  end
  if found == "" then
    vim.notify("loom: no file under cursor", vim.log.levels.WARN)
    return
  end
  loom().hide()
  vim.schedule(function()
    vim.cmd.edit(vim.fn.fnameescape(found))
    if line then
      pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
    end
  end)
end

--- Buffer-local keys for one loom terminal buffer.
function M.attach(buf)
  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set(
    { "t", "n" },
    config.options.prefix,
    M.prefix,
    vim.tbl_extend("force", opts, { desc = "loom: prefix" })
  )
  -- Scroll mode is Neovim normal mode in the terminal buffer.
  vim.keymap.set("n", "q", function()
    loom().hide()
  end, vim.tbl_extend("force", opts, { desc = "loom: hide" }))
  vim.keymap.set("n", "gf", open_file_under_cursor, vim.tbl_extend("force", opts, { desc = "loom: open file" }))
end

return M
