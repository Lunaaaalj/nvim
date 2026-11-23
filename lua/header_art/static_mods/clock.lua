-- Hero band: the clock and date (placeholder text clock; the seven-segment
-- display and the "needs you" strip replace it in the next commit).
local U = require("header_art.static_util")

return {
  id = "clock",
  bare = true,
  noflash = true,
  every = 60,
  render = function(w)
    return {
      U.row({ { os.date("%H:%M"), "b acc" } }, {}, w),
      U.row({ { os.date("%A %d %B"):upper(), "b" } }, {}, w),
    }
  end,
}
