-- Runtime toggles for transparent/solid editor background, dark/light
-- 'background', and an auto mode that follows the macOS appearance. All of it
-- is persisted to stdpath("state")/ui.json.
--
-- Transparency has two layers and both follow vim.g.ui_transparent:
--   1. each theme spec passes the flag to its native option at setup() time;
--   2. the global ColorScheme strip autocmd in lua/defaults/init.lua returns
--      early when the flag is off.
-- Toggling therefore re-runs the active theme's lazy `init`/`config` (nightfox
-- and catppuccin hash their options and recompile on change) and then reloads
-- the colorscheme so both layers pick up the new value.
--
-- Transparency is independent of dark/light: kitty follows the macOS
-- appearance itself (its *-theme.auto.conf files), so a transparent light
-- scheme sits on a light terminal.
--
-- Like VS Code's preferred light / dark theme: the last colorscheme loaded
-- while 'background' was dark is the dark scheme, likewise light (`schemes`
-- in ui.json). Flipping 'background' (manually or in auto mode) loads that
-- slot's scheme; with no scheme remembered for the target it keeps the current
-- one and asks it for its other variant (kanso, rose-pine, ...).
--
-- restore() must run BEFORE lazy.nvim loads the theme specs.

local M = {}

local state_file = vim.fn.stdpath("state") .. "/ui.json"

-- Auto mode: 'background' follows the macOS appearance.
local auto = false
local last_system -- last appearance auto mode acted on ("dark" | "light")
local timer

-- Remembered scheme per 'background'; `switching` mutes recording while this
-- module itself is loading schemes (an attempt that fails must not be recorded).
local slots = {}
local switching = false

local function save()
  vim.fn.mkdir(vim.fn.fnamemodify(state_file, ":h"), "p")
  vim.fn.writefile({ vim.json.encode({
    transparent = vim.g.ui_transparent,
    background = vim.o.background,
    auto = auto,
    schemes = slots,
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

-- Whether the loaded scheme actually draws light. 'background' alone can lie:
-- a dark-only scheme that never sets it (vesper) stays dark under "light".
-- Judge by Normal's bg when there is one, else by its fg (transparent mode).
local function scheme_is_light()
  local hl = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local function luma(c) return (0.299 * math.floor(c / 65536) + 0.587 * (math.floor(c / 256) % 256) + 0.114 * (c % 256)) / 255 end
  if hl.bg then return luma(hl.bg) > 0.5 end
  if hl.fg then return luma(hl.fg) < 0.5 end
  return vim.o.background == "light"
end

-- macOS appearance: `defaults read -g AppleInterfaceStyle` prints "Dark" in
-- dark mode and exits 1 (key missing) in light mode. Anything else (timeout,
-- no `defaults`) is unknown, so auto mode leaves 'background' alone.
local appearance_cmd = { "defaults", "read", "-g", "AppleInterfaceStyle" }

local function parse_appearance(r)
  if r.code == 0 and (r.stdout or ""):match("Dark") then return "dark" end
  if r.code == 1 then return "light" end
end

local function system_appearance_sync()
  if vim.fn.has("mac") == 0 then return end
  local ok, r = pcall(function() return vim.system(appearance_cmd, { text = true }):wait(1000) end)
  if ok and r then return parse_appearance(r) end
end

-- Off the main loop; `cb` runs scheduled.
local function system_appearance(cb)
  local ok = pcall(vim.system, appearance_cmd, { text = true }, function(r)
    local a = parse_appearance(r)
    vim.schedule(function() cb(a) end)
  end)
  if not ok then vim.schedule(function() cb(nil) end) end
end

function M.restore()
  local ok, s = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(state_file), "\n")) end)
  s = ok and type(s) == "table" and s or {}
  vim.g.ui_transparent = s.transparent ~= false -- default: transparent
  if s.background == "dark" or s.background == "light" then
    vim.o.background = s.background
  end

  for _, k in ipairs({ "dark", "light" }) do
    local v = type(s.schemes) == "table" and s.schemes[k]
    if type(v) == "string" and v ~= "" then slots[k] = v end
  end
  -- Remember every scheme that was loaded and really draws the current
  -- 'background' (a dark-only scheme that ignored "light" must not be filed
  -- under light). Registered before the strip autocmd, so Normal is still raw.
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("UiToggleRecord", { clear = true }),
    callback = function(ev)
      local bg = vim.o.background
      if switching or slots[bg] == ev.match or scheme_is_light() ~= (bg == "light") then return end
      slots[bg] = ev.match
      save()
    end,
  })

  -- Auto mode wins over the saved background. No scheme is loaded yet, so
  -- setting the option is enough; once the startup scheme is up, VimEnter
  -- checks it really drew the requested variant (and warns if not).
  if s.auto == true and vim.fn.has("mac") == 1 then
    auto = true
    local a = system_appearance_sync()
    if a then
      last_system = a
      vim.o.background = a
      vim.api.nvim_create_autocmd("VimEnter", {
        once = true,
        callback = function() vim.schedule(function() if auto then M.set_background(a) end end) end,
      })
    end
    M.watch()
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

-- The scheme to load at startup in auto mode, so the right one comes up
-- directly instead of the last session's followed by a swap.
function M.startup_scheme()
  if auto then return slots[vim.o.background] end
end

function M.toggle_transparency()
  vim.g.ui_transparent = not vim.g.ui_transparent
  reapply()
  vim.notify("Background: " .. (vim.g.ui_transparent and "transparent" or "solid"))
end

-- Switch to "dark" | "light". Returns false (after undoing everything and
-- warning) when the scheme has no variant for the target. Does nothing, with
-- no scheme reload, when it already draws the target.
function M.set_background(target, opts)
  opts = opts or {}
  local light = target == "light"
  local name, was_bg = vim.g.colors_name, vim.o.background
  local to = slots[target] or name -- the remembered scheme, else the current one
  if was_bg == target and scheme_is_light() == light and to == name then return true end

  -- Setting 'background' auto-reloads g:colors_name with the theme's OLD
  -- config; a scheme that derives 'background' from its variant (evergarden)
  -- would flip it straight back. Clearing the name skips that reload, so the
  -- only load is reapply() below, after the spec has re-read the new value.
  switching = true
  vim.g.colors_name = nil
  vim.o.background = target
  local loaded = pcall(reapply, to)
  if not loaded or vim.o.background ~= target or scheme_is_light() ~= light then
    -- no variant for target: the scheme pinned 'background' back (nightfox) or
    -- ignored it (vesper), or the remembered scheme is gone. Undo, 'background'
    -- included.
    vim.g.colors_name = nil
    vim.o.background = was_bg
    reapply(name)
    switching = false
    vim.notify(("%s has no %s variant; pick one with <leader>cs"):format(to or "This scheme", target), vim.log.levels.WARN)
    return false
  end
  switching = false
  if to and slots[target] ~= to then
    slots[target] = to
    save()
  end
  if not opts.quiet then
    vim.notify(("Background: %s, %s (%s)"):format(vim.o.background, vim.g.colors_name or "?", vim.g.ui_transparent and "transparent" or "solid"))
  end
  return true
end

-- Auto mode only acts when the system appearance CHANGES from what it last
-- handled: a scheme without the variant warns once per system change instead
-- of on every poll.
local function apply_system(a)
  if not auto or not a or a == last_system then return end
  last_system = a
  local was = vim.o.background
  if M.set_background(a, { quiet = true }) and vim.o.background ~= was then
    vim.notify(("Auto theme: %s (%s)"):format(a, vim.g.colors_name or "?"))
  end
end

local function poll() system_appearance(apply_system) end

local function stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

local function start_timer()
  stop_timer()
  timer = vim.uv.new_timer()
  timer:start(5000, 5000, vim.schedule_wrap(poll))
end

-- A slow poll while Neovim has focus, plus an immediate check on FocusGained
-- (stopping the poll on FocusLost). Without focus reporting the poll just
-- keeps running.
function M.watch()
  local g = vim.api.nvim_create_augroup("UiToggleAuto", { clear = true })
  vim.api.nvim_create_autocmd("FocusLost", { group = g, callback = stop_timer })
  vim.api.nvim_create_autocmd("FocusGained", { group = g, callback = function() poll(); start_timer() end })
  start_timer()
end

local function unwatch()
  stop_timer()
  pcall(vim.api.nvim_del_augroup_by_name, "UiToggleAuto")
end

-- A manual flip is an explicit choice, so it ends auto mode.
function M.toggle_background()
  if auto then
    auto = false
    unwatch()
    vim.notify("Auto theme: off (manual flip)")
  end
  M.set_background(vim.o.background == "dark" and "light" or "dark")
end

function M.toggle_auto()
  if auto then
    auto = false
    unwatch()
    save()
    vim.notify("Auto theme: off")
    return
  end
  if vim.fn.has("mac") == 0 then
    vim.notify("Auto theme follows the macOS appearance; not available here", vim.log.levels.WARN)
    return
  end
  local a = system_appearance_sync()
  if not a then
    vim.notify("Could not read the system appearance", vim.log.levels.WARN)
    return
  end
  auto, last_system = true, nil
  M.watch()
  save()
  vim.notify("Auto theme: on")
  apply_system(a)
end

vim.api.nvim_create_user_command("ToggleTransparency", M.toggle_transparency, { desc = "Toggle transparent / solid background" })
vim.api.nvim_create_user_command("ToggleBackground", M.toggle_background, { desc = "Toggle dark / light background" })
vim.api.nvim_create_user_command("ToggleAutoTheme", M.toggle_auto, { desc = "Toggle auto dark / light (follow macOS)" })

return M
