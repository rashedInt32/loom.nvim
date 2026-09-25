-- Highlight groups, derived from the active colour scheme and the `colors`
-- option, set again on every ColorScheme event.
--
-- A transparent scheme leaves Normal without a background. loom then leaves
-- its own backgrounds unset too, so the float shows the same terminal
-- background as the editor behind it.
local config = require("loom.config")

local M = {}

local function get(name, attr)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if ok and hl[attr] then
    return hl[attr]
  end
end

-- The first group in the list that defines the attribute.
local function pick(attr, names, fallback)
  for _, name in ipairs(names) do
    local v = get(name, attr)
    if v then
      return v
    end
  end
  return fallback
end

local function rgb(n)
  return math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
end

--- Mix colour `a` toward colour `b` by `t` (0 keeps a, 1 gives b).
function M.blend(a, b, t)
  local ar, ag, ab = rgb(a)
  local br, bg, bb = rgb(b)
  local function mix(x, y)
    return math.floor(x + (y - x) * t + 0.5)
  end
  return mix(ar, br) * 65536 + mix(ag, bg) * 256 + mix(ab, bb)
end

local function color(v)
  if type(v) == "string" then
    return tonumber(v:gsub("^#", ""), 16)
  end
  return v
end

--- The resolved palette. Exposed for tests and for the renderer.
function M.palette()
  local opts = config.options.colors or {}
  local dark = vim.o.background ~= "light"
  local base = pick("bg", { "NormalFloat", "Normal" }, nil)
  local fg = pick("fg", { "NormalFloat", "Normal" }, dark and 0xe0def4 or 0x575279)
  -- Stand-in for mixing when the real background is transparent.
  local ref = base or (dark and 0x0b0f14 or 0xffffff)
  local p = {
    transparent = base == nil,
    bg = base, -- nil means NONE
    fg = fg,
    muted = pick("fg", { "Comment" }, M.blend(fg, ref, 0.45)),
    border = pick("fg", { "FloatBorder", "WinSeparator" }, M.blend(fg, ref, 0.6)),
    accent = color(opts.active) or pick("fg", { "FloatTitle", "Special", "Function" }, 0x82aaff),
    ok = pick("fg", { "DiagnosticOk", "DiagnosticHint" }, 0x90b99f),
    warn = pick("fg", { "DiagnosticWarn" }, 0xe6b99d),
    err = pick("fg", { "DiagnosticError" }, 0xea83a5),
  }
  -- Text on a coloured pill: the editor background, or near black.
  p.on_pill = color(opts.active_fg) or base or (dark and 0x131314 or 0xffffff)
  p.inactive = color(opts.inactive) or M.blend(p.accent, ref, 0.82)
  p.inactive_fg = color(opts.inactive_fg) or M.blend(p.accent, fg, 0.35)
  p.session = color(opts.session) or p.ok
  p.prefix = color(opts.prefix) or p.warn
  p.dim = color(opts.dim) or (base and M.blend(base, 0x000000, dark and 0.22 or 0.05) or nil)
  return p
end

function M.set()
  local p = M.palette()
  local bg = p.bg
  local groups = {
    LoomNormal = { fg = p.fg, bg = bg },
    LoomBorder = { fg = p.border, bg = bg },
    LoomTitle = { fg = p.accent, bg = bg, bold = true },
    LoomFooter = { fg = p.muted, bg = bg },
    LoomFooterKey = { fg = p.accent, bg = bg, bold = true },
    LoomSep = { fg = p.border, bg = bg },
    LoomSepActive = { fg = p.accent, bg = bg },
    LoomPane = { bg = bg },
    LoomPaneInactive = { bg = config.options.dim_inactive and p.dim or bg },
    -- Tab pills: the active one filled with the accent, the rest tinted.
    LoomPillActive = { fg = p.on_pill, bg = p.accent, bold = true },
    LoomPillActiveCap = { fg = p.accent, bg = bg },
    LoomPillActiveMark = { fg = p.on_pill, bg = p.accent },
    LoomPill = { fg = p.inactive_fg, bg = p.inactive },
    LoomPillCap = { fg = p.inactive, bg = bg },
    LoomPillIndex = { fg = p.accent, bg = p.inactive, bold = true },
    LoomPillBusy = { fg = p.ok, bg = p.inactive },
    LoomPillFailed = { fg = p.err, bg = p.inactive },
    LoomPillPort = { fg = p.warn, bg = p.inactive },
    LoomPillActivity = { fg = p.accent, bg = p.inactive, bold = true },
    LoomSession = { fg = p.on_pill, bg = p.session, bold = true },
    LoomSessionCap = { fg = p.session, bg = bg },
    LoomPrefix = { fg = p.on_pill, bg = p.prefix, bold = true },
    LoomPrefixCap = { fg = p.prefix, bg = bg },
    LoomHint = { fg = p.muted, bg = bg },
  }
  for name, spec in pairs(groups) do
    vim.api.nvim_set_hl(0, name, spec)
  end
end

return M
