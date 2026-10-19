-- loom: a floating terminal that behaves like a small tmux.
local config = require("loom.config")
local highlights = require("loom.highlights")
local layout = require("loom.layout")
local state = require("loom.state")
local term = require("loom.term")
local ui = require("loom.ui")

local M = {}

M.current = nil -- name of the session on screen
local last_root = nil
local poll_timer = nil
local render_queued = false
local listening = false

local function session()
  return M.current and state.sessions[M.current] or nil
end

-- Coalesce bursts of terminal events into one redraw.
local function queue_render()
  if render_queued or not ui.visible then
    return
  end
  render_queued = true
  vim.schedule(function()
    render_queued = false
    local s = session()
    if ui.visible and s then
      ui.render(s)
    end
  end)
end

local function start_poll()
  if poll_timer then
    return
  end
  poll_timer = vim.uv.new_timer()
  poll_timer:start(
    0,
    config.options.poll_ms,
    vim.schedule_wrap(function()
      if not ui.visible then
        poll_timer:stop()
        poll_timer:close()
        poll_timer = nil
        return
      end
      for id in pairs(ui.panes) do
        local t = term.get(id)
        if t then
          term.poll(t)
        end
      end
    end)
  )
end

--- Show the float. Opens the project's session, and a first shell if empty.
function M.show()
  local root = state.root_of()
  if not M.current or root ~= last_root then
    M.current = state.for_cwd().name
    last_root = root
  end
  local s = session()
  if #s.tabs == 0 then
    state.new_tab(s)
  end
  ui.render(s, { focus = true })
  -- Set @loom (and the sluice handoff) again even if loom thinks it is set:
  -- something outside may have cleared it, and opening loom is when the
  -- prefix must work.
  ui.sync_prefix(false, true)
  start_poll()
end

function M.hide()
  if ui.visible then
    ui.hide()
  end
end

function M.toggle()
  if ui.visible then
    M.hide()
  else
    M.show()
  end
end

-- Every action below redraws and puts the cursor back in the active pane.
local function refresh(insert)
  local s = session()
  if not s or #s.tabs == 0 then
    return M.hide()
  end
  ui.render(s, { focus = true, insert = insert })
end

function M.new_tab(opts)
  if not ui.visible then
    M.show()
  end
  state.new_tab(session(), opts)
  refresh()
end

function M.split(dir, opts)
  if not ui.visible then
    M.show()
  end
  state.split(session(), dir, opts)
  refresh()
end

function M.goto_tab(i)
  local s = session()
  if s and s.tabs[i] then
    s.active = i
    refresh()
  end
end

function M.cycle_tab(delta)
  local s = session()
  if s and #s.tabs > 0 then
    s.active = (s.active - 1 + delta) % #s.tabs + 1
    refresh()
  end
end

function M.move(dir)
  local s = session()
  local tab = s and state.tab(s)
  if not tab or tab.zoomed then
    return
  end
  local id = layout.neighbor(tab.layout, ui.geom.box, tab.active, dir)
  if id then
    tab.active = id
    refresh()
  end
end

function M.next_pane()
  local s = session()
  local tab = s and state.tab(s)
  if tab then
    tab.zoomed = false
    tab.active = layout.cycle(tab.layout, tab.active, 1)
    refresh()
  end
end

function M.resize(dir)
  local tab = session() and state.tab(session())
  if tab and not tab.zoomed then
    tab.layout = layout.resize(tab.layout, tab.active, dir, 0.05)
    refresh()
  end
end

function M.zoom()
  local tab = session() and state.tab(session())
  if tab and #layout.leaves(tab.layout) > 1 then
    tab.zoomed = not tab.zoomed
    refresh()
  end
end

function M.close_pane()
  local s = session()
  local tab = s and state.tab(s)
  if tab then
    state.close_pane(s, tab.active)
    refresh()
  end
end

function M.close_tab()
  local s = session()
  if s and s.active > 0 then
    state.close_tab(s, s.active)
    refresh()
  end
end

function M.restart()
  local tab = session() and state.tab(session())
  local t = tab and term.get(tab.active)
  if t then
    local old = term.restart(t)
    refresh()
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(old) then
        pcall(vim.api.nvim_buf_delete, old, { force = true })
      end
    end)
  end
end

function M.rename()
  local s = session()
  local tab = s and state.tab(s)
  if not tab then
    return
  end
  ui.prompting = true
  vim.ui.input({ prompt = "Tab name: ", default = tab.name or state.label(tab, s.root) }, function(name)
    ui.prompting = false
    if name ~= nil then
      tab.name = vim.trim(name) ~= "" and vim.trim(name) or nil
    end
    vim.schedule(refresh)
  end)
end

--- Show a session by name, creating it rooted at the current project.
function M.session(name)
  local s = state.session(name, state.root_of())
  M.current = s.name
  if #s.tabs == 0 then
    state.new_tab(s)
  end
  ui.render(s, { focus = true })
  start_poll()
end

function M.pick_session()
  local names = vim.deepcopy(state.order)
  ui.prompting = true
  vim.ui.select(names, {
    prompt = "loom session",
    format_item = function(name)
      local s = state.sessions[name]
      local mark = name == M.current and "● " or "  "
      return ("%s%s  (%d tab%s)"):format(mark, name, #s.tabs, #s.tabs == 1 and "" or "s")
    end,
  }, function(name)
    ui.prompting = false
    vim.schedule(function()
      if name then
        M.session(name)
      else
        refresh()
      end
    end)
  end)
end

function M.new_session()
  ui.prompting = true
  vim.ui.input({ prompt = "New session: " }, function(name)
    ui.prompting = false
    vim.schedule(function()
      if name and vim.trim(name) ~= "" then
        M.session(vim.trim(name))
      else
        refresh()
      end
    end)
  end)
end

function M.scroll_mode()
  vim.cmd("stopinsert")
end

function M.help()
  require("loom.help").open()
end

local function on_term_change(t)
  -- A shell that exits cleanly closes its pane, as in tmux. A failure stays
  -- on screen so its output can be read.
  if t.exit_code == 0 then
    local s = state.find(t.id)
    if s then
      state.close_pane(s, t.id)
      if ui.visible and s.name == M.current then
        refresh()
      end
      return
    end
  end
  if t.exit_code ~= nil and ui.visible and ui.current_pane() == t.id then
    vim.cmd("stopinsert") -- a key in terminal mode would wipe the exited buffer
  end
  queue_render()
end

local function autocmds()
  local group = vim.api.nvim_create_augroup("loom", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = highlights.set })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if ui.visible then
        refresh(vim.api.nvim_get_mode().mode == "t")
      end
    end,
  })
  -- Keep tmux's @loom and sluice's handoff in step with focus, including
  -- focus loom did not move.
  vim.api.nvim_create_autocmd({ "WinEnter", "FocusGained" }, {
    group = group,
    callback = function()
      vim.schedule(ui.sync_prefix)
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      ui.sync_prefix(true)
    end,
  })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      if not ui.visible or ui.moving or ui.hiding or ui.prompting then
        return
      end
      local win = vim.api.nvim_get_current_win()
      local s = session()
      if win == ui.frame.win then
        -- A click on the frame: switch tab if it hit one, then go back to the pane.
        local i = ui.tab_at_mouse(vim.fn.getmousepos())
        vim.schedule(function()
          if i then
            M.goto_tab(i)
          else
            refresh()
          end
        end)
        return
      end
      local id = vim.w[win].loom_pane
      if id and s then
        local tab = state.tab(s)
        if tab and tab.active ~= id then
          tab.active = id
          queue_render()
        end
        return
      end
      if ui.pane_closed then
        -- Neovim moved focus here only because a loom pane's window closed,
        -- as it does when a shell exits. Put focus back instead of hiding.
        ui.pane_closed = false
        vim.schedule(function()
          if ui.visible then
            refresh()
          end
        end)
        return
      end
      if config.options.hide_on_leave then
        -- Decide when the hide runs, not now. Focus can pass through the
        -- editor for a moment, as when an exited pane's window closes and
        -- loom then refocuses a sibling pane; that is not leaving.
        vim.schedule(function()
          if ui.visible and not ui.prompting and not ui.is_loom_win(vim.api.nvim_get_current_win()) then
            M.hide()
          end
        end)
      end
    end,
  })
  -- Remember when a loom pane's window closes outside loom's own redraw, so
  -- the focus jump that follows is not taken as leaving the float.
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      local win = tonumber(ev.match)
      if not ui.visible or ui.moving or ui.hiding or not win then
        return
      end
      for _, pane_win in pairs(ui.panes) do
        if pane_win == win then
          ui.pane_closed = true
          return
        end
      end
    end,
  })
  -- A terminal buffer wiped from outside loom takes its pane with it.
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      local id = vim.b[ev.buf].loom_term
      local t = id and term.get(id)
      if t and t.buf == ev.buf then
        term.terms[id] = nil
        local s = state.find(id)
        if s then
          vim.schedule(function()
            state.close_pane(s, id)
            if ui.visible and s.name == M.current then
              refresh()
            end
          end)
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "loom",
    callback = function(ev)
      require("loom.keys").attach(ev.buf)
    end,
  })
end

function M.setup(opts)
  config.setup(opts)
  highlights.set()
  autocmds()
  if not listening then
    term.on_change(on_term_change)
    listening = true
  end
  for _, lhs in ipairs(config.options.toggle or {}) do
    vim.keymap.set({ "n", "t", "i", "v" }, lhs, M.toggle, { desc = "loom: toggle terminal" })
  end
end

return M
