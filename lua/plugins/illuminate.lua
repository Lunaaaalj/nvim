-- Softly highlights other occurrences of the word under the cursor (via LSP /
-- treesitter / regex, in that order).
return {
  "RRethy/vim-illuminate",
  event = { "BufReadPost", "BufNewFile" },
  config = function()
    require("illuminate").configure({
      providers = { "lsp", "treesitter", "regex" },
      delay = 120,
      under_cursor = true,
      -- Don't light up in noisy / special buffers.
      filetypes_denylist = {
        "neo-tree",
        "Trouble",
        "trouble",
        "lazy",
        "mason",
        "snacks_dashboard",
        "oil",
        "TelescopePrompt",
      },
    })
  end,
}
