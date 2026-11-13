return {
  "GCBallesteros/jupytext.nvim",
  config = function()
    -- jupytext.nvim calls a bare `jupytext` from PATH: install it as a uv
    -- tool (`uv tool install jupytext`, lands in ~/.local/bin).
    require("jupytext").setup({
      -- The text is jupytext's Markdown (```python fences): it round-trips
      -- losslessly. Its "quarto" format does not: the first `# Heading`
      -- became `title:` front matter and was written back into the .ipynb as
      -- a raw YAML markdown cell (issue #40).
      style = "markdown",
      output_extension = "md",
      -- ...but the buffer is a Quarto one, so otter gives LSP inside cells
      -- (quarto.lua, chunks = "all") and the Markdown-only tooling
      -- (render-markdown, prettier, the <leader>pv preview) stays away.
      force_ft = "quarto",
    })
  end,
}
