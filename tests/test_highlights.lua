-- Colours: transparent schemes stay transparent; the colors option wins.
local eq = MiniTest.expect.equality
local config = require("loom.config")
local highlights = require("loom.highlights")
local ui = require("loom.ui")

local function hl(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end

local T = MiniTest.new_set({
  hooks = {
    post_case = function()
      config.setup({})
    end,
  },
})

T["a transparent scheme leaves loom's backgrounds unset"] = function()
  vim.api.nvim_set_hl(0, "Normal", { fg = 0xe0def4 })
  vim.api.nvim_set_hl(0, "NormalFloat", {})
  config.setup({})
  highlights.set()
  eq(hl("LoomNormal").bg, nil)
  eq(hl("LoomPane").bg, nil)
  eq(hl("LoomPillActiveCap").bg, nil)
  -- Pills still get a fill so they read as pills.
  eq(hl("LoomPillActive").bg ~= nil, true)
end

T["a solid scheme's background carries into the float"] = function()
  vim.api.nvim_set_hl(0, "Normal", { fg = 0xe0def4, bg = 0x191724 })
  config.setup({})
  highlights.set()
  eq(hl("LoomNormal").bg, 0x191724)
  eq(hl("LoomPane").bg, 0x191724)
end

T["the colors option sets the pills"] = function()
  vim.api.nvim_set_hl(0, "Normal", { fg = 0xe0def4 })
  config.setup({ colors = { active = "#82aaff", active_fg = "#131314", session = "#90b99f", prefix = "#e6b99d" } })
  highlights.set()
  eq(hl("LoomPillActive").bg, 0x82aaff)
  eq(hl("LoomPillActive").fg, 0x131314)
  eq(hl("LoomPillActiveCap").fg, 0x82aaff)
  eq(hl("LoomSession").bg, 0x90b99f)
  eq(hl("LoomPrefix").bg, 0xe6b99d)
end

T["prefix_label reads like tmux"] = function()
  config.setup({ prefix = "<C-a>" })
  eq(ui.prefix_label(), "^a")
  config.setup({ prefix = "<c-b>" })
  eq(ui.prefix_label(), "^b")
end

return T
