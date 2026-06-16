-- Ghostly hints showing where motions (w, e, b, $, ^, ...) would land. Off by
-- default; toggle with <leader>up. Quietly teaches motions by osmosis.
return {
  "tris203/precognition.nvim",
  event = "VeryLazy",
  opts = {
    startVisible = false,
  },
  keys = {
    { "<leader>up", "<cmd>Precognition toggle<cr>", desc = "Toggle precognition hints" },
  },
}
