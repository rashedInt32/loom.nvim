-- Terminals run through a real pty: output, ports, activity, exit, restart.
local eq = MiniTest.expect.equality
local term = require("loom.term")
local config = require("loom.config")

local function wait(pred, ms)
  return vim.wait(ms or 5000, pred, 20)
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- A plain shell with no user rc files keeps the pty output predictable.
      config.setup({ shell = "/bin/sh", env = { PS1 = "$ " } })
    end,
    post_case = function()
      for _, t in pairs(term.terms) do
        term.kill(t)
      end
    end,
  },
})

T["a typed command runs and its output lands in the buffer"] = function()
  local t = term.new({ cmd = "echo loom-ok" })
  -- The output line is exactly the word; the echoed command line is not.
  eq(
    wait(function()
      return vim.tbl_contains(vim.api.nvim_buf_get_lines(t.buf, 0, -1, false), "loom-ok")
    end),
    true
  )
  eq(term.running(t), true)
  eq(vim.bo[t.buf].filetype, "loom")
  eq(vim.b[t.buf].loom_term, t.id)
end

T["a port announcement sets the badge and hidden output sets activity"] = function()
  local t = term.new({ cmd = "echo 'ready on http://localhost:4321'" })
  eq(
    wait(function()
      return t.port == 4321
    end),
    true
  )
  eq(t.activity, true)
  term.set_visible(t, true)
  eq(t.activity, false)
end

T["exit codes are recorded"] = function()
  local t = term.new({ cmd = "exit 3" })
  eq(
    wait(function()
      return t.exit_code ~= nil
    end),
    true
  )
  eq(t.exit_code, 3)
  eq(term.running(t), false)
end

T["restart keeps the id and swaps in a fresh buffer"] = function()
  local t = term.new({ cmd = "exit 4" })
  wait(function()
    return t.exit_code ~= nil
  end)
  local old = term.restart(t)
  eq(old ~= t.buf, true)
  eq(t.exit_code, nil)
  eq(term.get(t.id), t)
  eq(
    wait(function()
      return t.exit_code == 4
    end),
    true
  )
end

T["poll reads the foreground program"] = function()
  local t = term.new({ cmd = "sleep 5" })
  eq(
    wait(function()
      term.poll(t)
      return t.program == "sleep"
    end, 4000),
    true
  )
end

return T
