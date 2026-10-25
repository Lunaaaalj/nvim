-- Muted rose / gold / pine on a dusky base; the warmest of the polished themes.
-- `:colorscheme rose-pine` follows 'background' (main dark, dawn light);
-- rose-pine-main / -moon / -dawn pin a variant.
return {
    "rose-pine/neovim",
    name = "rose-pine",
    lazy = false,
    priority = 1000,
    config = function()
        require("rose-pine").setup({
            variant = "auto", -- follow 'background' (<leader>uB)
            dark_variant = "main", -- "main" (warmer) | "moon" (cooler)
            styles = {
                transparency = vim.g.ui_transparent, -- <leader>ub
            },
        })
    end,
}
