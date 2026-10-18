-- Minimal: peach / orange accents on near-black. Dark only, so <leader>uB
-- warns instead of switching.
return {
    "datsfilipe/vesper.nvim",
    lazy = false,
    priority = 1000,
    config = function()
        require("vesper").setup({
            transparent = vim.g.ui_transparent, -- <leader>ub
        })
    end,
}
