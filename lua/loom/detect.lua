-- What a terminal is doing, read from its output and exit code. Pure.
local M = {}

-- Ordered: the first match wins. Ports below 1024 are ignored, so a stray
-- ":80" in a URL does not become a badge.
local PORT_PATTERNS = {
  "https?://localhost:(%d+)",
  "https?://127%.0%.0%.1:(%d+)",
  "https?://0%.0%.0%.0:(%d+)",
  "https?://%[::1?%]:(%d+)",
  "[Ll]istening on [^%d]*(%d+)",
  "[Pp]ort[ :=]+(%d+)",
}

--- The local port a line announces, or nil.
function M.port(line)
  if type(line) ~= "string" or line == "" then
    return nil
  end
  -- Terminal output keeps colour codes; drop them before matching.
  local plain = line:gsub("\27%[[%d;?]*[%a]", "")
  for _, pat in ipairs(PORT_PATTERNS) do
    local p = plain:match(pat)
    local n = tonumber(p)
    if n and n >= 1024 and n <= 65535 then
      return n
    end
  end
  return nil
end

--- "running" while the job lives, then "done" or "failed" by exit code.
--- Codes from Ctrl-C and SIGTERM count as done: the user stopped it.
function M.status(exit_code)
  if exit_code == nil then
    return "running"
  end
  if exit_code == 0 or exit_code == 130 or exit_code == 143 then
    return "done"
  end
  return "failed"
end

local G = require("loom.glyphs")

local ICONS = {
  node = G.node,
  npm = G.npm,
  pnpm = G.node,
  yarn = G.node,
  bun = G.node,
  npx = G.node,
  deno = G.deno,
  git = G.git,
  lazygit = G.git,
  gh = G.github,
  nvim = G.vim,
  vim = G.vim,
  python = G.python,
  python3 = G.python,
  ruby = G.ruby,
  cargo = G.rust,
  rustc = G.rust,
  go = G.go,
  docker = G.docker,
  make = G.make,
  ssh = G.remote,
  htop = G.chart,
  btop = G.chart,
  top = G.chart,
  claude = G.robot,
  opencode = G.robot,
  zsh = G.shell,
  bash = G.shell,
  fish = G.shell,
  sh = G.shell,
}

M.DEFAULT_ICON = G.terminal

--- A Nerd Font icon for a program name such as "pnpm" or "/bin/zsh".
function M.icon(program)
  if type(program) ~= "string" or program == "" then
    return M.DEFAULT_ICON
  end
  local name = program:match("([^/]+)$"):gsub("^%-", ""):lower()
  return ICONS[name] or ICONS[name:match("^(%a+)")] or M.DEFAULT_ICON
end

local SHELLS = { zsh = true, bash = true, fish = true, sh = true, nu = true }

--- True for an interactive shell, which a tab names after its folder instead.
function M.is_shell(program)
  if type(program) ~= "string" then
    return false
  end
  local name = (program:match("([^/]+)$") or ""):gsub("^%-", "")
  return SHELLS[name] == true
end

return M
