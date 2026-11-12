-- Animated generative art behind the whole snacks dashboard window.
--
-- Snacks renders the dashboard content (clock, stats, key hints) as real text and
-- only knows about those lines, so the rest of the window is free. This module
-- fills it: every frame it computes a w x h field of levels (lua/header_art/
-- pieces.lua), maps them through a character set and writes the result as overlay
-- extmarks (own namespace, so snacks' re-renders never touch them) on the cells
-- that hold no text, plus `virt_lines` for the rows below the buffer's last line.
-- One clear rectangle around all the text (with a soft fade-in edge) keeps the
-- content readable. Colours are 8 steps from a dim tone to the scheme's
-- foreground (Normal fg; HeaderArt1..N, re-made on ColorScheme), so one
-- highlight group is shared by many cells.
--
-- The timer runs only while a dashboard window is visible and Neovim is focused,
-- like the clock in lua/plugins/snacks.lua. The braille header
-- (`dashboard-header.txt`) is kept as the alternative: `enabled = false` (or
-- `:HeaderArt toggle`, <leader>ua) brings it back.

local pieces = require("header_art.pieces")
local colors = require("defaults.colors")

local M = {}

local uv = vim.uv or vim.loop
local ns = vim.api.nvim_create_namespace("header_art")

---@class header_art.opts
---@field enabled boolean   draw the art; false shows the static braille header instead
---@field piece string      plasma | torus | orb | rings | flow | terrain | galaxy | galaxies | descent | spiral | hilbert | rain | aurora | turing | attention | kmeans | matrix | warp | life
---@field charset string    classic | blocks | dots | binary
---@field fps integer       frames per second
---@field speed number      animation speed multiplier (1 = the pieces' natural pace)
---@field brightness number 0..1, how far toward the foreground the brightest cells go
---@field halo boolean      pad the clear content box and fade the art in at its edge
---@field steps integer     colour steps between the dim tone and the accent
---@field animate boolean   false draws a single still frame instead of animating
local defaults = {
  enabled = true,
  piece = "plasma",
  charset = "classic",
  fps = 30,
  speed = 0.4,
  brightness = 0.7,
  halo = true,
  steps = 8,
  animate = true,
}

local charsets = {
  classic = { " ", ".", ":", "-", "=", "+", "*", "#", "%", "@" },
  blocks = { " ", "░", "░", "▒", "▒", "▓", "▓", "█", "█", "█" },
  dots = { " ", "·", "·", "∙", "•", "•", "●", "●", "●", "●" },
  binary = { " ", " ", "0", "1", "0", "1", "0", "1", "1", "1", binary = true },
}
local charset_names = { "classic", "blocks", "dots", "binary" }

local cfg = vim.deepcopy(defaults)
local S = { val = {}, mask = {}, t = 0 } -- runtime state

local clamp = function(v) return v < 0 and 0 or (v > 1 and 1 or v) end

-- The chosen piece and on/off survive restarts (machine-local, like the
-- colorscheme): written by the picker, toggle and `next`, read in setup().
-- Other `:HeaderArt` options stay session-only.
local state_file = vim.fn.stdpath("state") .. "/header_art.json"
local persisted = { "piece", "enabled" }

local function save()
  local out = {}
  for _, k in ipairs(persisted) do out[k] = cfg[k] end
  pcall(vim.fn.writefile, { vim.json.encode(out) }, state_file)
end

local function load()
  local ok, s = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(state_file), "\n")) end)
  if not ok or type(s) ~= "table" then return end
  if type(s.piece) == "string" and type(pieces[s.piece]) == "function" then cfg.piece = s.piece end
  if type(s.enabled) == "boolean" then cfg.enabled = s.enabled end
end

-- Level `v` (0..1) at cell x of screen row sr -> character, colour step.
-- Shared by the dashboard and the picker preview. `forced` is the character a
-- piece chose for the cell (its `chr` table, e.g. a contour's direction); it
-- replaces the charset's, and only the level decides the colour.
local function cell(set, v, x, sr, tick, forced)
  local nch = #set
  local idx = math.min(nch, math.floor(clamp(v) * nch) + 1)
  local ch = set[idx]
  if forced then
    ch = v > 0.03 and forced or " "
  elseif set.binary and idx > 2 then
    ch = (bit.band(x * 7 + sr * 13 + tick, 1) == 1) and "1" or "0"
  end
  return ch, math.min(cfg.steps, math.floor(clamp(v * cfg.brightness) * cfg.steps) + 1)
end

---------------------------------------------------------------------------
-- highlights
---------------------------------------------------------------------------

local function hex_to_int(s) return tonumber(s:sub(2), 16) end

local function set_hl()
  -- The scheme's own text colour (Normal fg keeps its fg in transparent mode).
  local accent = colors.fg("Normal") or colors.accent()
  if not accent then return end
  local bg
  if vim.g.ui_transparent then
    bg = hex_to_int(colors.terminal_bg)
  else
    bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg or hex_to_int(colors.terminal_bg)
  end
  local dim = colors.blend(colors.fg("Comment") or accent, bg, 0.45)
  for i = 1, cfg.steps do
    local k = cfg.steps == 1 and 1 or (i - 1) / (cfg.steps - 1)
    vim.api.nvim_set_hl(0, "HeaderArt" .. i, { fg = colors.blend(accent, dim, k) })
  end
end

---------------------------------------------------------------------------
-- finding the dashboard
---------------------------------------------------------------------------

local function dashboard_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.bo[b].filetype == "snacks_dashboard" then return w, b end
  end
end

---------------------------------------------------------------------------
-- content box: one clear rectangle around all the text (cached per buffer change)
---------------------------------------------------------------------------

-- Punching a hole per text cell left a ragged notch around every section
-- (clock, stats, hints). Instead the art keeps clear of ONE rectangle around
-- all of the content, padded, and fades in over `FADE` cells outside it, so
-- the content sits on a calm card with a soft edge.
local PAD_R, PAD_C, FADE = 1, 6, 8

local function content_box(buf, w)
  local key = vim.api.nvim_buf_get_changedtick(buf) .. ":" .. w .. ":" .. tostring(cfg.halo)
  if S.box_key == key and S.box_buf == buf then return S.box end
  local r0, r1, c0, c1
  for r, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local s = line:find("%S")
    if s then
      local body = line:match("^(.-)%s*$")
      local cs = vim.api.nvim_strwidth(line:sub(1, s - 1))
      local ce = vim.api.nvim_strwidth(body) - 1
      r0, r1 = r0 or (r - 1), r - 1
      c0, c1 = math.min(c0 or cs, cs), math.max(c1 or ce, ce)
    end
  end
  local box
  if r0 then
    local pr, pc = cfg.halo and PAD_R or 0, cfg.halo and PAD_C or 0
    box = { r0 = r0 - pr, r1 = r1 + pr, c0 = c0 - pc, c1 = c1 + pc, fade = cfg.halo and FADE or 0 }
  end
  S.box, S.box_key, S.box_buf = box, key, buf
  return box
end

-- 0 inside the box (no art), rising smoothly to 1 over `fade` cells outside it.
-- Rows count double: a cell is about twice as tall as it is wide.
local function box_factor(box, row, x)
  if not box then return 1 end
  local dx = math.max(box.c0 - x, x - box.c1, 0)
  local dy = math.max(box.r0 - row, row - box.r1, 0)
  if dx == 0 and dy == 0 then return 0 end
  if box.fade == 0 then return 1 end
  local d = math.max(dx, dy * 2) / box.fade
  if d >= 1 then return 1 end
  return d * d * (3 - 2 * d)
end

---------------------------------------------------------------------------
-- drawing
---------------------------------------------------------------------------

local function clear(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1) end
end

local function draw()
  local win, buf = dashboard_win()
  if not win then return false end
  local info = vim.fn.getwininfo(win)[1]
  local w, h, top = info.width - info.textoff, info.height, info.topline
  if w < 10 or h < 4 then
    clear(buf)
    return true
  end

  if S.w ~= w or S.h ~= h or S.piece ~= cfg.piece then
    S.w, S.h, S.piece = w, h, cfg.piece
    S.frame = pieces[cfg.piece](w, h)
    S.val, S.chr = {}, {}
  end

  local now = uv.hrtime()
  local dt = S.last and math.min(0.25, (now - S.last) / 1e9) or 0
  S.last = now
  S.t = S.t + dt * cfg.speed
  -- Pieces may also pick a character per cell (frame's third argument).
  local chr = S.chr
  for i = 1, w * h do chr[i] = false end
  S.frame(S.t, S.val, chr)

  local nlines = vim.api.nvim_buf_line_count(buf)
  local box = content_box(buf, w)
  local set = charsets[cfg.charset] or charsets.classic
  local val, tick = S.val, math.floor(S.t * 0.7)

  -- Screen row `sr` (document row `row`) as runs of chunks: { { start_col, chunks }, ... }.
  -- Cells inside the content box end a run (overlay rows must not cover the
  -- text), or, with `fill` (virt_lines, which can't skip cells), become blanks.
  local function segments(sr, row, fill)
    local segs, chunks, run, cur, startx = {}, nil, nil, nil, 0
    local function flush()
      chunks[#chunks + 1] = { table.concat(run), cur > 0 and ("HeaderArt" .. cur) or nil }
    end
    for x = 0, w - 1 do
      local f = box_factor(box, row, x)
      if f == 0 and not fill then
        if chunks then
          flush()
          segs[#segs + 1] = { startx, chunks }
          chunks = nil
        end
      else
        local ch, step = " ", 0
        if f > 0 then
          local i = sr * w + x + 1
          ch, step = cell(set, (val[i] or 0) * f, x, sr, tick, chr[i])
        end
        if not chunks then
          chunks, run, cur, startx = {}, {}, step, x
        elseif step ~= cur then
          flush()
          run, cur = {}, step
        end
        run[#run + 1] = ch
      end
    end
    if chunks then
      flush()
      segs[#segs + 1] = { startx, chunks }
    end
    return segs
  end

  clear(buf)
  -- Rows that show buffer lines: overlay extmarks on the free cells.
  for sr = 0, h - 1 do
    local row = top - 1 + sr
    if row >= nlines then break end
    for _, sg in ipairs(segments(sr, row, false)) do
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
        virt_text = sg[2],
        virt_text_pos = "overlay",
        virt_text_win_col = sg[1],
      })
    end
  end
  -- Rows below the last line. The COUNT must not depend on `top`: virt_lines are
  -- part of the document height, so a count derived from the scroll position
  -- changes the scroll limit as the window scrolls and the two chase each other
  -- (the view jumps back and forth, snacks.scroll animating each jump). Use the
  -- count for an unscrolled window; rows that are off screen get a blank filler.
  local below = h - nlines
  if below > 0 then
    local vlines = {}
    for k = 0, below - 1 do
      local sr = nlines - (top - 1) + k
      local segs = (sr >= 0 and sr < h) and segments(sr, nlines + k, true) or nil
      vlines[#vlines + 1] = segs and segs[1] and segs[1][2] or { { " " } }
    end
    vim.api.nvim_buf_set_extmark(buf, ns, nlines - 1, 0, { virt_lines = vlines })
  end
  return true
end

---------------------------------------------------------------------------
-- timer
---------------------------------------------------------------------------

local function stop()
  if S.timer then
    S.timer:stop()
    S.timer:close()
    S.timer = nil
  end
  S.last = nil
end

local function safe_draw()
  local ok, res = pcall(draw)
  if not ok then
    stop()
    cfg.enabled = false
    vim.notify("header_art disabled: " .. tostring(res), vim.log.levels.ERROR)
    return false
  end
  return res
end

local function start()
  if not cfg.enabled or S.timer then return end
  if not dashboard_win() then return end
  if not cfg.animate then
    vim.schedule(safe_draw)
    return
  end
  S.timer = uv.new_timer()
  S.timer:start(0, math.max(1, math.floor(1000 / math.max(1, cfg.fps))), vim.schedule_wrap(function()
    if not S.timer then return end
    if not safe_draw() then stop() end
  end))
end

local function restart()
  stop()
  start()
end

---------------------------------------------------------------------------
-- public api
---------------------------------------------------------------------------

function M.enabled() return cfg.enabled end

function M.options() return vim.deepcopy(cfg) end

local function refresh_dashboard()
  if _G.Snacks and Snacks.dashboard and dashboard_win() then Snacks.dashboard.update() end
end

local function set_enabled(on)
  if cfg.enabled == on then return end
  cfg.enabled = on
  if on then
    set_hl()
    refresh_dashboard() -- the braille header section hides itself
    restart()
  else
    stop()
    local _, buf = dashboard_win()
    clear(buf)
    refresh_dashboard() -- ... and comes back
  end
end

---@param on? boolean  nil toggles
function M.toggle(on)
  if on == nil then on = not cfg.enabled end
  set_enabled(on)
  save()
  vim.notify("Header art " .. (on and "on" or "off"))
end

--- Show `piece` (or the braille header when `piece` is nil) without a notice;
--- `persist` also remembers it across restarts. Used by the picker.
---@param piece? string
---@param persist? boolean
function M.apply(piece, persist)
  if piece then
    if type(pieces[piece]) ~= "function" then return end
    cfg.piece = piece
    set_enabled(true)
    if cfg.animate then start() else vim.schedule(safe_draw) end
  else
    set_enabled(false)
  end
  if persist then save() end
end

--- One frame of `piece` at time `t`, as `lines` (w x h) plus highlight ranges
--- `{ row, start_byte, end_byte, group }`, for drawing outside the dashboard
--- (the picker preview). `cache` keeps the built piece between frames.
---@return string[] lines, table[] marks
function M.render_frame(piece, w, h, t, cache)
  if cache.key ~= piece .. ":" .. w .. ":" .. h then
    cache.key, cache.frame, cache.val, cache.chr = piece .. ":" .. w .. ":" .. h, pieces[piece](w, h), {}, {}
  end
  for i = 1, w * h do cache.chr[i] = false end
  cache.frame(t, cache.val, cache.chr)
  local set = charsets[cfg.charset] or charsets.classic
  local tick = math.floor(t * 0.7)
  local lines, marks = {}, {}
  for sr = 0, h - 1 do
    local parts, bytes, cur, start = {}, 0, nil, 0
    for x = 0, w - 1 do
      local i = sr * w + x + 1
      local ch, step = cell(set, cache.val[i] or 0, x, sr, tick, cache.chr[i])
      if step ~= cur then
        if cur then marks[#marks + 1] = { sr, start, bytes, "HeaderArt" .. cur } end
        cur, start = step, bytes
      end
      parts[#parts + 1] = ch
      bytes = bytes + #ch
    end
    marks[#marks + 1] = { sr, start, bytes, "HeaderArt" .. cur }
    lines[#lines + 1] = table.concat(parts)
  end
  return lines, marks
end

---@param key string
---@param value any
function M.set(key, value)
  if defaults[key] == nil or key == "enabled" then return vim.notify("header_art: unknown option " .. key, vim.log.levels.WARN) end
  if key == "piece" and type(pieces[value]) ~= "function" then return vim.notify("header_art: unknown piece " .. tostring(value), vim.log.levels.WARN) end
  if key == "charset" and not charsets[value] then return vim.notify("header_art: unknown charset " .. tostring(value), vim.log.levels.WARN) end
  if type(defaults[key]) == "number" and type(value) ~= "number" then return vim.notify("header_art: " .. key .. " needs a number", vim.log.levels.WARN) end
  cfg[key] = value
  if key == "steps" then
    cfg.steps = math.max(1, math.floor(value))
    set_hl()
  end
  if key == "fps" or key == "animate" then restart() end
  if cfg.enabled then
    if cfg.animate then start() else vim.schedule(safe_draw) end
  end
end

--- Next piece in the list (wraps).
function M.cycle_piece()
  local idx = 1
  for i, name in ipairs(pieces.names) do
    if name == cfg.piece then idx = i end
  end
  local nxt = pieces.names[idx % #pieces.names + 1]
  M.set("piece", nxt)
  save()
  vim.notify("Header art: " .. nxt)
end

---@param opts? header_art.opts
function M.setup(opts)
  cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  load() -- the last picked piece / on-off wins over the spec's defaults
  set_hl()

  local grp = vim.api.nvim_create_augroup("HeaderArt", { clear = true })
  local function visible_start()
    if dashboard_win() then start() end
  end
  vim.api.nvim_create_autocmd("ColorScheme", { group = grp, callback = set_hl })
  vim.api.nvim_create_autocmd("User", { group = grp, pattern = "SnacksDashboardOpened", callback = visible_start })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = grp,
    callback = function()
      if vim.bo.filetype == "snacks_dashboard" then start() end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout" }, {
    group = grp,
    callback = function(ev)
      if vim.bo[ev.buf].filetype == "snacks_dashboard" then
        vim.schedule(function()
          if not dashboard_win() then stop() end
        end)
      end
    end,
  })
  vim.api.nvim_create_autocmd("FocusLost", { group = grp, callback = stop })
  vim.api.nvim_create_autocmd("FocusGained", { group = grp, callback = visible_start })
  -- A still frame has no timer, so repaint when snacks re-renders or the size changes.
  vim.api.nvim_create_autocmd({ "User", "VimResized", "WinResized" }, {
    group = grp,
    callback = function(ev)
      if cfg.enabled and not cfg.animate and dashboard_win() and (ev.event ~= "User" or ev.match == "SnacksDashboardUpdatePost") then
        vim.schedule(safe_draw)
      end
    end,
  })

  vim.api.nvim_create_user_command("HeaderArt", function(a)
    local sub, arg = a.fargs[1], a.fargs[2]
    if sub == nil or sub == "pick" then return require("header_art.picker").open() end
    if sub == "toggle" then return M.toggle() end
    if sub == "halo" then return M.set("halo", not cfg.halo) end
    if sub == "animate" then return M.set("animate", not cfg.animate) end
    if sub == "next" then return M.cycle_piece() end
    local num = tonumber(arg)
    M.set(sub, (sub == "piece" or sub == "charset") and arg or num)
  end, {
    nargs = "*",
    desc = "Dashboard background art: pick | toggle | next | halo | animate | piece X | charset X | fps N | speed X | brightness X",
    complete = function(_, line)
      local parts = vim.split(line, "%s+")
      if #parts <= 2 then
        return { "pick", "toggle", "next", "halo", "animate", "piece", "charset", "fps", "speed", "brightness", "steps" }
      end
      if parts[2] == "piece" then return pieces.names end
      if parts[2] == "charset" then return charset_names end
      return {}
    end,
  })

  vim.keymap.set("n", "<leader>ua", function() M.toggle() end, { desc = "Toggle dashboard background art" })
  vim.keymap.set("n", "<leader>uA", function() require("header_art.picker").open() end, { desc = "Pick dashboard art (live preview, persisted)" })

  visible_start()
end

return M
