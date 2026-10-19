-- The float: one frame window for the border, tab bar and separators, and one
-- window per visible pane on top of it. Hiding closes windows only.
local config = require("loom.config")
local canvas = require("loom.canvas")
local detect = require("loom.detect")
local G = require("loom.glyphs")
local layout = require("loom.layout")
local state = require("loom.state")
local term = require("loom.term")

local M = {}

M.ns = vim.api.nvim_create_namespace("loom")
M.visible = false
M.frame = { win = nil, buf = nil }
M.panes = {} -- term id -> window
M.armed = false -- prefix pressed, waiting for its key
M.tab_hits = {} -- { col_start, col_end, index } for mouse clicks
M.geom = nil

local Z = 50

local function size(v, total)
  if v <= 1 then
    return math.floor(total * v)
  end
  return math.min(math.floor(v), total)
end

--- Float position and the pane area inside it, in editor cells.
function M.geometry()
  local cols = vim.o.columns
  local lines = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)
  local w = math.max(20, math.min(size(config.options.width, cols), cols - 2))
  local h = math.max(6, math.min(size(config.options.height, lines), lines - 2))
  local g = {
    row = math.max(0, math.floor((lines - h - 2) / 2)),
    col = math.max(0, math.floor((cols - w - 2) / 2)),
    width = w,
    height = h,
  }
  -- Row 0 is the tab bar, row 1 a thin rule under it, then panes with a
  -- one-cell side margin. The rule, not the shell's prompt, keeps panes off
  -- the tabs: a prompt's leading blank line scrolls away when a pane resizes.
  g.box = { row = 2, col = 1, width = w - 2, height = h - 2 }
  return g
end

-- ── Tab bar ────────────────────────────────────────────────────────────────

--- Summarise a tab's panes: worst status, a running program, activity, a port.
function M.tab_info(tab)
  local info = { status = "idle", activity = false, port = nil, program = nil }
  for _, id in ipairs(layout.leaves(tab.layout)) do
    local t = term.get(id)
    if t then
      local st = detect.status(t.exit_code)
      if st == "failed" then
        info.status = "failed"
      elseif st == "running" and t.program and not detect.is_shell(t.program) and info.status ~= "failed" then
        info.status = "busy"
      end
      info.activity = info.activity or t.activity
      info.port = info.port or t.port
    end
  end
  local act = term.get(tab.active)
  info.program = act and act.program
  return info
end

--- The prefix as shown to the user: "<C-a>" becomes "^a".
function M.prefix_label()
  return (config.options.prefix:gsub("<[Cc]%-(%a)>", "^%1"):lower())
end

-- Wrap segments in rounded caps, like a lualine section. Without pills the
-- caps become plain spaces in the pill colour.
local function pill(body, fill, cap)
  local left = config.options.pills and G.pill_left or " "
  local right = config.options.pills and G.pill_right or " "
  local capped = { { left, config.options.pills and cap or fill } }
  for _, s in ipairs(body) do
    capped[#capped + 1] = s
  end
  capped[#capped + 1] = { right, config.options.pills and cap or fill }
  return capped
end

local function tab_segments(i, tab, active, name_max)
  local info = M.tab_info(tab)
  local name = state.label(tab, M.session and M.session.root)
  if vim.fn.strchars(name) > name_max then
    name = vim.fn.strcharpart(name, 0, math.max(1, name_max - 1)) .. G.ellipsis
  end
  local fill = active and "LoomPillActive" or "LoomPill"
  local mark = active and "LoomPillActiveMark" or nil
  local body = {
    { tostring(i) .. " ", active and fill or "LoomPillIndex" },
    { detect.icon(info.program or "zsh") .. " " .. name, fill },
  }
  if info.status == "failed" then
    body[#body + 1] = { " " .. G.cross, mark or "LoomPillFailed" }
  elseif info.status == "busy" then
    body[#body + 1] = { " " .. G.dot, mark or "LoomPillBusy" }
  end
  if info.port then
    body[#body + 1] = { " " .. G.globe .. " " .. info.port, mark or "LoomPillPort" }
  end
  if info.activity and not active then
    body[#body + 1] = { " " .. G.bullet, "LoomPillActivity" }
  end
  return pill(body, fill, active and "LoomPillActiveCap" or "LoomPillCap")
end

local function right_segments(s)
  local segs = {}
  if M.armed then
    vim.list_extend(segs, pill({ { "PREFIX", "LoomPrefix" } }, "LoomPrefix", "LoomPrefixCap"))
    segs[#segs + 1] = { " ", "LoomNormal" }
  else
    segs[#segs + 1] = { M.prefix_label() .. " ? keys  ", "LoomHint" }
  end
  vim.list_extend(segs, pill({ { G.loom .. " " .. s.name, "LoomSession" } }, "LoomSession", "LoomSessionCap"))
  return segs
end

local function draw_tabbar(cv, s, width)
  M.tab_hits = {}
  local right = right_segments(s)
  local avail = width - canvas.width_of(right) - 1
  -- Shrink names until every tab fits, down to a few characters.
  local name_max = 24
  local all
  repeat
    all = {}
    for i, tab in ipairs(s.tabs) do
      all[i] = tab_segments(i, tab, i == s.active, name_max)
    end
    local total = #all - 1
    for _, segs in ipairs(all) do
      total = total + canvas.width_of(segs)
    end
    name_max = name_max - 2
  until total <= avail or name_max < 4
  local col = 0
  for i, segs in ipairs(all) do
    local start = col
    col = cv:segments(0, col, segs)
    M.tab_hits[#M.tab_hits + 1] = { start, col, i }
    col = col + 1 -- a gap between pills
  end
  cv:segments(0, width - canvas.width_of(right), right)
end

-- The rule between the tab bar and the panes, lined up with the pane margins.
local function draw_rule(cv, box)
  cv:put(box.row - 1, box.col, string.rep("─", box.width), "LoomSep")
end

-- ── Separators ─────────────────────────────────────────────────────────────

local function touches(cell, r)
  local in_rows = cell.row >= r.row - 1 and cell.row <= r.row + r.height
  local in_cols = cell.col >= r.col - 1 and cell.col <= r.col + r.width
  if not (in_rows and in_cols) then
    return false
  end
  return cell.col == r.col - 1 or cell.col == r.col + r.width or cell.row == r.row - 1 or cell.row == r.row + r.height
end

local function draw_seps(cv, seps, active_rect)
  for _, cell in ipairs(layout.sep_cells(seps)) do
    local hl = (active_rect and touches(cell, active_rect)) and "LoomSepActive" or "LoomSep"
    cv:put(cell.row, cell.col, cell.char, hl)
  end
end

-- ── Windows ────────────────────────────────────────────────────────────────

local function footer()
  local k, f = "LoomFooterKey", "LoomFooter"
  local items = M.armed
      and {
        { "c", "new" },
        { "n/p", "tab" },
        { "_", "side" },
        { "-", "stack" },
        { "hjkl", "move" },
        { "z", "zoom" },
        { "x", "close" },
        { "s", "session" },
        { "[", "scroll" },
        { "d", "hide" },
      }
    or {
      { M.prefix_label(), "prefix" },
      { "c", "new" },
      { "_", "split" },
      { "-", "stack" },
      { "z", "zoom" },
      { "?", "help" },
    }
  local out = { { " ", f } }
  for _, it in ipairs(items) do
    out[#out + 1] = { it[1], k }
    out[#out + 1] = { " " .. it[2] .. "  ", f }
  end
  return out
end

-- The session now has its own pill in the tab bar, so the title stays short.
local function title()
  return { { " " .. G.loom .. " loom ", "LoomTitle" } }
end

local function ensure_frame(g, s)
  if not (M.frame.buf and vim.api.nvim_buf_is_valid(M.frame.buf)) then
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].filetype = "loom_frame"
    M.frame.buf = buf
  end
  local cfg = {
    relative = "editor",
    row = g.row,
    col = g.col,
    width = g.width,
    height = g.height,
    border = config.options.border,
    title = title(),
    title_pos = "center",
    footer = footer(),
    footer_pos = "center",
    zindex = Z,
    focusable = true,
  }
  if M.frame.win and vim.api.nvim_win_is_valid(M.frame.win) then
    vim.api.nvim_win_set_config(M.frame.win, cfg)
  else
    cfg.style = "minimal"
    cfg.noautocmd = true
    M.frame.win = vim.api.nvim_open_win(M.frame.buf, false, cfg)
    vim.wo[M.frame.win].winhighlight =
      "Normal:LoomNormal,FloatBorder:LoomBorder,FloatTitle:LoomTitle,FloatFooter:LoomFooter"
    vim.wo[M.frame.win].cursorline = false
  end
end

local function pane_winhl()
  if config.options.dim_inactive then
    return "Normal:LoomPane,NormalNC:LoomPaneInactive"
  end
  return "Normal:LoomPane,NormalNC:LoomPane"
end

local function place_pane(t, g, r)
  local cfg = {
    relative = "editor",
    row = g.row + 1 + r.row,
    col = g.col + 1 + r.col,
    width = math.max(1, r.width),
    height = math.max(1, r.height),
    zindex = Z + 1,
    focusable = true,
  }
  local win = M.panes[t.id]
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_config(win, cfg)
    if vim.api.nvim_win_get_buf(win) ~= t.buf then
      vim.api.nvim_win_set_buf(win, t.buf)
    end
  else
    cfg.style = "minimal"
    cfg.border = "none"
    cfg.noautocmd = true
    win = vim.api.nvim_open_win(t.buf, false, cfg)
    M.panes[t.id] = win
    vim.wo[win].winhighlight = pane_winhl()
    vim.wo[win].scrolloff = 0
    vim.wo[win].sidescrolloff = 0
    vim.w[win].loom_pane = t.id
  end
  return win
end

local function close_win(win)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

--- Draw session `s`. With `focus`, move the cursor into the active pane.
function M.render(s, opts)
  opts = opts or {}
  local tab = state.tab(s)
  if not tab then
    return M.hide()
  end
  local g = M.geometry()
  M.geom, M.session = g, s
  ensure_frame(g, s)

  local rects, seps
  if tab.zoomed then
    rects, seps = { [tab.active] = g.box }, {}
  else
    rects, seps = layout.rects(tab.layout, g.box)
  end

  local cv = canvas.new(g.width, g.height, "LoomNormal")
  draw_tabbar(cv, s, g.width)
  draw_rule(cv, g.box)
  draw_seps(cv, seps, not tab.zoomed and rects[tab.active] or nil)
  cv:flush(M.frame.buf, M.ns)

  -- Window changes made here are loom's own, not the user leaving the float.
  M.moving = true
  local was_inside = M.is_loom_win(vim.api.nvim_get_current_win())

  -- Show this tab's panes. Focus moves to the new active pane before old
  -- windows close, so closing the window under the cursor never drops focus
  -- into the editor behind the float.
  local shown = {}
  for id, r in pairs(rects) do
    local t = term.get(id)
    if t then
      place_pane(t, g, r)
      shown[id] = true
    end
  end
  local focus = opts.focus or (was_inside and not shown[M.current_pane() or -1])
  local target = M.panes[tab.active]
  if focus and target and vim.api.nvim_win_is_valid(target) then
    vim.api.nvim_set_current_win(target)
  end
  for id, win in pairs(M.panes) do
    if not shown[id] then
      close_win(win)
      M.panes[id] = nil
    end
  end
  for id, t in pairs(term.terms) do
    term.set_visible(t, shown[id] == true)
  end
  M.visible = true
  M.moving = false

  if focus and opts.insert ~= false then
    vim.cmd("startinsert")
  end
  M.sync_prefix()
end

function M.hide()
  M.hiding = true
  for id, win in pairs(M.panes) do
    close_win(win)
    M.panes[id] = nil
  end
  close_win(M.frame.win)
  M.frame.win = nil
  for _, t in pairs(term.terms) do
    term.set_visible(t, false)
  end
  M.visible = false
  M.armed = false
  M.hiding = false
  M.sync_prefix()
end

-- Whether this Neovim set @loom. It starts false on purpose: a Neovim that
-- never set @loom must never clear it. A nested Neovim, such as one started in
-- a loom pane or as a git editor, inherits the parent's TMUX_PANE, and used to
-- wipe the parent's @loom on its first window event or on exit.
local tmux_state = false

--- Tell tmux whether a loom pane has focus, through the pane option @loom.
--- A tmux binding can then send a shared prefix key to loom instead of
--- treating it as the tmux prefix. Runs a command only when the state flips,
--- or with `reassert` while it should be on, to heal an @loom cleared outside.
function M.sync_tmux(force_off, reassert)
  local pane = vim.env.TMUX_PANE
  if not (config.options.tmux and vim.env.TMUX and pane) then
    return
  end
  local on = not force_off and M.visible and M.current_pane() ~= nil
  if on == tmux_state and not (reassert and on) then
    return
  end
  tmux_state = on
  local cmd = on and { "tmux", "set-option", "-p", "-t", pane, "@loom", "1" }
    or { "tmux", "set-option", "-p", "-u", "-t", pane, "@loom" }
  if force_off then
    vim.system(cmd):wait(500) -- on exit, finish before Neovim goes away
  else
    vim.system(cmd)
  end
end

-- Same guard for sluice: only a Neovim that turned the handoff on may turn it off.
local sluice_state = false

--- Tell sluice (the zmx-based tmux replacement) whether a loom pane has focus,
--- through `sluice handoff on|off`. sluice then forwards the shared prefix key
--- to Neovim instead of treating it as its own prefix. The marker carries this
--- Neovim's pid, so sluice drops the handoff by itself if Neovim dies.
function M.sync_sluice(force_off, reassert)
  if not (config.options.sluice and vim.env.ZMX_SESSION) then
    return
  end
  if vim.fn.executable("sluice") ~= 1 then
    return
  end
  local on = not force_off and M.visible and M.current_pane() ~= nil
  if on == sluice_state and not (reassert and on) then
    return
  end
  sluice_state = on
  local cmd = { "sluice", "handoff", on and "on" or "off", "--pid", tostring(vim.fn.getpid()) }
  if force_off then
    vim.system(cmd):wait(500) -- on exit, finish before Neovim goes away
  else
    vim.system(cmd)
  end
end

--- Keep every prefix-sharing host in step: tmux via @loom, sluice via handoff.
function M.sync_prefix(force_off, reassert)
  M.sync_tmux(force_off, reassert)
  M.sync_sluice(force_off, reassert)
end

--- The pane window under the cursor's window, as a term id.
function M.current_pane()
  return vim.w[vim.api.nvim_get_current_win()].loom_pane
end

function M.is_loom_win(win)
  return win == M.frame.win or vim.w[win].loom_pane ~= nil
end

--- The tab index under a mouse position from getmousepos(), or nil.
--- Screen coordinates avoid any doubt about how borders count.
function M.tab_at_mouse(pos)
  local g = M.geom
  if not g or pos.screenrow ~= g.row + 2 then
    return nil
  end
  return M.tab_at(pos.screencol - 1 - (g.col + 1))
end

--- The tab index at a column of the tab bar, for mouse clicks.
function M.tab_at(col)
  for _, h in ipairs(M.tab_hits) do
    if col >= h[1] and col < h[2] then
      return h[3]
    end
  end
end

return M
