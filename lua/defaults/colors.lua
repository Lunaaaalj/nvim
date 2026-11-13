-- Small highlight helpers for deriving accents from whatever scheme is active,
-- so custom UI (cursorline, neo-tree tabs, dashboard) matches every theme.

local M = {}

-- First defined foreground (as an integer) among `groups`, resolving links.
function M.fg(...)
  for _, name in ipairs({ ... }) do
    local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
    if hl.fg then return hl.fg end
  end
end

-- Mix `a` into `b` by `alpha` (0..1); both integers, returns an integer.
function M.blend(a, b, alpha)
  local function ch(c, shift) return math.floor(c / 2 ^ shift) % 256 end
  local out = 0
  for _, shift in ipairs({ 16, 8, 0 }) do
    local v = math.floor(ch(a, shift) * alpha + ch(b, shift) * (1 - alpha) + 0.5)
    out = out + v * 2 ^ shift
  end
  return out
end

-- What actually shows behind a transparent editor: Alacritty's background.
-- alacritty.toml sets no colors.primary.background, so this is Alacritty's
-- default. Animations that fade (smear trail, yank flash) fade toward it; if you
-- change the terminal background, change this too.
M.terminal_bg = "#181818"

-- The scheme's own background, even in transparent mode (where Normal's bg
-- has been stripped): recorded by the strip autocmd in defaults/init.lua.
-- Falls back to a neutral dark/light when the scheme sets none.
function M.bg()
  local hl = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  return vim.g.scheme_bg or hl.bg or (vim.o.background == "light" and 0xf5f5f5 or 0x181818)
end

function M.hex(c)
  return ("#%06x"):format(c)
end

-- The scheme's accent: what functions are drawn in, falling back to Special.
function M.accent()
  return M.fg("Function", "Special", "Normal")
end

return M
