-- The float end to end: windows, positions, tab bar, splits, zoom, hide.
local eq = MiniTest.expect.equality
local loom = require("loom")
local ui = require("loom.ui")
local state = require("loom.state")
local term = require("loom.term")
local keys = require("loom.keys")

local function pane_wins()
  local out = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[win].loom_pane then
      out[#out + 1] = win
    end
  end
  table.sort(out, function(a, b)
    return vim.api.nvim_win_get_position(a)[2] < vim.api.nvim_win_get_position(b)[2]
  end)
  return out
end

local function frame_lines()
  return vim.api.nvim_buf_get_lines(ui.frame.buf, 0, -1, false)
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      vim.o.columns, vim.o.lines = 120, 40
      loom.setup({ shell = "/bin/sh", env = { PS1 = "$ " }, toggle = {}, hide_on_leave = false })
    end,
    post_case = function()
      loom.hide()
      state.reset()
      loom.current = nil
    end,
  },
})

T["show opens a frame and one focused pane with a first shell"] = function()
  loom.show()
  eq(ui.visible, true)
  eq(vim.api.nvim_win_is_valid(ui.frame.win), true)
  local wins = pane_wins()
  eq(#wins, 1)
  eq(vim.api.nvim_get_current_win(), wins[1])
  local g = ui.geometry()
  local cfg = vim.api.nvim_win_get_config(wins[1])
  eq(
    { cfg.row, cfg.col, cfg.width, cfg.height },
    { g.row + 1 + g.box.row, g.col + 1 + g.box.col, g.box.width, g.box.height }
  )
  eq(frame_lines()[1]:find("1 ", 1, true) ~= nil, true)
end

T["a vertical split puts two panes side by side with a separator"] = function()
  loom.show()
  loom.split("vertical")
  local wins = pane_wins()
  eq(#wins, 2)
  local a, b = vim.api.nvim_win_get_config(wins[1]), vim.api.nvim_win_get_config(wins[2])
  eq(a.row, b.row)
  eq(b.col, a.col + a.width + 1)
  -- The new pane is focused, and the separator column is drawn in the frame.
  eq(vim.api.nvim_get_current_win(), wins[2])
  local g = ui.geom
  local line = frame_lines()[g.box.row + 2]
  eq(vim.fn.strcharpart(line, a.col - g.col - 1 + a.width, 1), "│")
end

T["a rule under the tab bar keeps every pane off the tabs"] = function()
  loom.show()
  loom.split("horizontal")
  local g = ui.geom
  -- Row 1 of the frame is the rule, across the pane area.
  local rule = frame_lines()[2]
  eq(vim.fn.strcharpart(rule, g.box.col, g.box.width), string.rep("─", g.box.width))
  -- The top pane starts below the rule, never on the tab bar's next row.
  for _, win in ipairs(pane_wins()) do
    eq(vim.api.nvim_win_get_config(win).row >= g.row + 1 + g.box.row, true)
  end
end

T["zoom shows only the active pane, and again restores both"] = function()
  loom.show()
  loom.split("vertical")
  loom.zoom()
  eq(#pane_wins(), 1)
  loom.zoom()
  eq(#pane_wins(), 2)
end

T["move follows the layout and next_pane cycles"] = function()
  loom.show()
  local s = state.sessions[loom.current]
  local first = state.tab(s).active
  loom.split("vertical")
  loom.move("h")
  eq(state.tab(s).active, first)
  loom.next_pane()
  eq(state.tab(s).active ~= first, true)
end

T["tabs switch, and hidden tabs keep their terminals running"] = function()
  loom.show()
  local s = state.sessions[loom.current]
  local t1 = state.tab(s).active
  loom.new_tab()
  eq(#s.tabs, 2)
  eq(s.active, 2)
  eq(term.get(t1).visible, false)
  eq(term.running(term.get(t1)), true)
  loom.goto_tab(1)
  eq(term.get(t1).visible, true)
  loom.cycle_tab(1)
  eq(s.active, 2)
end

T["hide closes every window and leaves jobs running"] = function()
  loom.show()
  loom.split("horizontal")
  loom.hide()
  eq(#pane_wins(), 0)
  eq(ui.frame.win, nil)
  for _, t in pairs(term.terms) do
    eq(term.running(t), true)
  end
  loom.toggle()
  eq(#pane_wins(), 2)
end

T["tab_at maps tab bar columns to tabs"] = function()
  loom.show()
  loom.new_tab()
  local first, second = ui.tab_hits[1], ui.tab_hits[2]
  eq(ui.tab_at(first[1]), 1)
  eq(ui.tab_at(second[1]), 2)
  eq(ui.tab_at(9999), nil)
end

T["a clean shell exit closes its pane"] = function()
  loom.show()
  local s = state.sessions[loom.current]
  loom.split("vertical")
  local id = state.tab(s).active
  vim.fn.chansend(term.get(id).job, "exit\r")
  eq(
    vim.wait(3000, function()
      return term.get(id) == nil
    end, 20),
    true
  )
  eq(#pane_wins(), 1)
end

T["new tabs and closing panes keep the float open when hide_on_leave is on"] = function()
  loom.setup({ shell = "/bin/sh", env = { PS1 = "$ " }, toggle = {}, hide_on_leave = true })
  loom.show()
  loom.new_tab()
  vim.wait(50)
  eq(ui.visible, true)
  loom.split("vertical")
  loom.close_pane()
  vim.wait(50)
  eq(ui.visible, true)
  eq(vim.w[vim.api.nvim_get_current_win()].loom_pane ~= nil, true)
  loom.goto_tab(1)
  vim.wait(50)
  eq(ui.visible, true)
end

T["typing exit in pane after pane closes one pane at a time"] = function()
  loom.setup({ shell = "/bin/sh", env = { PS1 = "$ " }, toggle = {}, hide_on_leave = true })
  loom.show()
  loom.split("vertical")
  loom.split("horizontal")
  loom.split("vertical")
  local s = state.sessions[loom.current]
  for left = 3, 1, -1 do
    local id = state.tab(s).active
    vim.fn.chansend(term.get(id).job, "exit\r")
    eq(
      vim.wait(3000, function()
        return term.get(id) == nil
      end, 20),
      true
    )
    vim.wait(100) -- let any queued hide run
    eq({ left, ui.visible, #pane_wins() }, { left, true, left })
    eq(vim.w[vim.api.nvim_get_current_win()].loom_pane ~= nil, true)
  end
  -- The last shell closes the last pane, the tab, and the float.
  local id = state.tab(s).active
  vim.fn.chansend(term.get(id).job, "exit\r")
  eq(
    vim.wait(3000, function()
      return not ui.visible
    end, 20),
    true
  )
end

T["a pane window closed by Neovim itself does not hide the float"] = function()
  -- Neovim closes an exited terminal's window on its own, and focus can land
  -- on the editor behind the float before loom redraws.
  loom.setup({ shell = "/bin/sh", env = { PS1 = "$ " }, toggle = {}, hide_on_leave = true })
  local editor = vim.api.nvim_get_current_win()
  loom.show()
  loom.split("vertical")
  loom.split("horizontal")
  local s = state.sessions[loom.current]
  for _ = 1, 2 do
    local id = state.tab(s).active
    local t = term.get(id)
    vim.api.nvim_win_close(ui.panes[id], true)
    vim.api.nvim_set_current_win(editor)
    vim.api.nvim_buf_delete(t.buf, { force = true })
    vim.wait(200)
    eq(ui.visible, true)
    eq(vim.w[vim.api.nvim_get_current_win()].loom_pane ~= nil, true)
  end
  eq(#pane_wins(), 1)
end

T["focusing a window outside the float hides it"] = function()
  loom.setup({ shell = "/bin/sh", env = { PS1 = "$ " }, toggle = {}, hide_on_leave = true })
  local editor = vim.api.nvim_get_current_win()
  loom.show()
  vim.api.nvim_set_current_win(editor)
  vim.wait(200, function()
    return not ui.visible
  end)
  eq(ui.visible, false)
end

T["tab_at_mouse maps a screen position on the tab bar to a tab"] = function()
  -- Real clicks are checked in a live terminal; this pins the arithmetic.
  loom.show()
  loom.new_tab()
  local g, second = ui.geom, ui.tab_hits[2]
  local bar_row = g.row + 2 -- 1-based screen row of the first row inside the border
  local col_of = function(canvas_col)
    return canvas_col + 1 + g.col + 1
  end
  eq(ui.tab_at_mouse({ screenrow = bar_row, screencol = col_of(0) }), 1)
  eq(ui.tab_at_mouse({ screenrow = bar_row, screencol = col_of(second[1]) }), 2)
  eq(ui.tab_at_mouse({ screenrow = bar_row + 1, screencol = col_of(0) }), nil)
end

T["sessions keep their own tabs"] = function()
  loom.show()
  local home = loom.current
  loom.new_tab()
  loom.session("work")
  eq(loom.current, "work")
  eq(#state.sessions.work.tabs, 1)
  eq(#state.sessions[home].tabs, 2)
  loom.session(home)
  eq(ui.session.name, home)
end

T["every key in the spec has an action"] = function()
  for _, k in ipairs({
    "c",
    "n",
    "p",
    ",",
    "&",
    "%",
    "_",
    "-",
    '"',
    "h",
    "j",
    "k",
    "l",
    "o",
    "H",
    "J",
    "K",
    "L",
    "z",
    "x",
    "R",
    "s",
    "S",
    "[",
    "d",
    "q",
    "?",
    "1",
    "9",
  }) do
    eq(type(keys.action_for(k)), "function")
  end
  eq(type(keys.action_for(vim.keycode("<Left>"))), "function")
  eq(keys.action_for("Q"), nil)
end

return T
