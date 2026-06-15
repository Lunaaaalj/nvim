return {
  "GCBallesteros/jupytext.nvim",
  config = function()
      require("jupytext").setup({
    -- NOTE: this plugin invokes a bare `jupytext` from PATH; the neovim venv's
    -- bin is prepended to PATH in lua/defaults/init.lua so it resolves.
    style = "markdown",
    output_extension = "md",
    force_ft = "markdown",
})
  end
}
