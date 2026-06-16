-- Smooth animations for window resize, split open/close, and goto/scroll.
-- Cursor animation is left to smear_cursor.nvim and scrolling to snacks.scroll,
-- so both are disabled here to avoid two plugins fighting over the same effect.
return {
  "echasnovski/mini.animate",
  version = "*",
  event = "VeryLazy",
  config = function()
    local animate = require("mini.animate")
    animate.setup({
      cursor = { enable = false }, -- handled by smear_cursor.nvim
      scroll = { enable = false }, -- handled by snacks.scroll
      resize = { enable = true },
      open = { enable = true },
      close = { enable = true },
    })
  end,
}
