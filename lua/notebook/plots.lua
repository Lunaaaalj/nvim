-- Plot paper for notebook output (issue #40, phase 3).
--
-- Two modes, like the PDF viewer's `c`: "theme" (default) draws plots on the
-- colorscheme's background with its foreground for text/axes; "paper" draws
-- them black on white, like an exported notebook. Toggle: <leader>mp.
--
-- Kernels pick the style up from files written here (never from code sent
-- through Molten, which would add output cells):
--   matplotlibrc   $MATPLOTLIBRC for generated Python kernels, read on import;
--                  kernel_startup.py re-applies it when it changes
--   plot_style.R   read by kernel_startup.R before each base/grid plot
--                  (repr.plot.bg, par(), ggplot2 theme)
-- And every PNG Molten hands to image.nvim is flattened onto the same paper,
-- so figures saved with a transparent background (savefig(transparent=True),
-- some seaborn/plotly styles) don't show the terminal through them.
local M = {}

local colors = require("defaults.colors")

M.dir = vim.fn.stdpath("cache") .. "/notebook"
M.matplotlibrc = M.dir .. "/matplotlibrc"
M.style_r = M.dir .. "/plot_style.R"
local STATE = vim.fn.stdpath("state") .. "/notebook.json"
local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
M.startup_py = here .. "/kernel_startup.py"
M.startup_r = here .. "/kernel_startup.R"

M.mode = "theme"
M.last = nil ---@type string? last image Molten displayed (flattened copy)

local function load_state()
  local ok, lines = pcall(vim.fn.readfile, STATE)
  local ok2, data = pcall(vim.json.decode, ok and table.concat(lines, "\n") or "")
  if ok2 and type(data) == "table" and (data.plot_paper == "paper" or data.plot_paper == "theme") then
    M.mode = data.plot_paper
  end
end

local function save_state()
  pcall(vim.fn.writefile, { vim.json.encode({ plot_paper = M.mode }) }, STATE)
end

--- The colours plots are drawn with, as "#rrggbb".
function M.style()
  if M.mode == "paper" then
    return { bg = "#ffffff", panel = "#ffffff", fg = "#222222", muted = "#555555", grid = "#e5e5e5" }
  end
  local bg = colors.bg()
  local fg = colors.fg("Normal") or (vim.o.background == "light" and 0x222222 or 0xdddddd)
  return {
    bg = colors.hex(bg),
    panel = colors.hex(colors.blend(fg, bg, 0.03)),
    fg = colors.hex(fg),
    muted = colors.hex(colors.blend(fg, bg, 0.75)),
    grid = colors.hex(colors.blend(fg, bg, 0.15)),
  }
end

-- Figure resolution matched to the terminal's cell height in pixels, so a
-- 6.4x4.8in figure covers about the same number of cells on a retina screen
-- (36px cells) as on a 1x one (18px), instead of half as many.
function M.dpi()
  local ok, term = pcall(function() return require("image.utils.term").get_size() end)
  local cell_h = ok and type(term) == "table" and tonumber(term.cell_height) or nil
  if not cell_h or cell_h <= 0 then return 100 end
  return math.max(100, math.min(220, math.floor(100 * cell_h / 18 + 0.5)))
end

--- Write the style files the kernels read (mtime changes = re-applied).
function M.write()
  local s = M.style()
  local dpi = M.dpi()
  vim.fn.mkdir(M.dir, "p")
  local h = function(c) return c:sub(2) end -- matplotlibrc wants bare hex
  vim.fn.writefile({
    "# written by Neovim (lua/notebook/plots.lua): plot paper = " .. M.mode,
    "figure.facecolor: " .. h(s.bg),
    "figure.edgecolor: " .. h(s.bg),
    "savefig.facecolor: auto",
    "axes.facecolor: " .. h(s.panel),
    "axes.edgecolor: " .. h(s.muted),
    "axes.labelcolor: " .. h(s.fg),
    "axes.titlecolor: " .. h(s.fg),
    "text.color: " .. h(s.fg),
    "xtick.color: " .. h(s.muted),
    "ytick.color: " .. h(s.muted),
    "xtick.labelcolor: " .. h(s.fg),
    "ytick.labelcolor: " .. h(s.fg),
    "grid.color: " .. h(s.grid),
    "legend.facecolor: " .. h(s.bg),
    "legend.edgecolor: " .. h(s.grid),
    "legend.labelcolor: " .. h(s.fg),
    "figure.dpi: " .. dpi,
  }, M.matplotlibrc)
  vim.fn.writefile({
    "# written by Neovim (lua/notebook/plots.lua): plot paper = " .. M.mode,
    ('list(bg = "%s", panel = "%s", fg = "%s", muted = "%s", grid = "%s", dpi = %d)'):format(
      s.bg, s.panel, s.fg, s.muted, s.grid, dpi),
  }, M.style_r)
end

--- Environment for a generated kernelspec.
function M.kernel_env()
  return { MATPLOTLIBRC = M.matplotlibrc, NVIM_PLOT_STYLE_R = M.style_r }
end

-- ---------------------------------------------------------------------------
-- Flattening Molten's images

local flat_dir = M.dir .. "/flat"
-- R's png() on macOS (bitmapType "quartz"; cairo needs XQuartz) tags its PNGs
-- "Generic RGB". kitty ignores ICC profiles, so the colours came out darker
-- (#1e2528 drawn as #171c1e). Converting to sRGB fixes that; an untagged image
-- is just assigned sRGB, no change.
local SRGB = "/System/Library/ColorSync/Profiles/sRGB Profile.icc"

--- Flatten an image onto the paper; returns the new path (nil on failure).
function M.flatten(path)
  local bg = M.style().bg
  local st = vim.uv.fs_stat(path)
  if not st then return nil end
  -- size + mtime too: tempfile names can come round again
  local key = table.concat({ path, st.size, st.mtime.sec, st.mtime.nsec, bg }, "|")
  local out = ("%s/%s.png"):format(flat_dir, vim.fn.sha256(key):sub(1, 16))
  if vim.uv.fs_stat(out) then return out end
  vim.fn.mkdir(flat_dir, "p")
  local cmd = { "magick", path }
  if vim.uv.fs_stat(SRGB) then vim.list_extend(cmd, { "-profile", SRGB }) end
  vim.list_extend(cmd, { "-background", bg, "-alpha", "remove", "-alpha", "off", "-strip", out })
  local r = vim.system(cmd):wait(5000)
  return r.code == 0 and out or nil
end

-- Molten's image.nvim bridge (molten-nvim/lua/load_image_nvim.lua) is a plain
-- Lua table the Python side calls into; wrap its from_file. The returned
-- identifier is the path image.nvim was given, so render/clear keep working.
local function patch_bridge()
  local ok, bridge = pcall(require, "load_image_nvim")
  if not ok or type(bridge) ~= "table" or not bridge.image_api or bridge.image_api._nvim_flatten then return end
  local from_file = bridge.image_api.from_file
  bridge.image_api.from_file = function(path, opts)
    local flat = vim.fn.executable("magick") == 1 and M.flatten(path) or nil
    M.last = flat or path
    return from_file(flat or path, opts)
  end
  bridge.image_api._nvim_flatten = true
end

local view_win ---@type integer?

-- Show `path` in the plot window, reusing it (the previous image buffer is
-- wiped), else in a new split beside the first file window. Keeps the focus.
local function show_in_split(path)
  local cur = vim.api.nvim_get_current_win()
  local function load(win)
    vim.api.nvim_win_call(win, function()
      local old = vim.api.nvim_get_current_buf()
      vim.cmd("edit " .. vim.fn.fnameescape(path))
      vim.bo.bufhidden = "wipe"
      if old ~= vim.api.nvim_get_current_buf() and vim.api.nvim_buf_is_valid(old) and vim.bo[old].filetype == "image" then
        pcall(vim.api.nvim_buf_delete, old, { force = true })
      end
    end)
  end
  if view_win and vim.api.nvim_win_is_valid(view_win) then return load(view_win) end
  local host = cur
  if vim.bo[vim.api.nvim_win_get_buf(cur)].buftype ~= "" or vim.api.nvim_win_get_config(cur).relative ~= "" then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "" and vim.api.nvim_win_get_config(w).relative == "" then
        host = w
        break
      end
    end
  end
  vim.api.nvim_win_call(host, function()
    vim.cmd("rightbelow vsplit")
    view_win = vim.api.nvim_get_current_win()
  end)
  load(view_win)
  if vim.api.nvim_win_is_valid(cur) then vim.api.nvim_set_current_win(cur) end
end

--- Open the last plot full size in a split (snacks image buffer).
function M.view()
  if not M.last or not vim.uv.fs_stat(M.last) then
    return vim.notify("No plot shown yet in this session", vim.log.levels.WARN)
  end
  show_in_split(M.last)
end

--- Called by the REPLs (nvim --remote-expr) with a PNG they just saved.
function M.show_file(path)
  vim.schedule(function()
    if not vim.uv.fs_stat(path) then return end
    M.last = (vim.fn.executable("magick") == 1 and M.flatten(path)) or path
    show_in_split(M.last)
  end)
  return 1
end

function M.toggle()
  M.mode = M.mode == "theme" and "paper" or "theme"
  save_state()
  M.write()
  vim.notify(("Plot paper: %s (applies to the next plot)"):format(M.mode))
end

function M.setup()
  load_state()
  M.write()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("NotebookPlots", { clear = true }),
    -- scheduled: the strip autocmd (defaults/init.lua) records the scheme bg
    callback = function() vim.schedule(M.write) end,
  })
  if vim.g.molten_image_provider == "image.nvim" then patch_bridge() end
end

return M
