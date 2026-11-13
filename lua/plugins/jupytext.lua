return {
  "GCBallesteros/jupytext.nvim",
  config = function()
      require("jupytext").setup({
    -- NOTE: this plugin invokes a bare `jupytext` from PATH: install it as a
    -- uv tool (`uv tool install jupytext`, lands in ~/.local/bin).
    style = "markdown",
    output_extension = "md",
    force_ft = "markdown",
})
  end
}
