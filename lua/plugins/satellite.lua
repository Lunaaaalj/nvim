-- Minimal scrollbar with ambient marks: git changes, diagnostics, search hits,
-- and cursor position — context without taking up a column.
return {
  "lewis6991/satellite.nvim",
  event = { "BufReadPost", "BufNewFile" },
  opts = {
    current_only = false,
    winblend = 50,
    handlers = {
      cursor = { enable = true },
      search = { enable = true },
      diagnostic = { enable = true },
      gitsigns = { enable = true },
      marks = { enable = true },
    },
  },
}
