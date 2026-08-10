-- mini.animate's window open/close/resize animations draw temporary floating
-- windows that fade in/out. With this config's global transparency that fade
-- shows up as a dark background flashing whenever a split (terminal, neo-tree)
-- opens — so all of them are disabled. Cursor is handled by smear_cursor.nvim
-- and scrolling by snacks.scroll, which are disabled here too. That leaves the
-- plugin doing nothing; it's kept inert (rather than deleted) so it's easy to
-- re-enable a specific effect later if desired.
return {
  "echasnovski/mini.animate",
  version = "*",
  event = "VeryLazy",
  config = function()
    local animate = require("mini.animate")
    animate.setup({
      cursor = { enable = false }, -- handled by smear_cursor.nvim
      scroll = { enable = false }, -- handled by snacks.scroll
      resize = { enable = false }, -- flickers against the transparent background
      open = { enable = false }, -- flickers against the transparent background
      close = { enable = false }, -- flickers against the transparent background
    })
  end,
}
