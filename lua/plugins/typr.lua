-- Typing practice inside Neovim: a monkeytype-style drill plus a stats
-- dashboard (WPM/accuracy history), both rendered by nvzone/volt.
return {
  "nvzone/typr",
  dependencies = "nvzone/volt",
  cmd = { "Typr", "TyprStats" },
  keys = {
    { "<leader>ty", "<cmd>Typr<cr>", desc = "Typing practice (typr)" },
    { "<leader>tY", "<cmd>TyprStats<cr>", desc = "Typing stats (typr)" },
  },
  opts = {},
}
