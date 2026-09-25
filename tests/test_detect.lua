-- Detection: ports from output, status from exit codes, icons from programs.
local eq = MiniTest.expect.equality
local D = require("loom.detect")

local T = MiniTest.new_set()

T["port reads the common dev server announcements"] = function()
  eq(D.port("  ▲ Next.js 16.0.0\n   - Local:        http://localhost:3000"), 3000)
  eq(D.port("  ➜  Local:   http://127.0.0.1:5173/"), 5173)
  eq(D.port("Server listening on http://0.0.0.0:8080"), 8080)
  eq(D.port("Listening on port 4000"), 4000)
  eq(D.port("started server on [::]:3001, url: http://localhost:3001"), 3001)
end

T["port ignores colour codes, low ports and plain text"] = function()
  eq(D.port("\27[32m➜\27[0m  Local: \27[36mhttp://localhost:\27[1m5174\27[0m/"), 5174)
  eq(D.port("see http://localhost:80/docs"), nil)
  eq(D.port("compiled successfully"), nil)
  eq(D.port(""), nil)
  eq(D.port(nil), nil)
end

T["status separates a stop from a failure"] = function()
  eq(D.status(nil), "running")
  eq(D.status(0), "done")
  eq(D.status(130), "done")
  eq(D.status(143), "done")
  eq(D.status(1), "failed")
  eq(D.status(127), "failed")
end

T["icon maps programs and falls back"] = function()
  local G = require("loom.glyphs")
  eq(D.icon("pnpm"), G.node)
  eq(D.icon("/opt/homebrew/bin/nvim"), G.vim)
  eq(D.icon("-zsh"), G.shell)
  eq(D.icon("python3.12"), G.python)
  eq(D.icon("Python"), G.python)
  eq(D.icon("unknown-tool"), D.DEFAULT_ICON)
  eq(D.icon(nil), D.DEFAULT_ICON)
end

T["every glyph is one real character"] = function()
  -- Guards against private-use characters being lost as empty strings.
  for name, ch in pairs(require("loom.glyphs")) do
    eq({ name, vim.fn.strchars(ch) }, { name, 1 })
  end
end

T["is_shell knows login shells"] = function()
  eq(D.is_shell("-zsh"), true)
  eq(D.is_shell("/bin/bash"), true)
  eq(D.is_shell("pnpm"), false)
  eq(D.is_shell(nil), false)
end

return T
