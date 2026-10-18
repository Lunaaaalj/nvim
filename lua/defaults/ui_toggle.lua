-- Runtime toggles for transparent/solid editor background and dark/light
-- 'background', persisted to stdpath("state")/ui.json.
--
-- Transparency has two layers and both follow vim.g.ui_transparent:
--   1. each theme spec passes the flag to its native option at setup() time;
--   2. the global ColorScheme strip autocmd in lua/defaults/init.lua returns
--      early when the flag is off.
-- Toggling therefore re-runs the active theme's lazy `init`/`config` (nightfox
-- and catppuccin hash their options and recompile on change) and then reloads
-- the colorscheme so both layers pick up the new value.
--
-- restore() must run BEFORE lazy.nvim loads the theme specs.

local M = {}

local state_file = vim.fn.stdpath("state") .. "/ui.json"

-- Set when switching to light forced solid mode, so going back to dark
-- restores transparency instead of leaving the user in solid mode.
local restore_transparent = false

local function save()
  vim.fn.mkdir(vim.fn.fnamemodify(state_file, ":h"), "p")
  vim.fn.writefile({ vim.json.encode({
    transparent = vim.g.ui_transparent,
    background = vim.o.background,
    restore_transparent = restore_transparent,
  }) }, state_file)
end

-- Alacritty draws its own window.opacity behind the editor, so a "solid" editor
-- still looks see-through unless the terminal goes opaque too. `--reset` drops
-- the runtime override, restoring whatever alacritty.toml says (no hardcoded
-- 0.80). No-op outside Alacritty.
local terminal_overridden = false
local function sync_terminal()
  if not vim.env.ALACRITTY_SOCKET or vim.fn.executable("alacritty") == 0 then return end
  if vim.g.ui_transparent then
    if terminal_overridden then
      vim.system({ "alacritty", "msg", "config", "--reset" })
      terminal_overridden = false
    end
  else
    vim.system({ "alacritty", "msg", "config", "window.opacity=1" })
    terminal_overridden = true
  end
end

-- The lazy plugin that ships colors/<name>.{lua,vim}. Derived from the
-- runtimepath instead of a hand-kept table, so variants (forestbones, dayfox,
-- kanagawa-dragon, ...) resolve to their plugin automatically.
local function plugin_for(scheme)
  local file = vim.api.nvim_get_runtime_file("colors/" .. scheme .. ".lua", false)[1]
    or vim.api.nvim_get_runtime_file("colors/" .. scheme .. ".vim", false)[1]
  if not file then return end
  for _, p in pairs(require("lazy.core.config").plugins) do
    if p.dir and vim.startswith(file, p.dir .. "/") then return p end
  end
end

-- Re-run the active theme's setup with the current flag, then reload it.
-- `name` is passed explicitly when the caller changed 'background' first:
-- that change reloads the scheme, and one that forces its own background
-- (e.g. nightfox) leaves g:colors_name unset afterwards.
local function reapply(name)
  name = name or vim.g.colors_name
  if name then
    local p = plugin_for(name)
    if p and p._.loaded then
      if p.init then p.init(p) end
      if p.config or p.opts then require("lazy.core.loader").config(p) end
    end
    vim.cmd.colorscheme(name)
  end
  sync_terminal()
  save()
end

function M.restore()
  local ok, s = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(state_file), "\n")) end)
  s = ok and type(s) == "table" and s or {}
  vim.g.ui_transparent = s.transparent ~= false -- default: transparent
  restore_transparent = s.restore_transparent == true
  if s.background == "dark" or s.background == "light" then
    vim.o.background = s.background
  end

  sync_terminal()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("UiToggleTerminal", { clear = true }),
    callback = function()
      -- don't leave the terminal opaque after quitting in solid mode
      if terminal_overridden then
        vim.system({ "alacritty", "msg", "config", "--reset" }):wait(500)
      end
    end,
  })
end

function M.toggle_transparency()
  vim.g.ui_transparent = not vim.g.ui_transparent
  restore_transparent = false -- an explicit choice overrides the light-mode guard
  if vim.g.ui_transparent and vim.o.background == "light" then
    vim.notify("Transparent + light: text is drawn over the dark terminal background", vim.log.levels.WARN)
  end
  reapply()
  vim.notify("Background: " .. (vim.g.ui_transparent and "transparent" or "solid"))
end

function M.toggle_background()
  local name, was_transparent, was_restore = vim.g.colors_name, vim.g.ui_transparent, restore_transparent
  local light = vim.o.background == "dark"
  local target = light and "light" or "dark"
  if light and vim.g.ui_transparent then
    -- a light scheme over the dark, translucent terminal is unreadable
    vim.g.ui_transparent = false
    restore_transparent = true
  elseif not light and restore_transparent then
    vim.g.ui_transparent = true
    restore_transparent = false
  end
  vim.o.background = target
  reapply(name)
  if vim.o.background ~= target then
    -- the scheme pins its own background (nightfox, lackluster, ...): undo
    vim.g.ui_transparent, restore_transparent = was_transparent, was_restore
    reapply(name)
    vim.notify(("%s has no %s variant; pick one with <leader>cs"):format(name, target), vim.log.levels.WARN)
    return
  end
  vim.notify(("Background: %s (%s)"):format(vim.o.background, vim.g.ui_transparent and "transparent" or "solid"))
end

vim.api.nvim_create_user_command("ToggleTransparency", M.toggle_transparency, { desc = "Toggle transparent / solid background" })
vim.api.nvim_create_user_command("ToggleBackground", M.toggle_background, { desc = "Toggle dark / light background" })

return M
