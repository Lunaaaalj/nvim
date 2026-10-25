return {
    "rebelot/kanagawa.nvim",
    config = function()
        require("kanagawa").setup({
            transparent = vim.g.ui_transparent, -- do not set a background color (<leader>ub)
        })
    end,
}
