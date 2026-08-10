return {
  {
    "quarto-dev/quarto-nvim",
    ft = { "quarto" },
    dependencies = {
      "jmbuhr/otter.nvim",
      "neovim/nvim-lspconfig",
    },
    opts = {
      lspFeatures = {
        -- Per-language LSP (diagnostics/completion/hover) inside .qmd chunks,
        -- delegated to otter.nvim. Execution stays on Molten (see molten.lua /
        -- keymaps.lua), not quarto-nvim's own runner below.
        languages = { "r", "python", "julia", "bash" },
        chunks = "curly", -- ```{r}, ```{python} chunk headers
        diagnostics = { enabled = true, triggers = { "BufWritePost" } },
        completion = { enabled = true },
      },
      codeRunner = {
        -- Cell execution goes through Molten's existing flow (<leader>rc/ra/
        -- rk/rj), which molten_cells() in keymaps.lua now also recognizes for
        -- curly-brace Quarto chunks. Don't stand up a second execution path.
        enabled = false,
      },
    },
  },
  {
    -- quarto-nvim activates otter.nvim itself when lspFeatures is enabled
    -- above; no explicit otter.setup() call needed here.
    "jmbuhr/otter.nvim",
    ft = { "quarto" },
  },
}
