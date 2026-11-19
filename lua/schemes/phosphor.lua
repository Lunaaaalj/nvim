-- phosphor: a monochrome CRT. One hue (green P1 by default, amber via the
-- `phosphor-amber` scheme) and brightness as the only syntax axis: the hue at
-- full strength for what matters (keywords, functions), stepping down through
-- strings and text to dim comments. Dark only, like a tube; under "light" it
-- keeps drawing dark and <leader>uB warns. Red is kept for errors because a
-- fault that looks like everything else is a bad fault.
-- Role list: see concrete.lua.
local S = require("schemes")

return function(variant)
  local amber = variant == "amber"
  local hue = amber and "#ffb000" or "#4dff7c"
  local bg = amber and "#100a00" or "#050d07"
  -- hue at `a` strength over the tube's black
  local function t(a) return S.mix(hue, bg, a) end
  local red = "#ff5555"

  return {
    dark = {
      bg = bg, float = t(0.07), sel = t(0.12), visual = t(0.26), line = t(0.34),
      fg = t(0.82), dim = t(0.6),
      accent = hue,
      error = red, warn = amber and "#ffe08a" or "#e8ff6a", info = t(0.7), hint = t(0.45), ok = hue,
      add = hue, change = t(0.65), delete = red,
      syn = {
        comment = { fg = t(amber and 0.64 or 0.54), italic = true },
        string = t(0.68),
        number = { fg = hue },
        constant = { fg = hue, bold = true },
        keyword = { fg = hue, bold = true },
        func = { fg = hue },
        type = t(0.9),
        special = { fg = hue, underline = true },
        operator = t(0.6),
        variable = t(0.82),
        property = t(0.74),
        param = t(0.74),
        preproc = t(0.9),
        delimiter = t(0.55),
      },
      -- the glow: a bright cursor block and a line number you can't miss
      extra = {
        CursorLineNr = { fg = bg, bg = hue, bold = true },
      },
      term = {
        bg, red, t(0.8), t(0.9), t(0.6), t(0.7), t(0.75), t(0.85),
        t(0.34), "#ff8080", hue, t(1.0), t(0.75), t(0.85), t(0.9), t(1.0),
      },
    },
  }
end
