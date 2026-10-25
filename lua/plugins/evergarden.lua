-- Cozy earthy green-beige. evergarden sets 'background' FROM its variant
-- (summer = light, the rest dark), so the variant is chosen from 'background'
-- here; ui_toggle re-runs this config before reloading. evergarden-fall /
-- -winter / -spring / -summer pin a variant.
return {
    "comfysage/evergarden",
    lazy = false,
    priority = 1000,
    config = function()
        require("evergarden").setup({
            theme = {
                variant = vim.o.background == "light" and "summer" or "fall", -- fall: the warmest dark
                transparent_background = vim.g.ui_transparent, -- <leader>ub
            },
        })
    end,
}
