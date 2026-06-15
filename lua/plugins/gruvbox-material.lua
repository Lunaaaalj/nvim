-- Warm retro browns/greens/grays, softer than classic gruvbox. Dark + light.
-- Configured via globals (vimscript colorscheme). `:colorscheme gruvbox-material`.
return {
    "sainnhe/gruvbox-material",
    lazy = false,
    priority = 1000,
    init = function()
        vim.g.gruvbox_material_background = "medium" -- "hard" | "medium" | "soft"
        vim.g.gruvbox_material_transparent_background = 2 -- 0 off, 1/2 transparent
        vim.g.gruvbox_material_enable_italic = true
        vim.g.gruvbox_material_better_performance = 1
    end,
}
