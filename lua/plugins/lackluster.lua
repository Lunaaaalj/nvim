return {
    "slugbyte/lackluster.nvim",
    lazy = false,
    priority = 1000,
    config = function()
        require("lackluster").setup({
            tweak_background = {
                normal = "none", -- transparent editor background
                telescope = "none",
                menu = "none",
                popup = "none",
            },
        })
        -- vim.cmd.colorscheme("lackluster")
        -- vim.cmd.colorscheme("lackluster-hack") -- my favorite
        -- vim.cmd.colorscheme("lackluster-mint")
    end,
}
