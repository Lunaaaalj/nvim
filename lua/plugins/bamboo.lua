-- Warm greens and browns, softer than everforest. `:colorscheme bamboo`
-- follows 'background' (vulgaris dark, light light); bamboo-multiplex is the
-- greener dark style. Options live in vim.g.bamboo_config, so they survive the
-- module reset bamboo's colors file does on every load.
return {
    "ribru17/bamboo.nvim",
    lazy = false,
    priority = 1000,
    config = function()
        require("bamboo").setup({
            transparent = vim.g.ui_transparent, -- don't set background (<leader>ub)
        })
    end,
}
