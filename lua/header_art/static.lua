-- The low-redraw dashboard ("hud-static" piece, issue #44).
--
-- The animated pieces repaint the whole window 30 times a second (header_art/
-- init.lua draw()): ~300 KiB/s to the terminal for a dashboard nobody is
-- touching. This renderer works the other way round: the layout is computed
-- once (on open, resize, colorscheme), every module owns a rectangle, and a
-- module is re-rendered only when it is *due* (`every` seconds) or *dirty* (an
-- autocmd it listens to fired). Even then a row's extmark is rewritten only when
-- its rendered text differs from the last one, so Neovim's grid diff sends the
-- terminal only the cells that really changed. Nothing runs while the
-- dashboard is hidden or Neovim is unfocused.
--
-- Like the HUD's clock panel it paints over a block of no-break spaces that the
-- snacks sections reserve (header_art.content_size()), so snacks keeps owning
-- the buffer text and centring. Modules live in header_art/static_mods/<id>.lua
-- (see static_util.lua for the line format).

local colors = require("defaults.colors")
local U = require("header_art.static_util")

local uv = vim.uv or vim.loop
local M = {}

local ns = vim.api.nvim_create_namespace("header_art_static")
local NBSP = "\u{a0}"

---@class header_art.static.opts
M.opts = {
  -- which modules exist on the dashboard (a module also hides itself when it has nothing to show)
  modules = {
    clock = true, continue = true, recent = true, notes = true, project = true, github = true, sessions = true,
    todo = true, editor = true, log = true, system = true, activity = true, tip = true, keys = true,
  },
  width = 96, -- content width when the window is wide enough for two columns
  min_cols = 100, -- narrower windows get one column
  weights = { 50, 46 }, -- the two columns
  left = { "continue", "recent", "notes" },
  right = { "github", "sessions", "todo" },
  -- the rest fill whichever column is shorter, in this order
  extras = { "project", "editor", "log", "system", "activity", "tip" },
  -- when the window is too short, modules are dropped in this order
  drop = { "notes", "recent", "project", "tip", "activity", "system", "editor", "continue", "log", "todo", "sessions", "github" },
  margin = 4, -- rows kept free above/below the block
  live_dot = true, -- a dot in the corner that toggles once a second (the clock module)
  notes_file = vim.fn.stdpath("data") .. "/dashboard-notes.md",
  boot = "wipe", -- how the dashboard appears: wipe | cascade | sweep | type | none (`:HeaderArt boot <style>` replays)
}
M.W = M.opts.width

---------------------------------------------------------------------------
-- highlights: one group per class, derived from the active scheme
---------------------------------------------------------------------------

local palette, hl_cache = nil, {}

local function make_palette()
  local fg = colors.fg("Normal") or 0xd0d0d0
  -- the scheme's own background, also in transparent mode: dimmed tones blend toward
  -- it, which is right for light schemes too (terminal_bg is a dark grey)
  local bg = colors.bg()
  local accent = colors.accent() or fg
  local dim = colors.fg("Comment") or colors.blend(fg, bg, 0.45)
  return {
    fg = fg,
    dim = dim,
    mid = colors.blend(fg, bg, 0.64),
    faint = colors.blend(dim, bg, 0.42),
    acc = accent,
    ok = colors.fg("GitSignsAdd", "DiagnosticOk", "String") or accent,
    warn = colors.fg("DiagnosticWarn", "WarningMsg") or accent,
    err = colors.fg("DiagnosticError", "ErrorMsg") or accent,
    key_bg = colors.blend(fg, bg, 0.16),
    sel_bg = colors.blend(accent, bg, 0.22),
    flash_bg = colors.blend(accent, bg, 0.45),
  }
end

local function hlgroup(class)
  if class == nil or class == "" then class = "fg" end
  local g = hl_cache[class]
  if g then return g end
  palette = palette or make_palette()
  local fg, bg, bold
  for tok in class:gmatch("%S+") do
    if tok == "b" then bold = true
    elseif tok == "sel" then bg = palette.sel_bg
    elseif tok == "fl" then bg = palette.flash_bg
    elseif tok == "key" then bg, fg = palette.key_bg, fg or palette.fg
    elseif palette[tok] then fg = palette[tok] end
  end
  g = "DashStatic_" .. (class:gsub("%s+", "_"))
  vim.api.nvim_set_hl(0, g, { fg = fg or palette.fg, bg = bg, bold = bold })
  hl_cache[class] = g
  return g
end

---------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------

-- buf/win: the dashboard; layout: result of build_layout; state[id]: per module
-- { m, id, x, y, w, h, eid, lines, sig, dirty, last }; row0/col0: where the
-- reserved block starts in the buffer / window.
local S = { state = {}, ready = false }

local mod_cache = {}
local function load_module(id)
  if mod_cache[id] == nil then
    local ok, m = pcall(require, "header_art.static_mods." .. id)
    mod_cache[id] = ok and type(m) == "table" and m or false
    if not ok and not tostring(m):find("not found", 1, true) then
      vim.schedule(function() vim.notify("header_art.static: module " .. id .. ": " .. tostring(m), vim.log.levels.WARN) end)
    end
  end
  return mod_cache[id] or nil
end

local function dashboard_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.bo[b].filetype == "snacks_dashboard" then return w, b end
  end
end

local function every_of(m)
  local e = m.every
  if type(e) == "function" then e = e() end
  return e
end

---------------------------------------------------------------------------
-- blocks and layout
---------------------------------------------------------------------------

--- A module's lines at width `w`, each padded to exactly `w` cells: a title row
--- (dim caps, key badge on the right) then the body. `bare` modules (clock,
--- key hints) have no title.
local warned = {}
local function block(m, w)
  -- a broken module shows its error in its own rows instead of taking the dashboard down
  local ok, body = pcall(m.render, w)
  if not ok then
    if not warned[m.id] then
      warned[m.id] = true
      vim.schedule(function() vim.notify("header_art.static: " .. m.id .. ": " .. tostring(body), vim.log.levels.WARN) end)
    end
    body = { U.line({ { "error: " .. tostring(body):gsub("^.-:%d+: ", ""):sub(1, math.max(8, w - 8)), "err" } }) }
  end
  body = body or {}
  local out = {}
  if not m.bare then
    local badge = m.badge and { { "[" .. m.badge .. "]", "acc" } } or {}
    out[1] = U.row({ { m.title or m.id:upper(), "dim" } }, badge, w)
  end
  for _, ln in ipairs(body) do
    out[#out + 1] = { s = U.pad(ln.s, w), act = ln.act }
  end
  return out
end

local function sig_of(ln)
  local parts = {}
  for i, s in ipairs(ln.s) do parts[i] = (s[2] or "") .. "\0" .. s[1] end
  return table.concat(parts, "\1")
end

--- Place the enabled modules in a cols x rows window. Returns
--- `{ W, H, items = { { id, m, x, y, w, lines } } }`.
local function build_layout(cols, rows)
  local o = M.opts
  local two = cols >= o.min_cols
  local W = two and o.width or math.max(40, cols - 4)
  local gap = 2

  local present = {}
  for id, on in pairs(o.modules) do
    if on then
      local m = load_module(id)
      if m and (not m.available or select(2, pcall(m.available))) then present[id] = m end
    end
  end
  local dropped, drop_i = {}, 0

  local function place()
    local items = {}
    local function item(id, x, y, w)
      local m = present[id]
      local lines = block(m, w)
      items[#items + 1] = { id = id, m = m, x = x, y = y, w = w, lines = lines }
      return #lines
    end
    local y = 0
    if present.clock and not dropped.clock then y = item("clock", 0, 0, W) + 1 end

    local function alive(ids)
      local out = {}
      for _, id in ipairs(ids) do
        if present[id] and not dropped[id] and not present[id].bare then out[#out + 1] = id end
      end
      return out
    end
    local left, right = alive(o.left), alive(o.right)
    local extras = alive(o.extras)
    local bottom = present.clock and not dropped.clock and y - 2 or -1 -- last used row
    if two then
      local lw = math.floor((W - gap) * o.weights[1] / (o.weights[1] + o.weights[2]))
      local rw = W - gap - lw
      local cl, cr = { ids = left, h = 0, x = 0, w = lw }, { ids = right, h = 0, x = lw + gap, w = rw }
      for _, c in ipairs({ cl, cr }) do
        for _, id in ipairs(c.ids) do c.h = c.h + #block(present[id], c.w) + 1 end
      end
      for _, id in ipairs(extras) do
        local c = cl.h <= cr.h and cl or cr
        c.ids[#c.ids + 1] = id
        c.h = c.h + #block(present[id], c.w) + 1
      end
      for _, c in ipairs({ cl, cr }) do
        local cy = y
        for _, id in ipairs(c.ids) do cy = cy + item(id, c.x, cy, c.w) + 1 end
        bottom = math.max(bottom, cy - 2)
      end
    else
      local cy = y
      for _, list in ipairs({ left, right, extras }) do
        for _, id in ipairs(list) do cy = cy + item(id, 0, cy, W) + 1 end
      end
      bottom = cy - 2
    end
    if present.keys and not dropped.keys then
      local ky = bottom + 2
      local n = item("keys", 0, ky, W)
      bottom = ky + n - 1
    end
    return items, bottom + 1
  end

  local items, H = place()
  local limit = math.max(8, rows - o.margin)
  while H > limit and drop_i < #o.drop do
    drop_i = drop_i + 1
    dropped[o.drop[drop_i]] = true
    items, H = place()
  end
  return { W = W, H = H, items = items, cols = cols, rows = rows }
end

local function window_dims()
  local win = dashboard_win()
  if win then
    local info = vim.fn.getwininfo(win)[1]
    return info.width - info.textoff, info.height
  end
  -- Before the window exists (snacks renders the section first): the editor area
  -- without the command line, statusline and tabline, so the block is sized for the
  -- window it is about to get and the layout is not redone a moment later.
  local lines = vim.o.lines - vim.o.cmdheight
  if vim.o.laststatus > 0 then lines = lines - 1 end
  if vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1) then lines = lines - 1 end
  return vim.o.columns, lines
end

--- Size of the block the snacks sections must reserve (header_art.content_size()).
function M.size()
  local cols, rows = window_dims()
  local L = build_layout(cols, rows)
  return L.W, L.H
end

---------------------------------------------------------------------------
-- drawing
---------------------------------------------------------------------------

local function placeholder_origin(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local r0, c0, n
  for i, line in ipairs(lines) do
    local s = line:find(NBSP, 1, true)
    if s then
      if not r0 then r0, c0, n = i - 1, vim.api.nvim_strwidth(line:sub(1, s - 1)), 0 end
      n = n + 1
    elseif r0 then
      break
    end
  end
  return r0, c0, n
end

--- The first `cells` cells of a row's segments; the last `lead` of them in the
--- accent, like the head of a wipe. Used while the dashboard is revealing itself.
local function cut(segs, cells, lead)
  local out, n = {}, 0
  for _, seg in ipairs(segs) do
    local text, class = seg[1], seg[2] or ""
    local len = vim.fn.strchars(text)
    if n >= cells then break end
    local take = math.min(len, cells - n)
    local from = n -- cells before this segment
    local plain = math.max(0, math.min(take, (cells - lead) - from))
    if plain > 0 then out[#out + 1] = { vim.fn.strcharpart(text, 0, plain), hlgroup(class) } end
    if take > plain then out[#out + 1] = { vim.fn.strcharpart(text, plain, take - plain), hlgroup("acc b") } end
    n = n + take
  end
  return out
end

local function draw_row(st, i, flash, cells, lead)
  local buf = S.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) or not S.row0 then return end
  local ln = st.lines[i]
  if not ln then return end
  local selected = S.sel and S.sel.id == st.id and S.sel.i == i
  local virt = {}
  if cells then
    virt = cut(ln.s, cells, lead or 0)
  else
    for _, seg in ipairs(ln.s) do
      local class = seg[2] or ""
      if flash then class = class .. " fl" elseif selected then class = class .. " sel" end
      virt[#virt + 1] = { seg[1], hlgroup(class) }
    end
  end
  if #virt == 0 then
    pcall(vim.api.nvim_buf_del_extmark, buf, ns, st.eid + i)
    return
  end
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, S.row0 + st.y + i - 1, 0, {
    id = st.eid + i,
    virt_text = virt,
    virt_text_pos = "overlay",
    virt_text_win_col = S.col0 + st.x,
  })
end

local function draw_all()
  if not S.layout or not S.row0 then return end
  vim.api.nvim_buf_clear_namespace(S.buf, ns, 0, -1)
  for _, st in pairs(S.state) do
    for i = 1, #st.lines do draw_row(st, i) end
  end
end

local function build(buf, win, cols, rows)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local L = build_layout(cols, rows)
  S.buf, S.win, S.layout, S.cols, S.rows = buf, win, L, cols, rows
  S.state = {}
  for idx, it in ipairs(L.items) do
    local st = { id = it.id, m = it.m, x = it.x, y = it.y, w = it.w, h = #it.lines, eid = idx * 1000, lines = it.lines, sig = {}, dirty = false, last = uv.now() }
    for i, ln in ipairs(it.lines) do st.sig[i] = sig_of(ln) end
    S.state[it.id] = st
  end
  M.W = L.W
  if S.booting then S.boot_rebuilt = true end -- the reveal's tick re-orders the new modules
  return L
end

local function reserved_rows_differ()
  local r0, _, n = placeholder_origin(S.buf)
  return not r0 or n ~= S.layout.H
end

local function request_dashboard_update()
  if S.updating then return end
  S.updating = true
  vim.schedule(function()
    S.updating = false
    if _G.Snacks and Snacks.dashboard and dashboard_win() then Snacks.dashboard.update() end
  end)
end

local function relayout()
  local win, buf = dashboard_win()
  if not win then return end
  local cols, rows = window_dims()
  build(buf, win, cols, rows)
  if reserved_rows_differ() then
    request_dashboard_update() -- UpdatePost comes back through attach()
  else
    S.row0, S.col0 = placeholder_origin(buf)
    draw_all()
  end
end

---------------------------------------------------------------------------
-- refreshing
---------------------------------------------------------------------------

local function refresh_module(st)
  -- a module that has nothing left to show leaves the layout
  if st.m.available and not st.m.available() then return relayout() end
  local lines = block(st.m, st.w)
  if #lines ~= st.h then return relayout() end
  for i, ln in ipairs(lines) do
    local sig = sig_of(ln)
    if sig ~= st.sig[i] then
      st.lines[i], st.sig[i] = ln, sig
      local flash = S.ready and not st.m.noflash
      draw_row(st, i, flash)
      if flash then
        vim.defer_fn(function()
          if S.state[st.id] == st and st.sig[i] == sig then draw_row(st, i) end
        end, 700)
      end
    end
  end
end

local function flush()
  S.flush_pending = false
  if not (S.buf and vim.api.nvim_buf_is_valid(S.buf)) or S.booting or not S.row0 then return end
  if S.need_layout then
    S.need_layout = false
    return relayout()
  end
  local ids = {}
  for id, st in pairs(S.state) do
    if st.dirty then ids[#ids + 1] = id end
  end
  for _, id in ipairs(ids) do
    local st = S.state[id]
    if st then
      st.dirty = false
      st.last = uv.now()
      refresh_module(st)
    end
  end
end

local function schedule_flush()
  if S.flush_pending then return end
  S.flush_pending = true
  vim.schedule(flush)
end

local function visible()
  local win, buf = dashboard_win()
  return win ~= nil and buf == S.buf
end

local function tick()
  if not visible() then return M.pause() end
  local now = uv.now()
  for _, st in pairs(S.state) do
    local e = every_of(st.m)
    if e and now - st.last >= e * 1000 - 60 then st.dirty = true end
  end
  schedule_flush()
end

local function min_interval()
  local iv
  for _, st in pairs(S.state) do
    local e = every_of(st.m)
    if e and (not iv or e < iv) then iv = e end
  end
  return iv
end

local function timer_stop()
  if S.timer then
    S.timer:stop()
    S.timer:close()
    S.timer = nil
  end
end

local function timer_start()
  if S.timer then return end
  local iv = min_interval()
  if not iv then return end
  local period = math.max(1, math.floor(iv * 1000))
  local sec, usec = uv.gettimeofday()
  local now_ms = sec * 1000 + math.floor(usec / 1000)
  S.timer_iv = iv
  S.timer = uv.new_timer()
  S.timer:start(period - (now_ms % period), period, vim.schedule_wrap(tick)) -- aligned to the clock
end

---------------------------------------------------------------------------
-- selection and <CR>
---------------------------------------------------------------------------

local function row_at(row, col)
  for _, st in pairs(S.state) do
    local y0 = S.row0 + st.y
    if row >= y0 and row < y0 + st.h and col >= S.col0 + st.x and col < S.col0 + st.x + st.w then
      return st, row - y0 + 1
    end
  end
end

local function cursor_hit()
  if not (S.win and vim.api.nvim_win_is_valid(S.win)) or not S.row0 then return end
  local cur = vim.api.nvim_win_get_cursor(S.win)
  local virt = vim.api.nvim_win_call(S.win, function() return vim.fn.virtcol(".") end) - 1
  local st, i = row_at(cur[1] - 1, virt)
  if st and st.lines[i] and st.lines[i].act then return st, i end
end

local function on_cursor()
  local st, i = cursor_hit()
  local old = S.sel
  S.sel = st and { id = st.id, i = i } or nil
  local function same(a, b) return (a and a.id) == (b and b.id) and (a and a.i) == (b and b.i) end
  if same(old, S.sel) then return end
  if old and S.state[old.id] then draw_row(S.state[old.id], old.i) end
  if S.sel then draw_row(st, i) end
end

local function on_enter()
  local st, i = cursor_hit()
  if not st then return end
  local act = st.lines[i].act
  local ok, err = pcall(act)
  if not ok then vim.notify("dashboard: " .. tostring(err), vim.log.levels.WARN) end
end

---------------------------------------------------------------------------
-- autocmds
---------------------------------------------------------------------------

local grp
local function mark(ids)
  for _, id in ipairs(ids) do
    local st = S.state[id]
    if st then
      st.dirty = true
    elseif M.opts.modules[id] then
      -- not on the dashboard yet: it may have something to show now
      local m = load_module(id)
      if m and (not m.available or m.available()) then S.need_layout = true end
    end
  end
  schedule_flush()
end

local function setup_autocmds()
  if grp then return end
  grp = vim.api.nvim_create_augroup("HeaderArtStatic", { clear = true })
  local function au(ev, opts) vim.api.nvim_create_autocmd(ev, vim.tbl_extend("force", { group = grp }, opts)) end

  au("ColorScheme", {
    callback = function()
      palette, hl_cache = nil, {}
      vim.schedule(function()
        if S.layout and S.row0 then draw_all() end
      end)
    end,
  })
  au({ "VimResized", "WinResized" }, {
    callback = function()
      if visible() then vim.schedule(function() if visible() then M.attach() end end) end
    end,
  })
  au("User", {
    pattern = "SnacksDashboardUpdatePost",
    -- snacks rewrote the buffer lines, which collapses our extmarks: redraw them
    callback = function() vim.schedule(function() M.attach(true) end) end,
  })

  -- every module's own triggers
  local by_event = {}
  for id, on in pairs(M.opts.modules) do
    local m = on and load_module(id)
    for _, spec in ipairs(m and m.on or {}) do
      by_event[spec] = by_event[spec] or {}
      table.insert(by_event[spec], id)
    end
  end
  for spec, ids in pairs(by_event) do
    local ev, pat = spec:match("^(%S+)%s+(%S+)$")
    au(ev or spec, { pattern = pat, callback = function() mark(ids) end })
  end
end

---------------------------------------------------------------------------
-- public api
---------------------------------------------------------------------------

--- Stop the timer (focus lost, dashboard hidden). The extmarks stay.
function M.pause()
  timer_stop()
end

--- Remove everything and stop (another piece was chosen, or the art is off).
function M.detach()
  timer_stop()
  if S.buf and vim.api.nvim_buf_is_valid(S.buf) then
    vim.api.nvim_buf_clear_namespace(S.buf, ns, 0, -1)
    pcall(vim.keymap.del, "n", "<CR>", { buffer = S.buf })
  end
  if grp then
    pcall(vim.api.nvim_del_augroup_by_id, grp)
    grp = nil
  end
  S = { state = {}, ready = false }
end

-- Reveal styles. Each gives a row its start time (ms after the sweep begins) and
-- how long the row takes to appear (0 = at once); `lead` cells at the head of a
-- row are drawn in the accent. y = row in the block (0-based), i = row in its
-- module, k = the module's order top-to-bottom, left-to-right.
M.reveal_styles = {
  -- whole rows appear top to bottom
  sweep = { t0 = function(st, i, y) return y * 26 end, dur = 0, lead = 0 },
  -- a diagonal wipe: every row is drawn left to right, each starting a little after
  -- the one above, so the picture arrives from the top-left corner with a bright edge
  wipe = { t0 = function(st, i, y) return y * 22 + st.x * 3 end, dur = 340, lead = 3 },
  -- modules come in one after another, each typed out quickly
  cascade = { t0 = function(st, i, y, k) return (k - 1) * 90 + (i - 1) * 34 end, dur = 200, lead = 2 },
  -- line by line, each typed left to right (slow, like a terminal)
  type = { t0 = function(st, i, y) return y * 40 end, dur = 240, lead = 1 },
  none = { t0 = function() return 0 end, dur = 0, lead = 0 },
}
M.reveal_names = { "wipe", "cascade", "sweep", "type", "none" }

--- Module order top-to-bottom, left-to-right (the `cascade` reveal's `k`), and fresh
--- per-row reveal counters.
local function assign_order()
  local order = {}
  for _, st in pairs(S.state) do order[#order + 1] = st end
  table.sort(order, function(a, b) if a.y ~= b.y then return a.y < b.y end return a.x < b.x end)
  for k, st in ipairs(order) do st.k, st.bc = k, {} end
end

local function boot_end(style)
  local last = 0
  for _, st in pairs(S.state) do
    for i = 1, st.h do last = math.max(last, style.t0(st, i, st.y + i - 1, st.k or 1) + style.dur) end
  end
  return last
end

local function boot()
  if S.booted then return end
  local style = M.reveal_styles[M.opts.boot] or M.reveal_styles.wipe
  S.booted, S.booting = true, true
  assign_order()
  vim.api.nvim_buf_clear_namespace(S.buf, ns, 0, -1)
  local finish_at, t0 = boot_end(style), uv.now()
  S.boot_redraw = false
  local timer = uv.new_timer()
  timer:start(0, 28, vim.schedule_wrap(function()
    if not (S.buf and vim.api.nvim_buf_is_valid(S.buf)) or not S.row0 then
      timer:stop()
      timer:close()
      S.booting = false
      return
    end
    local t = uv.now() - t0
    if S.boot_rebuilt then
      -- the window changed size (or a module appeared) mid-reveal: carry on with the new layout
      S.boot_rebuilt, S.boot_redraw = false, true
      assign_order()
    end
    for _, st in pairs(S.state) do
      st.bc = st.bc or {}
      for i = 1, st.h do
        local start = style.t0(st, i, st.y + i - 1, st.k or 1)
        local p = style.dur == 0 and (t >= start and 1 or 0) or math.max(0, math.min(1, (t - start) / style.dur))
        local cells = math.floor(p * st.w + 0.5)
        -- a redraw after snacks rewrote the text repaints every row that has started
        if cells ~= st.bc[i] or (S.boot_redraw and cells > 0) then
          st.bc[i] = cells
          if cells >= st.w then draw_row(st, i) else draw_row(st, i, false, cells, style.lead) end
        end
      end
    end
    S.boot_redraw = false
    if t >= finish_at then
      timer:stop()
      timer:close()
      S.booting, S.ready = false, true
      flush()
    end
  end))
end

--- Play the reveal again, optionally in another style (`:HeaderArt boot [style]`).
function M.replay(style)
  if style then
    if not M.reveal_styles[style] then return vim.notify("header_art: unknown reveal " .. style, vim.log.levels.WARN) end
    M.opts.boot = style
  end
  if not (S.layout and S.row0 and not S.booting) then return end
  S.booted = false
  S.ready = false
  boot()
end

--- Show the dashboard (or catch up after a pause; `force` redraws every row, needed
--- after snacks rewrote the buffer text): measure the reserved block,
--- lay out if the window changed, draw what is not on screen, start the timer.
--- Cheap when nothing changed, so every dashboard event can call it.
function M.attach(force)
  local win, buf = dashboard_win()
  if not win then return false end
  local r0, c0, n = placeholder_origin(buf)
  if not r0 then return false end -- snacks has not rendered the block yet (UpdatePost calls again)
  setup_autocmds()
  local cols, rows = window_dims()
  local fresh = S.buf ~= buf or not S.layout or S.cols ~= cols or S.rows ~= rows
  if fresh then build(buf, win, cols, rows) end
  S.win = win
  if n ~= S.layout.H then return request_dashboard_update() end
  local moved = S.row0 ~= r0 or S.col0 ~= c0
  S.row0, S.col0 = r0, c0

  vim.keymap.set("n", "<CR>", on_enter, { buffer = buf, nowait = true, desc = "Dashboard: open the row under the cursor" })
  if not S.cursor_au then
    S.cursor_au = true
    vim.api.nvim_create_autocmd("CursorMoved", { group = grp, buffer = buf, callback = on_cursor })
  end

  if fresh and not S.booted and not vim.g.header_art_static_noboot then
    boot()
  elseif S.booting then
    -- snacks rewrote the text mid-reveal (its UpdatePost): the next tick puts back the
    -- rows shown so far and the reveal carries on, instead of jumping to the finished picture
    if fresh or moved or force then S.boot_redraw = true end
  elseif fresh or moved or force then
    draw_all()
    S.ready = true
  end
  -- anything that may have changed while paused gets re-rendered once
  for _, st in pairs(S.state) do st.dirty = true end
  schedule_flush()
  timer_stop()
  timer_start()
  return true
end

--- Re-render modules by id (for data that arrives asynchronously).
---@param ids string[]
function M.invalidate(ids)
  if S.layout then mark(ids) end
end

---@param opts? header_art.static.opts
function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
  M.W = M.opts.width
end

--- Test/inspection hook: the current layout and per-module rows.
function M._state() return S end

return M
