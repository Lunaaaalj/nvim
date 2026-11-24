-- The last 12 weeks of GitHub contributions as a small heat map.
local U = require("header_art.static_util")

local LEVEL = { { "·", "faint" }, { "░", "dim" }, { "▒", "mid" }, { "▓", "acc" }, { "█", "acc b" } }

local function days()
  local ok, d = pcall(function() return require("defaults.dashboard_data").stats() end)
  return ok and type(d) == "table" and d.days or nil
end

return {
  id = "activity",
  title = "ACTIVITY",
  on = { "User DashboardDataChanged" },
  available = function() return days() ~= nil end,
  render = function(w)
    local ds = days() or {}
    local mx, total = 1, 0
    for _, d in ipairs(ds) do mx, total = math.max(mx, d.count), total + d.count end
    -- grid[weekday 1=Mon..7=Sun][week]
    local grid, weeks, col, last_wd = {}, 12, 1, nil
    for r = 1, 7 do grid[r] = {} end
    local cols = {}
    for _, d in ipairs(ds) do
      local y, m, dd = d.date:match("(%d+)-(%d+)-(%d+)")
      local wd = (tonumber(os.date("%w", os.time({ year = y, month = m, day = dd, hour = 12 }))) + 6) % 7 + 1
      if last_wd and wd < last_wd then col = col + 1 end
      last_wd = wd
      grid[wd][col] = d.count
      cols[col] = true
    end
    local ncol = col
    local first = math.max(1, ncol - weeks + 1)
    local names = { "Mo", "", "We", "", "Fr", "", "" }
    local out = {}
    for r = 1, 7 do
      local segs = { { (names[r] .. "  "):sub(1, 3), "dim" } }
      for c = first, ncol do
        local v = grid[r][c]
        local lv = v == nil and 1 or (v == 0 and 1 or math.min(5, 1 + math.ceil(v / mx * 4)))
        segs[#segs + 1] = { LEVEL[lv][1] .. " ", LEVEL[lv][2] }
      end
      out[#out + 1] = U.line(segs)
    end
    out[#out + 1] = U.line({ { "12 weeks · ", "dim" }, { tostring(total), "mid" }, { " contributions", "dim" } })
    return out
  end,
}
