-- Scroll-mode keys in a loom terminal: gf opens the file under the cursor.
local eq = MiniTest.expect.equality
local loom = require("loom")
local ui = require("loom.ui")
local state = require("loom.state")
local term = require("loom.term")

local dir = vim.fn.tempname()
local file = dir .. "/loomgf.txt"

-- Put `text` on the first line of the active loom terminal buffer, cursor on it.
local function cursor_on(text)
  local s = state.sessions[loom.current]
  local t = term.get(state.tab(s).active)
  vim.cmd("stopinsert")
  vim.bo[t.buf].modifiable = true
  vim.api.nvim_buf_set_lines(t.buf, 0, 1, false, { text })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  return t
end

local function press_gf(buf)
  vim.fn.maparg("gf", "n", false, true).callback()
  vim.wait(200, function()
    return vim.api.nvim_buf_get_name(0) ~= "" and not vim.b[vim.api.nvim_get_current_buf()].loom_term
  end, 10)
end

local T = MiniTest.new_set({
  hooks = {
    pre_once = function()
      vim.fn.mkdir(dir, "p")
      vim.fn.writefile({ "one", "two", "three" }, file)
    end,
    pre_case = function()
      vim.o.columns, vim.o.lines = 120, 40
      loom.setup({ shell = "/bin/sh", env = { PS1 = "$ " }, toggle = {}, hide_on_leave = false })
      loom.show()
    end,
    post_case = function()
      loom.hide()
      state.reset()
      loom.current = nil
      vim.cmd("silent! %bwipeout!")
    end,
  },
})

T["gf opens a file findfile resolves, at the line after the colon"] = function()
  cursor_on(file .. ":3")
  press_gf()
  eq(ui.visible, false)
  eq(vim.api.nvim_buf_get_name(0), vim.fn.resolve(file))
  eq(vim.api.nvim_win_get_cursor(0)[1], 3)
end

T["gf falls back to a readable path when findfile misses it"] = function()
  cursor_on(file)
  local real = vim.fn.findfile
  vim.fn.findfile = function()
    return ""
  end
  local ok, err = pcall(press_gf)
  vim.fn.findfile = real
  assert(ok, err)
  eq(vim.api.nvim_buf_get_name(0), vim.fn.resolve(file))
end

T["gf warns and stays put when nothing is under the cursor"] = function()
  cursor_on("/no/such/loom/file.txt")
  local notes = {}
  local real = vim.notify
  vim.notify = function(msg, level)
    notes[#notes + 1] = { msg, level }
  end
  vim.fn.maparg("gf", "n", false, true).callback()
  vim.notify = real
  eq(notes, { { "loom: no file under cursor", vim.log.levels.WARN } })
  eq(ui.visible, true)
end

return T
