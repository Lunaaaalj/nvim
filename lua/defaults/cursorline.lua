-- Current-line styling + which windows get a cursorline at all.
--
-- Transparent mode (vim.g.ui_transparent) uses vim.g.cursorline_style:
--   "number"    accent, bold line number only; no line decoration (default)
--   "underline" a single faint rule in one colour (explicit `sp`)
--   "band"      a soft tint: Normal fg blended ~7% into black/white. Over a
--               translucent Alacritty this needs
--               `colors.transparent_background_colors = true`, else it is an
--               opaque stripe.
-- Solid mode keeps the scheme's own CursorLine band untouched.
-- <leader>uc cycles the style.
--
-- Required from lua/defaults/init.lua AFTER the transparency strip autocmd, so
-- its ColorScheme handler runs second and wins.

local colors = require("defaults.colors")

local M = {}

local styles = { "number", "underline", "band" }
vim.g.cursorline_style = vim.g.cursorline_style or "number"

local function opt()
  if vim.g.ui_transparent and vim.g.cursorline_style == "number" then return "number" end
  return "number,line"
end

local function apply_highlights()
  if not vim.g.ui_transparent then return end -- the scheme's band looks right on its own bg
  local set = vim.api.nvim_set_hl
  set(0, "CursorLineNr", { fg = colors.accent(), bold = true })
  local style = vim.g.cursorline_style
  if style == "underline" then
    set(0, "CursorLine", { underline = true, sp = colors.fg("LineNr", "Comment") })
  elseif style == "band" then
    local base = vim.o.background == "light" and 0xffffff or 0x000000
    set(0, "CursorLine", { bg = colors.blend(colors.fg("Normal") or 0x808080, base, 0.07) })
  else
    set(0, "CursorLine", {})
  end
end

-- Filetypes that never get a cursorline, and ones that manage it themselves
-- (neo-tree uses its cursorline as the selection marker).
local skip_ft = { image = true, snacks_dashboard = true, lazy = true, mason = true, TelescopePrompt = true, TelescopeResults = true }
local unmanaged_ft = { ["neo-tree"] = true }

local function update(win, active)
  if not vim.api.nvim_win_is_valid(win) then return end
  local buf = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[buf].filetype
  if unmanaged_ft[ft] then return end
  -- Window-local option values are copied into every new window, so terminals
  -- and floats must be switched off explicitly, not just left alone. Floats
  -- include Zen Mode's window, which keeps its `cursorline = false`.
  local on = active
    and vim.bo[buf].buftype == ""
    and vim.api.nvim_win_get_config(win).relative == ""
    and not skip_ft[ft]
    and not vim.w[win].no_cursorline -- per-window opt-out
  vim.wo[win].cursorline = on
  if on then vim.wo[win].cursorlineopt = opt() end
end

local grp = vim.api.nvim_create_augroup("ActiveCursorLine", { clear = true })
vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter", "FileType", "TermOpen" }, {
  group = grp,
  callback = function() update(vim.api.nvim_get_current_win(), true) end,
})
vim.api.nvim_create_autocmd("WinLeave", {
  group = grp,
  callback = function() update(vim.api.nvim_get_current_win(), false) end,
})
vim.api.nvim_create_autocmd("ColorScheme", {
  group = grp,
  callback = function()
    apply_highlights()
    -- cursorlineopt depends on the mode, which a ColorScheme reload may change
    update(vim.api.nvim_get_current_win(), true)
  end,
})

function M.cycle()
  local i = 1
  for j, s in ipairs(styles) do if s == vim.g.cursorline_style then i = j end end
  vim.g.cursorline_style = styles[i % #styles + 1]
  apply_highlights()
  update(vim.api.nvim_get_current_win(), true)
  vim.notify("Cursorline: " .. vim.g.cursorline_style
    .. (vim.g.ui_transparent and "" or " (applies in transparent mode)"))
end

return M
