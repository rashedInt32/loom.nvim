-- Nerd Font glyphs, built from codepoints at load time.
--
-- Private-use characters are easy to lose when a file passes through tools
-- that do not keep them, which leaves empty strings behind. Codepoints in
-- plain ASCII cannot be lost.
local function g(cp)
  return vim.fn.nr2char(cp)
end

return {
  pill_left = g(0xE0B6), -- rounded cap, as in lualine
  pill_right = g(0xE0B4),
  loom = g(0xF018D), -- md-console
  terminal = g(0xF120),
  shell = g(0xF489),
  node = g(0xE718),
  npm = g(0xE71E),
  deno = g(0xE7C0),
  git = g(0xE702),
  github = g(0xF09B),
  vim = g(0xE62B),
  python = g(0xE73C),
  ruby = g(0xE739),
  rust = g(0xE7A8),
  go = g(0xE627),
  docker = g(0xF308),
  make = g(0xE779),
  remote = g(0xF08C0), -- md-lan-connect, for remote shells
  chart = g(0xF080),
  robot = g(0xF06A9),
  globe = g(0xF059F), -- md-web, before a port number
  dot = g(0x25CF), -- ●
  cross = g(0xF00D),
  bullet = g(0x2022), -- •
  ellipsis = g(0x2026), -- …
  session = g(0xF0645), -- md-layers-outline-ish, marks the session pill
}
