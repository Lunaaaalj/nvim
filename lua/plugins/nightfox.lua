return {
    "EdenEast/nightfox.nvim",
    config = function()
        require("nightfox").setup({
            options = {
                transparent = vim.g.ui_transparent, -- disable setting the background color (<leader>ub)
            },
        })
    end,
}
