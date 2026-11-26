-- Ámbar Glass: the kitty profile's palette as two schemes, developed in its own
-- repo (~/Downloads/GitHub/ambar-glass.nvim; README / :help ambar).
-- `ambar-cielo` (dark, drawn for the kitty glass), `ambar-papel` (light paper),
-- `ambar-glass` (either, following 'background').
--
-- Papel stays opaque under <leader>ub's transparent mode: dark ink over the
-- dark glass is unreadable. defaults/colors.lua's transparent() asks
-- require("ambar").opaque(), so the strip autocmd, cursorline, bufferline,
-- neo-tree and the dashboard art treat it as solid mode.
return {
    dir = vim.fn.expand("~/Downloads/GitHub/ambar-glass.nvim"),
    name = "ambar-glass.nvim",
    lazy = false,
    priority = 1000,
    config = function()
        require("ambar").setup({
            transparent = function() return vim.g.ui_transparent end, -- <leader>ub
        })
    end,
}
