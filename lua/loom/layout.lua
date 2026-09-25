-- The pane layout of one tab: a binary tree of splits over terminal ids.
--
-- Pure data, no Neovim state. Every function returns a new tree and leaves
-- its input alone, so callers can keep the old tree around for zoom and undo.
--
--   leaf  = { kind = "leaf", term = id }
--   split = { kind = "split", dir = "vertical" | "horizontal", ratio, a, b }
--
-- "vertical" follows Vim: panes side by side, a on the left. "horizontal"
-- stacks them, a on top. One cell between them is the separator.
local M = {}

M.MIN_RATIO = 0.1
M.MAX_RATIO = 0.9

function M.leaf(term)
  return { kind = "leaf", term = term }
end

local function map(tree, fn)
  if tree.kind == "leaf" then
    return fn(tree)
  end
  local a, b = map(tree.a, fn), map(tree.b, fn)
  return { kind = "split", dir = tree.dir, ratio = tree.ratio, a = a, b = b }
end

--- Split the pane holding `term`, putting `new_term` after it.
function M.split(tree, term, dir, new_term)
  return map(tree, function(leaf)
    if leaf.term ~= term then
      return leaf
    end
    return { kind = "split", dir = dir, ratio = 0.5, a = M.leaf(term), b = M.leaf(new_term) }
  end)
end

--- Remove the pane holding `term`. Its sibling takes the parent's place.
--- Returns nil when that pane was the whole tree.
function M.remove(tree, term)
  if tree.kind == "leaf" then
    return tree.term ~= term and tree or nil
  end
  local a, b = M.remove(tree.a, term), M.remove(tree.b, term)
  if not a then
    return b
  end
  if not b then
    return a
  end
  return { kind = "split", dir = tree.dir, ratio = tree.ratio, a = a, b = b }
end

--- Terminal ids in reading order.
function M.leaves(tree, out)
  out = out or {}
  if tree.kind == "leaf" then
    out[#out + 1] = tree.term
  else
    M.leaves(tree.a, out)
    M.leaves(tree.b, out)
  end
  return out
end

function M.contains(tree, term)
  return vim.tbl_contains(M.leaves(tree), term)
end

--- The id `delta` places after `term` in reading order, wrapping around.
function M.cycle(tree, term, delta)
  local list = M.leaves(tree)
  for i, id in ipairs(list) do
    if id == term then
      return list[(i - 1 + delta) % #list + 1]
    end
  end
  return list[1]
end

-- Split `size` cells into two parts with one separator cell between them.
local function divide(size, ratio)
  if size < 3 then
    return size, 0
  end
  local first = math.floor((size - 1) * ratio + 0.5)
  first = math.max(1, math.min(size - 2, first))
  return first, size - 1 - first
end

--- Lay the tree out in `box` = { row, col, width, height }.
--- Returns rects keyed by term id, and separators as { row, col, len, dir }.
--- A separator's dir is "v" for a vertical line and "h" for a horizontal one.
function M.rects(tree, box)
  local rects, seps = {}, {}
  local function walk(node, b)
    if node.kind == "leaf" then
      rects[node.term] = b
      return
    end
    if node.dir == "vertical" then
      local wa, wb = divide(b.width, node.ratio)
      if wb == 0 then
        return walk(node.a, b)
      end
      walk(node.a, { row = b.row, col = b.col, width = wa, height = b.height })
      seps[#seps + 1] = { row = b.row, col = b.col + wa, len = b.height, dir = "v" }
      walk(node.b, { row = b.row, col = b.col + wa + 1, width = wb, height = b.height })
    else
      local ha, hb = divide(b.height, node.ratio)
      if hb == 0 then
        return walk(node.a, b)
      end
      walk(node.a, { row = b.row, col = b.col, width = b.width, height = ha })
      seps[#seps + 1] = { row = b.row + ha, col = b.col, len = b.width, dir = "h" }
      walk(node.b, { row = b.row + ha + 1, col = b.col, width = b.width, height = hb })
    end
  end
  walk(tree, box)
  return rects, seps
end

local function overlap(a1, a2, b1, b2)
  return math.max(0, math.min(a2, b2) - math.max(a1, b1))
end

--- The pane next to `term` in direction h, j, k, or l, or nil at the edge.
function M.neighbor(tree, box, term, dir)
  local rects = M.rects(tree, box)
  local cur = rects[term]
  if not cur then
    return nil
  end
  local best, best_gap, best_overlap
  for id, r in pairs(rects) do
    if id ~= term then
      local gap, ov
      if dir == "l" then
        gap, ov = r.col - (cur.col + cur.width), overlap(r.row, r.row + r.height, cur.row, cur.row + cur.height)
      elseif dir == "h" then
        gap, ov = cur.col - (r.col + r.width), overlap(r.row, r.row + r.height, cur.row, cur.row + cur.height)
      elseif dir == "j" then
        gap, ov = r.row - (cur.row + cur.height), overlap(r.col, r.col + r.width, cur.col, cur.col + cur.width)
      else
        gap, ov = cur.row - (r.row + r.height), overlap(r.col, r.col + r.width, cur.col, cur.col + cur.width)
      end
      if gap >= 0 and ov > 0 then
        if not best or gap < best_gap or (gap == best_gap and ov > best_overlap) then
          best, best_gap, best_overlap = id, gap, ov
        end
      end
    end
  end
  return best
end

--- Move the divider nearest `term` in direction h, j, k, or l by `step`.
--- h and l move a side-by-side divider, j and k a stacked one.
function M.resize(tree, term, dir, step)
  step = step or 0.05
  local want = (dir == "h" or dir == "l") and "vertical" or "horizontal"
  local delta = (dir == "h" or dir == "k") and -step or step
  local done = false
  -- Innermost matching split first, so the divider moved is the one touching the pane.
  local function walk(node)
    if node.kind == "leaf" then
      return node, node.term == term
    end
    local a, in_a = walk(node.a)
    local b, in_b = walk(node.b)
    local ratio = node.ratio
    if (in_a or in_b) and not done and node.dir == want then
      ratio = math.max(M.MIN_RATIO, math.min(M.MAX_RATIO, ratio + delta))
      done = true
    end
    return { kind = "split", dir = node.dir, ratio = ratio, a = a, b = b }, in_a or in_b
  end
  return (walk(tree))
end

--- Separator cells with junctions resolved, as { row, col, char, sep }.
--- `sep` is the index of the separator the cell belongs to.
function M.sep_cells(seps)
  local grid = {}
  local function key(r, c)
    return r * 100000 + c
  end
  for i, s in ipairs(seps) do
    for k = 0, s.len - 1 do
      local r, c = s.dir == "v" and s.row + k or s.row, s.dir == "h" and s.col + k or s.col
      local cell = grid[key(r, c)] or { row = r, col = c, sep = i }
      cell[s.dir] = true
      grid[key(r, c)] = cell
    end
  end
  local out = {}
  for _, cell in pairs(grid) do
    local up = grid[key(cell.row - 1, cell.col)]
    local down = grid[key(cell.row + 1, cell.col)]
    local left = grid[key(cell.row, cell.col - 1)]
    local right = grid[key(cell.row, cell.col + 1)]
    -- A cell joins a neighbour only when that neighbour's line runs toward it.
    local u = cell.v or (up and up.v) or false
    local d = cell.v or (down and down.v) or false
    local l = cell.h or (left and left.h) or false
    local r = cell.h or (right and right.h) or false
    local char
    if u and d and l and r then
      char = "┼"
    elseif u and d and r then
      char = "├"
    elseif u and d and l then
      char = "┤"
    elseif l and r and d then
      char = "┬"
    elseif l and r and u then
      char = "┴"
    elseif u or d then
      char = "│"
    else
      char = "─"
    end
    out[#out + 1] = { row = cell.row, col = cell.col, char = char, sep = cell.sep }
  end
  table.sort(out, function(x, y)
    return x.row == y.row and x.col < y.col or x.row < y.row
  end)
  return out
end

return M
