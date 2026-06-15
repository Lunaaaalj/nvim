return {
    {
        'nvim-treesitter/nvim-treesitter',
        lazy = false,
        build = ':TSUpdate',
        config = function()
            require("nvim-treesitter").setup({
                ensure_installed = {
                    "lua", "vim", "vimdoc", "bash",
                    "python", "cpp", "c",
                    "markdown", "markdown_inline",
                },
                parser_install_dir = vim.fn.stdpath("data") .. "/parsers",
                highlight = {
        enable = true,
        -- disable legacy vim regex highlighting when treesitter is active
        additional_vim_regex_highlighting = false,
    },
            })
        end,
    }
}
