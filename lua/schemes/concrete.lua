-- concrete: brutalist. Raw grey, hard contrast, ONE signal colour.
-- Hierarchy comes from weight and brightness (keywords bold, comments dim,
-- strings a step down), never from hue; the accent is spent only on what you
-- act on: functions, the cursor line number, search, TODOs. Real hues appear
-- only where meaning demands them (diagnostics, git). No italics anywhere.
--
-- Palette roles (every scheme in lua/schemes/ fills the same ones):
--   bg float sel visual line   surfaces, darkest to most prominent
--   fg dim                     text, line numbers / secondary
--   accent                     the one colour the UI points with
--   error warn info hint ok    diagnostics
--   add change delete          git / diff
--   syn.*                      comment string number constant keyword func type
--                              special operator variable property param preproc
--                              delimiter: `{ fg, bold, italic, … }` or a colour
--   term                       the 16 `:terminal` colours
--   search_bg (optional), extra (optional group overrides)
local pal = {
  dark = {
    bg = "#161616", float = "#1e1e1e", sel = "#262626", visual = "#3b3b3b", line = "#4d4d4d",
    fg = "#e6e6e1", dim = "#85857d",
    accent = "#ff6a00",
    error = "#ff3030", warn = "#ffd400", info = "#b8b8b2", hint = "#85857d", ok = "#9acd6f",
    add = "#8fbf6a", change = "#d9b84a", delete = "#ff3030",
    syn = {
      comment = "#82827a",
      string = "#b0b0a8",
      number = { fg = "#ffffff" },
      constant = { fg = "#ffffff" },
      keyword = { fg = "#ffffff", bold = true },
      func = "#ff6a00",
      type = "#cfcfc8",
      special = "#ff6a00",
      operator = "#a0a098",
      variable = "#e6e6e1",
      property = "#cfcfc8",
      param = "#cfcfc8",
      preproc = { fg = "#cfcfc8", bold = true },
      delimiter = "#8a8a82",
    },
    term = {
      "#161616", "#ff3030", "#9acd6f", "#ffd400", "#9a9a92", "#c4c4bd", "#b0b0a8", "#d6d6d0",
      "#4d4d4d", "#ff6a60", "#b6e08a", "#ffe45c", "#bcbcb4", "#dcdcd6", "#cfcfc8", "#ffffff",
    },
  },
  light = {
    bg = "#dddad3", float = "#e8e5de", sel = "#d0ccc3", visual = "#bdb8ac", line = "#8a867c",
    fg = "#151515", dim = "#6a665c",
    accent = "#c04200",
    error = "#c40000", warn = "#8f6a00", info = "#444444", hint = "#6a665c", ok = "#3f7d1f",
    add = "#3f7d1f", change = "#8f6a00", delete = "#c40000",
    syn = {
      comment = "#655f55",
      string = "#4a4640",
      number = { fg = "#000000" },
      constant = { fg = "#000000" },
      keyword = { fg = "#000000", bold = true },
      func = "#b83c00",
      type = "#2a2824",
      special = "#b83c00",
      operator = "#555249",
      variable = "#151515",
      property = "#2a2824",
      param = "#2a2824",
      preproc = { fg = "#2a2824", bold = true },
      delimiter = "#6a665c",
    },
    term = {
      "#151515", "#c40000", "#3f7d1f", "#8f6a00", "#444444", "#6a665c", "#555249", "#bdb8ac",
      "#3a3a3a", "#e03030", "#4f9a28", "#a87e00", "#5a5a5a", "#7a766c", "#6a665c", "#000000",
    },
  },
}

-- `vim.g.concrete_accent = false` (set before `:colorscheme concrete`) drops
-- the signal orange: the accent becomes the brightest ink, so functions,
-- search and the cursor line number are picked out by weight alone.
if vim.g.concrete_accent == false then
  for mode, hi in pairs({ dark = "#ffffff", light = "#000000" }) do
    local p = pal[mode]
    p.accent, p.syn.func, p.syn.special = hi, hi, hi
  end
end

return pal
