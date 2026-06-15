-- Minimalist "bones" family, every variant ships light + dark.
-- Earthy fits: `forestbones` (green/brown), `kanagawabones`; neutral: `zenbones`,
-- `neobones`. Requires lush.nvim. Transparency via per-variant globals + the
-- global ColorScheme autocmd in lua/defaults/init.lua.
return {
    "zenbones-theme/zenbones.nvim",
    dependencies = { "rktjmp/lush.nvim" },
    lazy = false,
    priority = 1000,
    init = function()
        local transparent = { transparent_background = true }
        vim.g.zenbones = transparent
        vim.g.neobones = transparent
        vim.g.forestbones = transparent
        vim.g.kanagawabones = transparent
        vim.g.seoulbones = transparent
        vim.g.zenbones_compat = 1
    end,
}
