-- Terminal processes: each lives in a hidden buffer that outlives any window.
local config = require("loom.config")
local detect = require("loom.detect")

local M = {}

---@class loom.Term
---@field id integer
---@field buf integer
---@field job integer
---@field cmd string|nil   typed into the shell after it starts
---@field cwd string
---@field exit_code integer|nil
---@field port integer|nil
---@field activity boolean  printed while not on screen
---@field visible boolean
---@field program string|nil  foreground program, from polling

M.terms = {} ---@type table<integer, loom.Term>
local next_id = 1
local listeners = {}

--- Call `fn(term)` whenever a terminal changes in a way the UI shows.
function M.on_change(fn)
  listeners[#listeners + 1] = fn
end

local function changed(t)
  for _, fn in ipairs(listeners) do
    pcall(fn, t)
  end
end

local function watch(t)
  vim.api.nvim_buf_attach(t.buf, false, {
    on_lines = function(_, buf, _, first, _, last)
      if buf ~= t.buf then
        return true -- detach from a buffer replaced by a restart
      end
      local notify = false
      if not t.visible and not t.activity then
        t.activity, notify = true, true
      end
      if not t.port then
        local lines = vim.api.nvim_buf_get_lines(buf, first, math.min(last, first + 50), false)
        for _, line in ipairs(lines) do
          local p = detect.port(line)
          if p then
            t.port, notify = p, true
            break
          end
        end
      end
      if notify then
        vim.schedule(function()
          changed(t)
        end)
      end
    end,
  })
end

local function spawn(t)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  local shell = config.options.shell or vim.o.shell
  local job
  vim.api.nvim_buf_call(buf, function()
    job = vim.fn.jobstart({ shell }, {
      term = true,
      cwd = t.cwd,
      env = config.options.env,
      on_exit = function(_, code)
        if t.buf ~= buf then
          return -- an old process from before a restart
        end
        t.exit_code = code
        vim.schedule(function()
          changed(t)
        end)
      end,
    })
  end)
  if job <= 0 then
    vim.api.nvim_buf_delete(buf, { force = true })
    error("loom: could not start " .. shell)
  end
  vim.bo[buf].filetype = "loom"
  vim.b[buf].loom_term = t.id
  t.buf, t.job, t.exit_code, t.port, t.program = buf, job, nil, nil, nil
  watch(t)
  if t.cmd and t.cmd ~= "" then
    vim.fn.chansend(job, t.cmd .. "\r")
  end
end

--- Start a shell, optionally typing `opts.cmd` into it.
---@return loom.Term
function M.new(opts)
  opts = opts or {}
  local t = {
    id = next_id,
    cmd = opts.cmd,
    cwd = opts.cwd or vim.fn.getcwd(),
    activity = false,
    visible = false,
  }
  next_id = next_id + 1
  spawn(t)
  M.terms[t.id] = t
  return t
end

function M.get(id)
  return M.terms[id]
end

function M.running(t)
  return t.exit_code == nil
end

--- Replace the process with a fresh one in a new buffer. Returns the old buffer
--- so the caller can swap windows before it is wiped.
function M.restart(t)
  local old = t.buf
  if M.running(t) then
    pcall(vim.fn.jobstop, t.job)
  end
  spawn(t)
  changed(t)
  return old
end

--- Stop the process and wipe its buffer.
function M.kill(t)
  if M.running(t) then
    pcall(vim.fn.jobstop, t.job)
  end
  -- Forget it first: the wipe below fires BufWipeout, and loom's handler
  -- must not mistake its own kill for a buffer wiped from outside.
  M.terms[t.id] = nil
  if vim.api.nvim_buf_is_valid(t.buf) then
    pcall(vim.api.nvim_buf_delete, t.buf, { force = true })
  end
end

function M.set_visible(t, visible)
  t.visible = visible
  if visible and t.activity then
    t.activity = false
    changed(t)
  end
end

--- Read the terminal's foreground program asynchronously, then call `cb()`.
--- The shell's tty foreground process group names what is running now.
function M.poll(t, cb)
  if not M.running(t) then
    return
  end
  local ok, pid = pcall(vim.fn.jobpid, t.job)
  if not ok or not pid or pid <= 0 then
    return
  end
  vim.system({ "ps", "-o", "tpgid=", "-p", tostring(pid) }, { text = true }, function(r)
    local pgid = tonumber(vim.trim(r.stdout or ""))
    if not pgid or pgid <= 0 then
      return
    end
    vim.system({ "ps", "-o", "comm=", "-p", tostring(pgid) }, { text = true }, function(r2)
      local name = vim.trim(r2.stdout or "")
      name = name:match("([^/]+)$") or name
      if name ~= "" and name ~= t.program then
        t.program = name
        vim.schedule(function()
          changed(t)
          if cb then
            cb()
          end
        end)
      end
    end)
  end)
end

return M
