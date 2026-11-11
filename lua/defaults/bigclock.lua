-- Big block-digit clock for the dashboard.
--
-- Each digit is a 5-row bitmap; one "pixel" is drawn as two cells (`px`) because
-- a terminal cell is about twice as tall as it is wide, so 2-cell pixels keep the
-- digits upright instead of tall and thin. `render("14:32")` returns the 5 text
-- rows; colour comes from the caller (the dashboard section uses DashboardAccent).

local M = {}

local glyphs = {
  ["0"] = { "███", "█ █", "█ █", "█ █", "███" },
  ["1"] = { " █ ", "██ ", " █ ", " █ ", "███" },
  ["2"] = { "███", "  █", "███", "█  ", "███" },
  ["3"] = { "███", "  █", "███", "  █", "███" },
  ["4"] = { "█ █", "█ █", "███", "  █", "  █" },
  ["5"] = { "███", "█  ", "███", "  █", "███" },
  ["6"] = { "███", "█  ", "███", "█ █", "███" },
  ["7"] = { "███", "  █", "  █", "  █", "  █" },
  ["8"] = { "███", "█ █", "███", "█ █", "███" },
  ["9"] = { "███", "█ █", "███", "  █", "███" },
  [":"] = { " ", "█", " ", "█", " " },
}

M.height = 5

---@param str string  digits and colons, e.g. "14:32"
---@param opts? { px?: string, gap?: string }
---@return string[] rows
function M.render(str, opts)
  opts = opts or {}
  local px = opts.px or "██"
  local blank = (" "):rep(vim.api.nvim_strwidth(px))
  local gap = opts.gap or "  "
  local rows = {}
  for r = 1, M.height do
    local parts = {}
    for ch in str:gmatch(".") do
      local g = glyphs[ch]
      if g then
        local line = g[r]:gsub("█", "\0"):gsub(" ", "\1")
        parts[#parts + 1] = (line:gsub("%z", px):gsub("\1", blank))
      end
    end
    rows[r] = table.concat(parts, gap)
  end
  -- Snacks centres each row by its full string width, blank cells included, but
  -- the glyphs carry empty pixel columns (the "1" has one on its left), so the
  -- visible digits sat off-centre against the date. Strip the margin every row
  -- shares so the box is the ink; all rows lose the same amount, staying equal.
  if opts.trim ~= false then
    local lead, trail = math.huge, math.huge
    for _, row in ipairs(rows) do
      lead = math.min(lead, (row:find("[^ ]") or #row + 1) - 1)
      trail = math.min(trail, #row:match(" *$"))
    end
    for r, row in ipairs(rows) do rows[r] = row:sub(lead + 1, #row - trail) end
  end
  return rows
end

return M
