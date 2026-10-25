-- Flexoki: "inky" warm paper tones, very calm. `:colorscheme flexoki` follows
-- 'background'; flexoki-dark / flexoki-light pin a variant. No built-in
-- transparency option; the global ColorScheme autocmd in lua/defaults/init.lua
-- strips the background (only while vim.g.ui_transparent).
return {
    "kepano/flexoki-neovim",
    name = "flexoki",
    lazy = false,
    priority = 1000,
}
