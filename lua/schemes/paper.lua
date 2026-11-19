-- paper: ink on a printed page. Near-white and near-black, no accent: the
-- hierarchy is italics, bold and four steps of grey, like a typeset book. The
-- dark variant is the same page at night (warm off-white on charcoal), so
-- <leader>uB changes the light, not the character. Colour only for faults.
-- Role list: see concrete.lua.
return {
  light = {
    bg = "#f6f6f4", float = "#ededeb", sel = "#e6e6e3", visual = "#d4d4d0", line = "#a8a8a4",
    fg = "#1c1c1c", dim = "#6a6a66",
    accent = "#000000",
    error = "#a02828", warn = "#8a6a10", info = "#444444", hint = "#6a6a66", ok = "#3a6a3a",
    add = "#3a6a3a", change = "#8a6a10", delete = "#a02828",
    syn = {
      comment = { fg = "#6a6a66", italic = true },
      string = "#3d3d3a",
      number = "#1c1c1c",
      constant = "#1c1c1c",
      keyword = { fg = "#000000", bold = true },
      func = "#000000",
      type = "#2e2e2c",
      special = { fg = "#000000", italic = true },
      operator = "#55554f",
      variable = "#1c1c1c",
      property = "#333331",
      param = { fg = "#333331", italic = true },
      preproc = "#3d3d3a",
      delimiter = "#74746e",
    },
    term = {
      "#1c1c1c", "#a02828", "#3a6a3a", "#8a6a10", "#444444", "#6a6a66", "#55554f", "#d4d4d0",
      "#3d3d3a", "#c04040", "#4a8a4a", "#a8820f", "#5a5a56", "#74746e", "#6a6a66", "#000000",
    },
  },
  dark = {
    bg = "#1f1f1e", float = "#272726", sel = "#2f2f2e", visual = "#403f3e", line = "#55554f",
    fg = "#e4e3df", dim = "#92918d",
    accent = "#ffffff",
    error = "#d88a80", warn = "#d0b878", info = "#b0afab", hint = "#92918d", ok = "#98b898",
    add = "#98b898", change = "#d0b878", delete = "#d88a80",
    syn = {
      comment = { fg = "#8c8b87", italic = true },
      string = "#bfbeba",
      number = "#e4e3df",
      constant = "#e4e3df",
      keyword = { fg = "#ffffff", bold = true },
      func = "#ffffff",
      type = "#cfcec9",
      special = { fg = "#ffffff", italic = true },
      operator = "#a09f9b",
      variable = "#e4e3df",
      property = "#d4d3cf",
      param = { fg = "#d4d3cf", italic = true },
      preproc = "#bfbeba",
      delimiter = "#85847f",
    },
    term = {
      "#1f1f1e", "#d88a80", "#98b898", "#d0b878", "#a8a7a3", "#bfbeba", "#b0afab", "#e4e3df",
      "#55554f", "#e8a49a", "#b0d0b0", "#e0cc90", "#c0bfbb", "#d4d3cf", "#cccbc7", "#ffffff",
    },
  },
}
