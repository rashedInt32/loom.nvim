-- A grid of screen cells, turned into buffer lines and highlight ranges.
--
-- Box-drawing characters and Nerd Font icons take several bytes but one cell,
-- so positions are kept in cells and converted to bytes only at the end.
local M = {}
M.__index = M

function M.new(width, height, hl)
  local self = setmetatable({ width = width, height = height, rows = {} }, M)
  for r = 0, height - 1 do
    local row = {}
    for c = 0, width - 1 do
      row[c] = { ch = " ", hl = hl }
    end
    self.rows[r] = row
  end
  return self
end

local CHAR = "[%z\1-\127\194-\244][\128-\191]*"

--- Write `text` at cell (row, col). Returns the column after the text.
function M:put(row, col, text, hl)
  local cells = self.rows[row]
  if not cells then
    return col
  end
  for ch in text:gmatch(CHAR) do
    local w = vim.fn.strdisplaywidth(ch)
    if w < 1 then
      w = 1
    end
    if col + w > self.width then
      break
    end
    if col >= 0 then
      cells[col] = { ch = ch, hl = hl }
      for k = 1, w - 1 do
        cells[col + k] = { ch = "", hl = hl }
      end
    end
    col = col + w
  end
  return col
end

--- Draw a list of { text, hl } segments from `col`. Returns the end column.
function M:segments(row, col, segs)
  for _, s in ipairs(segs) do
    col = self:put(row, col, s[1], s[2])
  end
  return col
end

--- Display width of a segment list.
function M.width_of(segs)
  local w = 0
  for _, s in ipairs(segs) do
    w = w + vim.fn.strdisplaywidth(s[1])
  end
  return w
end

--- Lines, plus { row, col_start, col_end, hl } byte ranges.
function M:render()
  local lines, marks = {}, {}
  for r = 0, self.height - 1 do
    local parts, byte = {}, 0
    local run_hl, run_start
    local row = self.rows[r]
    for c = 0, self.width - 1 do
      local cell = row[c]
      if cell.hl ~= run_hl then
        if run_hl then
          marks[#marks + 1] = { r, run_start, byte, run_hl }
        end
        run_hl, run_start = cell.hl, byte
      end
      parts[#parts + 1] = cell.ch
      byte = byte + #cell.ch
    end
    if run_hl then
      marks[#marks + 1] = { r, run_start, byte, run_hl }
    end
    lines[r + 1] = table.concat(parts)
  end
  return lines, marks
end

--- Write the canvas into `buf`, replacing its text and loom highlights.
function M:flush(buf, ns)
  local lines, marks = self:render()
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
end

return M
