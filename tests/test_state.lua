-- Sessions and tabs: creation, splits, closing panes and tabs, labels.
local eq = MiniTest.expect.equality
local state = require("loom.state")
local layout = require("loom.layout")
local term = require("loom.term")
local config = require("loom.config")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup({ shell = "/bin/sh", env = { PS1 = "$ " } })
    end,
    post_case = function()
      state.reset()
    end,
  },
})

T["sessions are keyed by name and remember their root"] = function()
  local a = state.session("base", "/tmp")
  eq(state.session("base"), a)
  eq(a.root, "/tmp")
  state.session("work")
  eq(state.order, { "base", "work" })
end

T["for_cwd names the session after the git root"] = function()
  local s = state.for_cwd()
  eq(s.name, vim.fn.fnamemodify(state.root_of(), ":t"))
end

T["new_tab and split track the active pane"] = function()
  local s = state.session("t", "/tmp")
  local a = state.new_tab(s)
  eq(s.active, 1)
  local b = state.split(s, "vertical")
  local tab = state.tab(s)
  eq(tab.active, b.id)
  eq(layout.leaves(tab.layout), { a.id, b.id })
  eq(b.cwd, "/tmp")
end

T["closing the active pane moves focus to its neighbour"] = function()
  local s = state.session("t", "/tmp")
  local a = state.new_tab(s)
  local b = state.split(s, "vertical")
  state.close_pane(s, b.id)
  eq(state.tab(s).active, a.id)
  eq(term.get(b.id), nil)
end

T["closing the last pane closes the tab"] = function()
  local s = state.session("t", "/tmp")
  state.new_tab(s)
  local b = state.new_tab(s)
  eq(#s.tabs, 2)
  state.close_pane(s, b.id)
  eq(#s.tabs, 1)
  eq(s.active, 1)
end

T["close_tab kills every pane in it"] = function()
  local s = state.session("t", "/tmp")
  local a = state.new_tab(s)
  local b = state.split(s, "horizontal")
  state.new_tab(s)
  state.close_tab(s, 1)
  eq(#s.tabs, 1)
  eq(term.get(a.id), nil)
  eq(term.get(b.id), nil)
end

T["label prefers the override, then the program, and never repeats the session"] = function()
  local s = state.session("t", "/tmp")
  local t = state.new_tab(s)
  local tab = state.tab(s)
  -- An idle shell at the session root is named after the shell, not the folder.
  eq(state.label(tab, s.root), "shell")
  t.program = "-zsh"
  eq(state.label(tab, s.root), "zsh")
  -- Elsewhere, the folder tells tabs apart.
  t.cwd = "/tmp/other"
  eq(state.label(tab, s.root), "other")
  t.program = "pnpm"
  eq(state.label(tab, s.root), "pnpm")
  tab.name = "dev"
  eq(state.label(tab, s.root), "dev")
end

T["find locates a terminal's session and tab"] = function()
  local s = state.session("t", "/tmp")
  state.new_tab(s)
  local b = state.new_tab(s)
  local fs, idx = state.find(b.id)
  eq(fs, s)
  eq(idx, 2)
end

return T
