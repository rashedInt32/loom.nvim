-- The layout tree: splits, removal, rectangles, neighbours, resize, junctions.
local eq = MiniTest.expect.equality
local L = require("loom.layout")

local T = MiniTest.new_set()
local BOX = { row = 0, col = 0, width = 21, height = 11 }

T["split and leaves keep reading order"] = function()
  local t = L.leaf(1)
  t = L.split(t, 1, "vertical", 2)
  t = L.split(t, 2, "horizontal", 3)
  eq(L.leaves(t), { 1, 2, 3 })
  eq(L.contains(t, 3), true)
  eq(L.contains(t, 9), false)
end

T["split leaves the input tree alone"] = function()
  local t = L.leaf(1)
  local t2 = L.split(t, 1, "vertical", 2)
  eq(t, L.leaf(1))
  eq(L.leaves(t2), { 1, 2 })
end

T["remove lifts the sibling and returns nil for the last pane"] = function()
  local t = L.split(L.split(L.leaf(1), 1, "vertical", 2), 2, "horizontal", 3)
  local r = L.remove(t, 2)
  eq(L.leaves(r), { 1, 3 })
  eq(r.dir, "vertical")
  eq(L.remove(L.leaf(1), 1), nil)
  eq(L.leaves(L.remove(r, 1)), { 3 })
end

T["cycle wraps both ways"] = function()
  local t = L.split(L.split(L.leaf(1), 1, "vertical", 2), 2, "vertical", 3)
  eq(L.cycle(t, 3, 1), 1)
  eq(L.cycle(t, 1, -1), 3)
  eq(L.cycle(t, 2, 1), 3)
end

T["rects split side by side with a one-cell separator"] = function()
  local t = L.split(L.leaf(1), 1, "vertical", 2)
  local rects, seps = L.rects(t, BOX)
  eq(rects[1], { row = 0, col = 0, width = 10, height = 11 })
  eq(rects[2], { row = 0, col = 11, width = 10, height = 11 })
  eq(seps, { { row = 0, col = 10, len = 11, dir = "v" } })
end

T["rects stack top and bottom and honour the ratio"] = function()
  local t = L.split(L.leaf(1), 1, "horizontal", 2)
  t.ratio = 0.3
  local rects, seps = L.rects(t, BOX)
  eq(rects[1], { row = 0, col = 0, width = 21, height = 3 })
  eq(rects[2], { row = 4, col = 0, width = 21, height = 7 })
  eq(seps[1], { row = 3, col = 0, len = 21, dir = "h" })
end

T["rects never produce an empty pane in a tiny box"] = function()
  local t = L.split(L.leaf(1), 1, "vertical", 2)
  local rects = L.rects(t, { row = 0, col = 0, width = 2, height = 5 })
  eq(rects[1], { row = 0, col = 0, width = 2, height = 5 })
  eq(rects[2], nil)
end

T["neighbor finds the pane in each direction"] = function()
  -- 1 | 2
  --   | -
  --   | 3
  local t = L.split(L.split(L.leaf(1), 1, "vertical", 2), 2, "horizontal", 3)
  eq(L.neighbor(t, BOX, 1, "l"), 2)
  eq(L.neighbor(t, BOX, 3, "h"), 1)
  eq(L.neighbor(t, BOX, 2, "j"), 3)
  eq(L.neighbor(t, BOX, 3, "k"), 2)
  eq(L.neighbor(t, BOX, 1, "h"), nil)
  eq(L.neighbor(t, BOX, 3, "j"), nil)
end

T["resize moves the nearest matching divider and clamps"] = function()
  local t = L.split(L.split(L.leaf(1), 1, "vertical", 2), 2, "horizontal", 3)
  local r = L.resize(t, 3, "l", 0.1)
  eq(r.ratio, 0.6)
  eq(r.b.ratio, 0.5)
  local s = L.resize(t, 3, "k", 0.1)
  eq(s.ratio, 0.5)
  eq(s.b.ratio, 0.4)
  local far = t
  for _ = 1, 20 do
    far = L.resize(far, 1, "h", 0.1)
  end
  eq(far.ratio, L.MIN_RATIO)
end

T["sep_cells draws a tee where a stacked divider meets a side divider"] = function()
  local t = L.split(L.split(L.leaf(1), 1, "vertical", 2), 2, "horizontal", 3)
  local _, seps = L.rects(t, BOX)
  local cells = L.sep_cells(seps)
  local at = {}
  for _, c in ipairs(cells) do
    at[c.row .. ":" .. c.col] = c.char
  end
  eq(at["0:10"], "│")
  eq(at["5:10"], "├")
  eq(at["5:11"], "─")
  eq(at["5:20"], "─")
end

return T
