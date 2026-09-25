-- The key help overlay: a card over the float, closed by any key.
local canvas = require("loom.canvas")
local config = require("loom.config")
local ui = require("loom.ui")

local M = {}

M.GROUPS = {
  {
    "Tabs",
    {
      { "c", "new tab" },
      { "n  p", "next / previous" },
      { "1-9", "go to tab" },
      { ",", "rename" },
      { "&", "close tab" },
    },
  },
  {
    "Panes",
    {
      { "_  %", "split side by side" },
      { '-  "', "split top / bottom" },
      { "h j k l", "move" },
      { "H J K L", "resize" },
      { "o", "next pane" },
      { "z", "zoom" },
      { "x", "close pane" },
      { "R", "restart" },
    },
  },
  {
    "Session",
    {
      { "s", "pick session" },
      { "S", "new session" },
      { "[", "scroll mode" },
      { "d  q", "hide" },
      { "?", "this help" },
    },
  },
}

function M.open()
  local prefix = ui.prefix_label()
  local col_w, key_w = 30, 9
  local width = col_w * #M.GROUPS + 2
  local rows = 0
  for _, g in ipairs(M.GROUPS) do
    rows = math.max(rows, #g[2])
  end
  local height = rows + 4
  local cv = canvas.new(width, height, "LoomNormal")
  for gi, g in ipairs(M.GROUPS) do
    local x = 2 + (gi - 1) * col_w
    cv:put(1, x, g[1], "LoomTitle")
    for i, item in ipairs(g[2]) do
      cv:put(2 + i, x, item[1], "LoomFooterKey")
      cv:put(2 + i, x + key_w, item[2], "LoomFooter")
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  cv:flush(buf, ui.ns)
  local g = ui.geom or ui.geometry()
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = g.row + math.max(1, math.floor((g.height - height) / 2)),
    col = g.col + math.max(1, math.floor((g.width - width) / 2)),
    width = width,
    height = height,
    style = "minimal",
    border = config.options.border,
    title = { { " keys after " .. prefix .. " ", "LoomTitle" } },
    title_pos = "center",
    footer = { { " any key closes ", "LoomFooter" } },
    footer_pos = "center",
    zindex = 60,
    focusable = false,
    noautocmd = true,
  })
  vim.wo[win].winhighlight = "Normal:LoomNormal,FloatBorder:LoomSepActive,FloatTitle:LoomTitle,FloatFooter:LoomFooter"
  vim.cmd("redraw")
  pcall(vim.fn.getcharstr)
  pcall(vim.api.nvim_win_close, win, true)
  if ui.session and ui.visible then
    ui.render(ui.session, { focus = true })
  end
end

return M
