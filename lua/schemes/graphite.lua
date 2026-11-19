-- graphite: pencil on dark paper. Greys only and NO accent: the "accent" is
-- the brightest ink, so search, the cursor line number and functions are
-- picked out by brightness, weight and inversion, never by hue. Colour exists
-- only where a fault must be seen (diagnostics, git), kept muted. Dark only.
-- Role list: see concrete.lua.
return {
  dark = {
    bg = "#1a1a1a", float = "#212121", sel = "#292929", visual = "#3a3a3a", line = "#4a4a4a",
    fg = "#cfcfcf", dim = "#8a8a8a",
    accent = "#f2f2f2",
    error = "#d08080", warn = "#c8b070", info = "#a0a0a0", hint = "#8a8a8a", ok = "#90b090",
    add = "#8aa88a", change = "#b8a878", delete = "#c88080",
    syn = {
      comment = { fg = "#858585", italic = true },
      string = "#a0a0a0",
      number = "#dcdcdc",
      constant = "#dcdcdc",
      keyword = { fg = "#f2f2f2", bold = true },
      func = "#f2f2f2",
      type = "#b8b8b8",
      special = { fg = "#f2f2f2", italic = true },
      operator = "#8f8f8f",
      variable = "#cfcfcf",
      property = "#bdbdbd",
      param = { fg = "#bdbdbd", italic = true },
      preproc = "#a8a8a8",
      delimiter = "#7c7c7c",
    },
    term = {
      "#1a1a1a", "#d08080", "#90b090", "#c8b070", "#9a9a9a", "#b0b0b0", "#a8a8a8", "#cfcfcf",
      "#4a4a4a", "#e09a9a", "#a8c8a8", "#dccb90", "#b4b4b4", "#c8c8c8", "#c0c0c0", "#f2f2f2",
    },
  },
}
