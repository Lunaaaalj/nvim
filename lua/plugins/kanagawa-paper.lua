-- Kanagawa, desaturated and warmer: ink on aged paper. `:colorscheme
-- kanagawa-paper` follows 'background' (ink dark, canvas light);
-- kanagawa-paper-ink / -canvas pin a variant.
return {
    "thesimonho/kanagawa-paper.nvim",
    lazy = false,
    priority = 1000,
    config = function()
        require("kanagawa-paper").setup({
            transparent = vim.g.ui_transparent, -- do not set background color (<leader>ub)
        })
    end,
}
