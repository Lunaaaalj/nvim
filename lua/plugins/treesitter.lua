return {
    {
        'nvim-treesitter/nvim-treesitter',
        lazy = false,
        build = ':TSUpdate',
        config = function()
      -- Optional: set install directory (defaults are fine too)
      require("nvim-treesitter").setup({
        install_dir = vim.fn.stdpath("data") .. "/site",
      })

      -- Install parsers you want
      require("nvim-treesitter").install({
        "lua",
        "vim",
        "vimdoc",
        "bash",
        "python",
        "cpp",
        "c",
        "markdown",
        "markdown_inline",
      })
    end,
  },
    
}
