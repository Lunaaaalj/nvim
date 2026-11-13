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
        -- ```{r} chunks and plain ```python fences: notebooks (.ipynb) open
        -- as quarto with jupytext's plain fences (jupytext.lua)
        chunks = "all",
        diagnostics = { enabled = true, triggers = { "BufWritePost" } },
        completion = { enabled = true },
      },
      codeRunner = {
        -- Cells run through Molten (lua/notebook/, <leader>m...), which
        -- reads curly and plain fences. Don't stand up a second execution path.
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
