return {
    {
        "catppuccin/nvim", name = "catppuccin", priority = 1000,
        config = function()
            require("catppuccin").setup({
            transparent_background = vim.g.ui_transparent,
            term_colors = true,
            })
        end
}
    }
