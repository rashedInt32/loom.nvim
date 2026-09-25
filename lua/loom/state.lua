-- Sessions and tabs: which terminals exist and how each tab lays them out.
--
--   session = { name, root, tabs = { tab... }, active = index }
--   tab     = { layout, active = term id, name = override|nil, zoomed }
local layout = require("loom.layout")
local term = require("loom.term")
local detect = require("loom.detect")

local M = {}

M.sessions = {} ---@type table<string, table>
M.order = {} -- session names in creation order, for the picker

--- The project a directory belongs to: its git root, or the directory itself.
function M.root_of(dir)
  dir = dir or vim.fn.getcwd()
  return vim.fs.root(dir, ".git") or dir
end

--- Get or create a session. `root` is where its new terminals start.
function M.session(name, root)
  local s = M.sessions[name]
  if not s then
    s = { name = name, root = root or vim.fn.getcwd(), tabs = {}, active = 0 }
    M.sessions[name] = s
    M.order[#M.order + 1] = name
  end
  return s
end

--- The session for the current working directory's project.
function M.for_cwd()
  local root = M.root_of()
  return M.session(vim.fn.fnamemodify(root, ":t"), root)
end

function M.tab(s)
  return s.tabs[s.active]
end

--- Open a tab with one fresh terminal and make it active.
function M.new_tab(s, opts)
  opts = opts or {}
  local t = term.new({ cmd = opts.cmd, cwd = opts.cwd or s.root })
  table.insert(s.tabs, { layout = layout.leaf(t.id), active = t.id, name = opts.name, zoomed = false })
  s.active = #s.tabs
  return t
end

--- Split the active pane of the active tab. The new pane becomes active.
function M.split(s, dir, opts)
  opts = opts or {}
  local tab = M.tab(s)
  if not tab then
    return M.new_tab(s, opts)
  end
  local cur = term.get(tab.active)
  local t = term.new({ cmd = opts.cmd, cwd = opts.cwd or (cur and cur.cwd) or s.root })
  tab.layout = layout.split(tab.layout, tab.active, dir, t.id)
  tab.active = t.id
  tab.zoomed = false
  return t
end

--- The tab index and tab holding a terminal, in any session.
function M.find(term_id)
  for _, s in pairs(M.sessions) do
    for i, tab in ipairs(s.tabs) do
      -- A tab being closed can have no layout for a moment.
      if tab.layout and layout.contains(tab.layout, term_id) then
        return s, i, tab
      end
    end
  end
end

--- Close one pane. An emptied tab closes too.
function M.close_pane(s, term_id)
  local idx, tab
  for i, tb in ipairs(s.tabs) do
    if layout.contains(tb.layout, term_id) then
      idx, tab = i, tb
    end
  end
  if not tab then
    return
  end
  local next_active = layout.cycle(tab.layout, term_id, -1)
  tab.layout = layout.remove(tab.layout, term_id)
  local t = term.get(term_id)
  if t then
    term.kill(t)
  end
  if not tab.layout then
    M.remove_tab(s, idx)
  else
    tab.zoomed = false
    if tab.active == term_id then
      tab.active = next_active ~= term_id and next_active or layout.leaves(tab.layout)[1]
    end
  end
end

--- Drop a tab from the list without touching its terminals.
function M.remove_tab(s, idx)
  table.remove(s.tabs, idx)
  if s.active > #s.tabs then
    s.active = #s.tabs
  elseif s.active > idx then
    s.active = s.active - 1
  end
  if #s.tabs > 0 and s.active == 0 then
    s.active = 1
  end
end

--- Close a tab and every terminal in it.
function M.close_tab(s, idx)
  local tab = s.tabs[idx]
  if not tab then
    return
  end
  for _, id in ipairs(layout.leaves(tab.layout)) do
    local t = term.get(id)
    if t then
      term.kill(t)
    end
  end
  M.remove_tab(s, idx)
end

--- What a tab is called: its override, else the program running in its
--- active pane. An idle shell is named after its folder when that differs
--- from the session `root`, and after the shell otherwise, so a tab never just
--- repeats the session name.
function M.label(tab, root)
  if tab.name and tab.name ~= "" then
    return tab.name
  end
  local t = term.get(tab.active)
  if not t then
    return "shell"
  end
  if t.program and not detect.is_shell(t.program) then
    return t.program
  end
  if root and vim.fs.normalize(t.cwd) ~= vim.fs.normalize(root) then
    return vim.fn.fnamemodify(t.cwd, ":t")
  end
  return t.program and (t.program:match("([^/]+)$"):gsub("^%-", "")) or "shell"
end

--- Remove every session. For tests.
function M.reset()
  for _, s in pairs(M.sessions) do
    while #s.tabs > 0 do
      M.close_tab(s, 1)
    end
  end
  M.sessions, M.order = {}, {}
end

return M
