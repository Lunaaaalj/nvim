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

-- The scheme's accent: what functions are drawn in, falling back to Special.
function M.accent()
  return M.fg("Function", "Special", "Normal")
end

return M
