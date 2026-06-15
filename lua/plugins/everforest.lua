-- Earthy green/brown forest palette, low-contrast. Dark + light variants.
-- `:colorscheme everforest` (respects background=dark/light).
return {
    "neanias/everforest-nvim",
    lazy = false,
    priority = 1000,
    config = function()
        require("everforest").setup({
            background = "medium", -- "hard" | "medium" | "soft"
            transparent_background_level = 2, -- 0 off, 1 partial, 2 fully transparent
            italics = true,
        })
    end,
}
