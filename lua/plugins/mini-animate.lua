-- Window resize / open / close animations (cursor and scroll stay off: smear_cursor
-- and snacks.scroll own those, and double-animating fights).
--
-- The stock open/close animation draws a float over the window with
-- MiniAnimateNormalFloat -> NormalFloat (bg stripped by the transparency
-- autocmd) and FADES its 'winblend' 80 -> 100. Fading a bg-less float over
-- transparent cells is what flashed dark before. This version is motion only:
-- the float gets a soft scheme-derived tint, 'winblend' stays constant, and the
-- window shape grows from / shrinks to the centre. To compare with the stock
-- fade, delete the two `winblend` lines below.
return {
  "echasnovski/mini.animate",
  version = "*",
  event = "VeryLazy",
  config = function()
    local animate = require("mini.animate")
    local colors = require("defaults.colors")
    local function tint()
      local fg = colors.fg("Comment") or 0x808080
      vim.api.nvim_set_hl(0, "MiniAnimateNormalFloat", { bg = colors.blend(fg, tonumber(colors.terminal_bg:sub(2), 16), 0.12) })
    end
    tint()
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("MiniAnimateTint", { clear = true }),
      callback = tint,
    })

    local timing = animate.gen_timing.quadratic({ easing = "out", duration = 150, unit = "total" })
    local still = function() return 0 end -- constant 'winblend': no fade
    animate.setup({
      cursor = { enable = false }, -- handled by smear_cursor.nvim
      scroll = { enable = false }, -- handled by snacks.scroll
      resize = { enable = true, timing = timing },
      open = {
        enable = true,
        timing = timing,
        winconfig = animate.gen_winconfig.center({ direction = "from_center" }),
        winblend = still,
      },
      close = {
        enable = true,
        timing = timing,
        winconfig = animate.gen_winconfig.center({ direction = "to_center" }),
        winblend = still,
      },
    })
  end,
}
