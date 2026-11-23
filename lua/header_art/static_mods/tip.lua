-- A key from the cheatsheet, one per day (stable all day, so it never redraws).
local U = require("header_art.static_util")

local function pick()
  local ok, cs = pcall(require, "defaults.cheatsheet")
  if not ok or not cs.sections then return nil end
  local flat = {}
  for _, sec in ipairs(cs.sections) do
    for _, row in ipairs(sec[2]) do flat[#flat + 1] = { sec[1], row[1], row[2] } end
  end
  if #flat == 0 then return nil end
  local day = tonumber(os.date("%j")) + tonumber(os.date("%Y")) * 366
  return flat[(day * 7919) % #flat + 1]
end

return {
  id = "tip",
  title = "TIP",
  available = function() return pick() ~= nil end,
  render = function(w)
    local t = pick()
    if not t then return {} end
    return { U.row({ { t[2], "acc" } }, { { t[1], "dim" } }, w), U.line({ { t[3], "" } }) }
  end,
}
