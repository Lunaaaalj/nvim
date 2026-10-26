-- The player: a library browser float (tabs Playlists / Artists / Albums /
-- Songs / Queue, drill in with l, back with h, live filter with /) above a
-- now-playing card. The card's album art is a third, borderless float over the
-- card's left padding, because snacks.image draws an image over a whole buffer.
--
-- Navigation (tab, drill-down stack, cursor, filter) survives closing the
-- float, so reopening lands where you left.
local music = require("music")
local lib = require("music.library")

local M = {}

local ns = vim.api.nvim_create_namespace("music_ui")
local ART_ROWS = 7
local CARD_H = ART_ROWS + 2

local TABS = { "Playlists", "Artists", "Albums", "Songs", "Queue" }
local QUEUE_TAB = 5

-- stacks[tab] = list of views; a view is
-- { title, items, cursor, filter, loading, numbered }
local nav = { tab = 2, stacks = {} }
local ui = {}

local function valid_win(w) return w and vim.api.nvim_win_is_valid(w) end
local function valid_buf(b) return b and vim.api.nvim_buf_is_valid(b) end
local function width(s) return vim.fn.strdisplaywidth(s) end

local function scratch()
  local b = vim.api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = "wipe"
  return b
end

local function fit(text, w)
  text = text or ""
  if w <= 0 then return "" end
  if width(text) <= w then return text end
  local n = vim.fn.strchars(text)
  while n > 0 and width(vim.fn.strcharpart(text, 0, n)) > w - 1 do n = n - 1 end
  return vim.fn.strcharpart(text, 0, n) .. "…"
end

-- Columns that make `rows` rows of art square on screen.
local function art_cols(rows)
  local ok, px = pcall(function() return Snacks.image.terminal.size() end)
  local ratio = ok and px.cell_width > 0 and px.cell_height / px.cell_width or 2
  return math.floor(rows * ratio + 0.5)
end

-- `text` cut or padded to exactly `w` cells.
local function cell(text, w)
  text = fit(text, w)
  return text .. (" "):rep(math.max(0, w - width(text)))
end

-- Rows of { text, hl } segments → buffer lines + highlight extmarks.
local function draw(buf, rows, pad)
  pad = pad or ""
  local lines, marks = {}, {}
  for i, segs in ipairs(rows) do
    local line = pad
    for _, seg in ipairs(segs) do
      local start = #line
      line = line .. seg[1]
      if seg[2] then marks[#marks + 1] = { i - 1, start, #line, seg[2] } end
    end
    lines[i] = #segs > 0 and line or ""
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
end

---------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------

local function item(kind, data, ctx)
  local search = kind == "song" and table.concat({ data.name, data.artist, data.album }, " ")
    or kind == "album" and (data.name .. " " .. data.artist)
    or data.name
  return { kind = kind, data = data, ctx = ctx, search = search:lower() }
end

local function songs(list, ctx)
  return vim.tbl_map(function(t) return item("song", t, ctx) end, list)
end

local function ids(tracks)
  return vim.tbl_map(function(t) return t.id end, tracks)
end

local function stack() return nav.stacks[nav.tab] end
local function view()
  local s = stack()
  return s and s[#s]
end

-- Items of `v` matching its filter: every word must appear somewhere.
local function visible(v)
  if not v.filter or v.filter == "" then return v.items end
  local words = vim.split(v.filter:lower(), "%s+", { trimempty = true })
  return vim.tbl_filter(function(it)
    for _, w in ipairs(words) do
      if not it.search:find(w, 1, true) then return false end
    end
    return true
  end, v.items)
end

local render_list

-- A view whose items arrive asynchronously; `fill(cb)` hands them over.
local function async_view(title, fill, extra)
  local v = vim.tbl_extend("force", { title = title, items = {}, cursor = 1, filter = "", loading = true }, extra or {})
  fill(function(items)
    v.items, v.loading = items, false
    render_list()
  end)
  return v
end

-- Album/playlist views are cover grids (when the terminal can draw images).
local GRID = { grid = true }

local roots = {
  function() -- Playlists
    return async_view(nil, function(cb)
      lib.playlists(function(pls)
        cb(vim.tbl_map(function(p) return item("playlist", p) end, pls))
      end)
    end, GRID)
  end,
  function() -- Artists
    return async_view(nil, function(cb)
      lib.load(function() cb(vim.tbl_map(function(a) return item("artist", a) end, lib.artists)) end)
    end)
  end,
  function() -- Albums
    return async_view(nil, function(cb)
      lib.load(function() cb(vim.tbl_map(function(a) return item("album", a) end, lib.albums)) end)
    end, GRID)
  end,
  function() -- Songs: played in library order context
    return async_view(nil, function(cb)
      lib.load(function() cb(songs(lib.songs, { mode = "library" })) end)
    end)
  end,
  function() -- Queue
    return async_view(nil, function(cb)
      lib.tracks("queue", function(list) cb(songs(list, { mode = "queue" })) end)
    end)
  end,
}

local function album_view(al)
  return {
    title = al.name,
    items = songs(al.tracks, { mode = "list", ids = ids(al.tracks) }),
    cursor = 1,
    filter = "",
    numbered = true,
  }
end

local function set_tab(i, fresh)
  nav.tab = (i - 1) % #TABS + 1
  if fresh or not nav.stacks[nav.tab] then nav.stacks[nav.tab] = { roots[nav.tab]() } end
  render_list()
end

-- The queue changed: rebuild its tab now if it's showing, else on next visit.
local function queue_changed()
  if nav.tab == QUEUE_TAB then set_tab(QUEUE_TAB, true) else nav.stacks[QUEUE_TAB] = nil end
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

-- In a grid `v.cursor` is the tile index; in a list it's the cursor line.
local function selected()
  local v = view()
  if not v or not valid_win(ui.win) then return end
  local list = visible(v)
  return list[ui.grid and v.cursor or vim.api.nvim_win_get_cursor(ui.win)[1]], v
end

local function push(v)
  stack()[#stack() + 1] = v
  render_list()
end

local function play(it)
  if not it then return end
  local d, ctx = it.data, it.ctx
  if it.kind == "playlist" then
    music.play(d.id)
  elseif it.kind == "album" or it.kind == "artist" then
    music.queue_set(1, ids(d.tracks), queue_changed)
  elseif ctx.mode == "playlist" then
    music.play(ctx.id, d.id)
  elseif ctx.mode == "library" or ctx.mode == "queue" then
    music.play(ctx.mode, d.id)
  else -- a song inside an album: queue the album, start from this song
    music.queue_set(vim.fn.index(ctx.ids, d.id) + 1, ctx.ids, queue_changed)
  end
end

local function open(it)
  if not it then return end
  if it.kind == "playlist" then
    push(async_view(it.data.name, function(cb)
      lib.tracks(it.data.id, function(list) cb(songs(list, { mode = "playlist", id = it.data.id })) end)
    end))
  elseif it.kind == "artist" then
    push({
      title = it.data.name,
      items = vim.tbl_map(function(a) return item("album", a) end, it.data.albums),
      cursor = 1,
      filter = "",
      grid = true,
    })
  elseif it.kind == "album" then
    push(album_view(it.data))
  else
    play(it)
  end
end

local function back()
  local s = stack()
  if #s > 1 then
    s[#s] = nil
    render_list()
  end
end

local function enqueue(it)
  if not it then return end
  local function add(list)
    music.queue_add(ids(list), queue_changed)
    vim.notify(("Music: queued %s"):format(#list == 1 and list[1].name or (#list .. " songs")))
  end
  if it.kind == "song" then
    add({ it.data })
  elseif it.kind == "playlist" then
    lib.tracks(it.data.id, add)
  else
    add(it.data.tracks)
  end
end

-- Jump to the playing song inside its album.
local function reveal()
  local t = music.state.track
  if not t then return end
  lib.load(function()
    local full = lib.by_id[t.id]
    local al = full and lib.album(full)
    if not al then return vim.notify("Music: the playing song isn't in the library") end
    nav.tab = 3
    local root = nav.stacks[3] and nav.stacks[3][1] or roots[3]()
    local v = album_view(al)
    for i, it in ipairs(v.items) do
      if it.data.id == t.id then v.cursor = i end
    end
    nav.stacks[3] = { root, v }
    render_list()
  end)
end

---------------------------------------------------------------------------
-- Library list
---------------------------------------------------------------------------

local function now_id() return music.state.track and music.state.track.id end

local function row(it, w, numbered)
  local d = it.data
  if it.kind == "song" then
    local playing = d.id == now_id()
    local segs = { { playing and "󰐊 " or "  ", "MusicAccent" } }
    local name_hl = playing and "MusicAccent" or nil
    local time = ("  %5s"):format(music.fmt_time(d.duration))
    local rest = w - 2 - #time
    if numbered then
      local n = (d.track or 0) > 0 and ("%3d  "):format(d.track) or "     "
      vim.list_extend(segs, { { n, "MusicMuted" }, { cell(d.name, rest - #n), name_hl } })
    else
      local nw, aw = math.floor(rest * 0.45), math.floor(rest * 0.27)
      vim.list_extend(segs, {
        { cell(d.name, nw), name_hl }, { "  " },
        { cell(d.artist, aw), "MusicMuted" }, { "  " },
        { cell(d.album, rest - nw - aw - 4), "MusicMuted" },
      })
    end
    segs[#segs + 1] = { time, "MusicMuted" }
    return segs
  elseif it.kind == "album" then
    local year = d.year > 0 and tostring(d.year) or ""
    local nw = math.floor((w - 8) * 0.6)
    return {
      { "  " }, { cell(d.name, nw) }, { "  " },
      { cell(d.artist, w - nw - 10 - 2), "MusicMuted" }, { ("%6s"):format(year), "MusicMuted" },
    }
  elseif it.kind == "artist" then
    local info = ("%d album%s · %d"):format(#d.albums, #d.albums == 1 and "" or "s", #d.tracks)
    return { { "  " }, { cell(d.name, w - 2 - width(info) - 2) }, { "  " .. info, "MusicMuted" } }
  end
  return { { "  " }, { cell(d.name, w - 2) } }
end

local function esc(s) return (s:gsub("%%", "%%%%")) end

local function winbar(v, n)
  local parts = { " " }
  for i, name in ipairs(TABS) do
    parts[#parts + 1] = (i == nav.tab and "%#MusicTitle#" or "%#MusicMuted#") .. name .. "%*  "
  end
  for i = 2, #stack() do
    parts[#parts + 1] = "%#MusicMuted#› %*" .. esc(fit(stack()[i].title or "", 30)) .. " "
  end
  parts[#parts + 1] = "%="
  if v.filter ~= "" then parts[#parts + 1] = "%#MusicAccent#/" .. esc(v.filter) .. "%*  " end
  parts[#parts + 1] = "%#MusicMuted#" .. (v.loading and "…" or n) .. " "
  return table.concat(parts)
end

---------------------------------------------------------------------------
-- Cover grid
---------------------------------------------------------------------------
-- Each tile is GRID_ART rows of art, a title and a subtitle. The covers are
-- snacks "inline" placements whose range spans the art rows: snacks then draws
-- every image row as an overlay at a fixed window column, so covers sit side
-- by side and, being placeholder text, scroll with the buffer for free.

local GRID_ART = 7
local ns_sel = vim.api.nvim_create_namespace("music_ui_sel")

local function grid_supported()
  return Snacks and Snacks.image and Snacks.image.supports_terminal()
end

-- Song id whose artwork stands for an album or playlist.
local function cover_id(it)
  if it.kind == "album" then return it.data.tracks[1] and it.data.tracks[1].id end
  return it.data.first
end

local function clear_covers()
  if valid_buf(ui.buf) and Snacks and Snacks.image then
    pcall(Snacks.image.placement.clean, ui.buf)
  end
end

-- Tile `k` (1-based) → top line (1-based) and left column (bytes = cells:
-- the art rows a cover anchors on are plain spaces).
local function tile_pos(g, k)
  local r, c = math.floor((k - 1) / g.per), (k - 1) % g.per
  return r * g.th + 1, g.pad + c * (g.aw + g.gap)
end

local function set_footer(text)
  if valid_win(ui.win) and ui.footer ~= text then
    ui.footer = text
    vim.api.nvim_win_set_config(ui.win, { footer = { { text, "MusicMuted" } }, footer_pos = "center" })
  end
end

-- Highlight the selected tile's caption and put the cursor on it, scrolled
-- so its cover is in view.
local function select_tile(v, move_cursor)
  local g = ui.grid
  if not g or not valid_buf(ui.buf) then return end
  vim.api.nvim_buf_clear_namespace(ui.buf, ns_sel, 0, -1)
  local top = tile_pos(g, v.cursor)
  local title = top + GRID_ART
  -- caption byte ranges were recorded while building the lines (titles with
  -- accents or Cyrillic make bytes ≠ cells)
  for i, range in ipairs(g.caps[v.cursor]) do
    vim.api.nvim_buf_set_extmark(ui.buf, ns_sel, title + i - 2, range[1], {
      end_col = range[2], hl_group = i == 1 and "MusicSelTitle" or "MusicSel", priority = 200,
    })
  end
  if move_cursor then
    ui.rendering = true
    pcall(vim.api.nvim_win_set_cursor, ui.win, { title, g.caps[v.cursor][1][1] })
    -- scroll by whole rows of tiles, never through the middle of a cover
    vim.api.nvim_win_call(ui.win, function()
      local fits = math.max(1, math.floor(vim.fn.winheight(0) / g.th))
      local r = math.floor((top - 1) / g.th)
      local first = math.floor((vim.fn.line("w0") - 1) / g.th)
      if r < first then
        first = r
      elseif r >= first + fits then
        first = r - fits + 1
      end
      vim.fn.winrestview({ topline = first * g.th + 1 })
    end)
    ui.rendering = false
  end
end

local function render_grid(v, list)
  local W = vim.api.nvim_win_get_width(ui.win)
  local aw = art_cols(GRID_ART)
  local per = math.max(1, math.floor((W - 1) / (aw + 2)))
  local gap = math.max(2, math.floor((W - 1 - per * aw) / per))
  -- caps[k] = byte ranges of tile k's title and subtitle, for the selection
  local g = { aw = aw, per = per, gap = gap, th = GRID_ART + 3, pad = math.floor(gap / 2), caps = {} }
  ui.grid = g

  local rows, mid = {}, math.ceil(GRID_ART / 2)
  for first = 1, #list, per do
    local tiles = vim.list_slice(list, first, math.min(first + per - 1, #list))
    local function line(fn, caption)
      local segs, at = { { (" "):rep(g.pad) } }, g.pad
      for i, it in ipairs(tiles) do
        local s = fn(it)
        local text = cell(s[1], aw)
        segs[#segs + 1] = { text, s[2] }
        segs[#segs + 1] = { (" "):rep(gap) }
        if caption then
          local k = first + i - 1
          g.caps[k] = g.caps[k] or {}
          table.insert(g.caps[k], { at, at + #text })
        end
        at = at + #text + gap
      end
      rows[#rows + 1] = segs
    end
    for r = 1, GRID_ART do
      -- a note until the cover arrives (the cover is drawn over it)
      line(function() return { r == mid and ((" "):rep(math.floor(aw / 2) - 1) .. "󰝚") or "", "MusicMuted" } end)
    end
    line(function(it) return { it.data.name, "MusicTitle" } end, true)
    line(function(it)
      return { it.kind == "album" and it.data.artist or (it.data.kind == "none" and "Playlist" or it.data.kind or ""), "MusicMuted" }
    end, true)
    rows[#rows + 1] = {}
  end
  clear_covers()
  draw(ui.buf, rows)
  vim.wo[ui.win].cursorline = false
  -- the global scrolloff=8 would re-scroll after select_tile snaps to a row
  vim.wo[ui.win].scrolloff = 0
  v.cursor = math.max(1, math.min(v.cursor, #list))
  select_tile(v, true)

  -- covers arrive asynchronously (cached ones at once); a re-render bumps
  -- `gen` so late arrivals for an old layout are dropped
  ui.gen = (ui.gen or 0) + 1
  local gen = ui.gen
  pcall(function() require("pdfview.viewer").fix_snacks_spinner() end)
  for k, it in ipairs(list) do
    local id = cover_id(it)
    if id then
      music.artwork(id, function(png)
        if not png or gen ~= ui.gen or not valid_buf(ui.buf) then return end
        local top, col = tile_pos(g, k)
        Snacks.image.placement.new(ui.buf, png, {
          inline = true,
          conceal = true, -- required for the multi-row overlay path
          pos = { top, col },
          range = { top, col, top + GRID_ART - 1, col + aw },
          width = aw,
          height = GRID_ART,
        })
      end)
    end
  end
end

local LIST_HINTS = " ⏎ play · l/h in/out · a queue · / filter · ⇥ tab · ␣ pause · n/p skip · ? keys "
local GRID_HINTS = " hjkl move · ⏎ open · P play · ⌫ back · a queue · / filter · ⇥ tab · ? keys "

function render_list()
  local v = view()
  -- nil while set_tab builds a root whose data was cached (filled synchronously)
  if not v or not valid_buf(ui.buf) or not valid_win(ui.win) then return end
  local list = visible(v)
  if v.grid and not v.loading and #list > 0 and grid_supported() then
    set_footer(GRID_HINTS)
    render_grid(v, list)
    vim.wo[ui.win].winbar = winbar(v, #list)
    return
  end
  ui.grid = nil
  ui.gen = (ui.gen or 0) + 1
  clear_covers()
  if valid_buf(ui.buf) then vim.api.nvim_buf_clear_namespace(ui.buf, ns_sel, 0, -1) end
  set_footer(LIST_HINTS)
  vim.wo[ui.win].cursorline = true
  vim.wo[ui.win].scrolloff = -1 -- back to the global value
  local w = vim.api.nvim_win_get_width(ui.win) - 1
  local rows = {}
  if v.loading then
    rows[1] = { { "  Loading…", "MusicMuted" } }
  elseif #list == 0 then
    rows[1] = { { v.filter ~= "" and "  No match" or "  Empty", "MusicMuted" } }
  end
  for i, it in ipairs(list) do rows[i] = row(it, w, v.numbered) end
  draw(ui.buf, rows)
  vim.wo[ui.win].winbar = winbar(v, #list)
  ui.rendering = true
  pcall(vim.api.nvim_win_set_cursor, ui.win, { math.max(1, math.min(v.cursor, #rows)), 0 })
  ui.rendering = false
end

-- Grid: move the selection by `d` tiles.
local function grid_move(d)
  local v = view()
  if not (v and ui.grid) then return end
  v.cursor = math.max(1, math.min(v.cursor + d, #visible(v)))
  select_tile(v, true)
end

-- Grid: the tile under the cursor (after gg, G, <C-d>, a mouse click…).
local function grid_follow_cursor()
  local v, g = view(), ui.grid
  if not (v and g) then return end
  local r = math.floor((vim.api.nvim_win_get_cursor(ui.win)[1] - 1) / g.th)
  local vcol = vim.api.nvim_win_call(ui.win, function() return vim.fn.virtcol(".") end) - 1
  local c = math.max(0, math.min(g.per - 1, math.floor((vcol - g.pad) / (g.aw + g.gap))))
  local k = math.max(1, math.min(r * g.per + c + 1, #visible(v)))
  if k ~= v.cursor then
    v.cursor = k
    select_tile(v, false)
  end
end

---------------------------------------------------------------------------
-- Now-playing card
---------------------------------------------------------------------------

-- A bar `w` cells wide filled to `frac`: accent up to a knob, muted after.
local function bar(frac, w, knob)
  local filled = math.floor(math.max(0, math.min(1, frac)) * w + 0.5)
  if knob then
    filled = math.min(filled, w - 1)
    return { { ("━"):rep(filled), "MusicAccent" }, { "●", "MusicAccent" }, { ("─"):rep(w - filled - 1), "MusicMuted" } }
  end
  return { { ("━"):rep(filled), "MusicAccent" }, { ("─"):rep(w - filled), "MusicMuted" } }
end

local function card_rows(tw)
  local s, rows = music.state, {}
  for i = 1, CARD_H do rows[i] = {} end
  if not s.running then
    rows[4] = { { "Music is not running", "MusicTitle" } }
    rows[6] = { { "<Space> launches it and plays", "MusicMuted" } }
    return rows
  end
  local t = s.track
  if not t then
    rows[4] = { { "Nothing playing", "MusicTitle" } }
    rows[6] = { { "<CR> on anything above plays it", "MusicMuted" } }
  else
    rows[2] = { { fit(t.name, tw), "MusicTitle" } }
    if t.artist ~= "" then rows[3] = { { fit(t.artist, tw) } } end
    if t.album ~= "" then rows[4] = { { fit(t.album, tw), "MusicMuted" } } end
    local pos, dur = music.position(), t.duration or 0
    local times = dur > 0 and (" %s / %s"):format(music.fmt_time(pos), music.fmt_time(dur)) or " " .. music.fmt_time(pos)
    local icon = s.playing and "󰐊 " or "󰏤 "
    local segs = { { icon, "MusicAccent" } }
    vim.list_extend(segs, bar(dur > 0 and pos / dur or 0, tw - width(icon .. times), true))
    segs[#segs + 1] = { times, "MusicMuted" }
    rows[6] = segs
  end
  local vol = s.volume or 0
  local segs = { { "󰕾 ", "MusicMuted" } }
  vim.list_extend(segs, bar(vol / 100, 12))
  segs[#segs + 1] = { (" %3d%%"):format(vol), "MusicMuted" }
  segs[#segs + 1] = { "    󰒟", s.shuffle and "MusicAccent" or "MusicMuted" }
  local rep_icon = s.rep == "one" and "󰑘" or s.rep == "all" and "󰑖" or "󰑗"
  segs[#segs + 1] = { "  " .. rep_icon, s.rep ~= "off" and "MusicAccent" or "MusicMuted" }
  rows[8] = segs
  return rows
end

local function render_card()
  if not valid_buf(ui.card_buf) or not valid_win(ui.card) then return end
  local x = ui.art_cols + 5
  draw(ui.card_buf, card_rows(vim.api.nvim_win_get_width(ui.card) - x - 2), (" "):rep(x))
end

-- A centred note, shown until (or instead of) the album art.
local function placeholder()
  local b = scratch()
  local lines = {}
  for i = 1, ART_ROWS do lines[i] = "" end
  local mid = math.ceil(ART_ROWS / 2)
  lines[mid] = (" "):rep(math.floor((ui.art_cols - 2) / 2)) .. "󰝚"
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.api.nvim_buf_set_extmark(b, ns, mid - 1, 0, { end_row = mid, hl_group = "MusicMuted" })
  vim.bo[b].modifiable = false
  return b
end

local function show_art_buf(b)
  if valid_win(ui.art) then vim.api.nvim_win_set_buf(ui.art, b) end
end

local function update_art()
  local t = music.state.running and music.state.track
  local id = t and t.id or nil
  if id == ui.art_id then return end
  ui.art_id = id
  show_art_buf(placeholder())
  if not (id and Snacks and Snacks.image and Snacks.image.supports_terminal()) then return end
  music.artwork(id, function(png)
    if not png or ui.art_id ~= id or not valid_win(ui.art) then return end
    pcall(function() require("pdfview.viewer").fix_snacks_spinner() end)
    local b = scratch()
    show_art_buf(b)
    Snacks.image.buf.attach(b, { src = png })
  end, true) -- ahead of any covers the grid is loading
end

---------------------------------------------------------------------------
-- Filter input
---------------------------------------------------------------------------

local function close_input()
  if valid_win(ui.input) then pcall(vim.api.nvim_win_close, ui.input, true) end
  ui.input = nil
  vim.cmd.stopinsert()
  if valid_win(ui.win) then vim.api.nvim_set_current_win(ui.win) end
end

-- Live filter: a one-line float over the list's last row.
local function filter()
  local v = view()
  if not v or valid_win(ui.input) then return end
  local b = scratch()
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { v.filter })
  ui.input = vim.api.nvim_open_win(b, true, {
    relative = "win",
    win = ui.win,
    row = vim.api.nvim_win_get_height(ui.win) - 1,
    col = 0,
    width = vim.api.nvim_win_get_width(ui.win),
    height = 1,
    style = "minimal",
    zindex = 52,
  })
  vim.wo[ui.input].winblend = 0
  vim.wo[ui.input].winhighlight = "Normal:MusicSel"
  vim.api.nvim_buf_set_extmark(b, ns, 0, 0, {
    virt_text = { { " / ", "MusicAccent" } },
    virt_text_pos = "inline",
    right_gravity = false,
  })
  vim.cmd.startinsert({ bang = true })
  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = b,
    callback = function()
      v.filter = vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] or ""
      v.cursor = 1
      render_list()
    end,
  })
  local function imap(lhs, fn) vim.keymap.set("i", lhs, fn, { buffer = b, nowait = true }) end
  local function move(d)
    return function()
      v.cursor = math.max(1, math.min(v.cursor + d, #visible(v)))
      render_list()
    end
  end
  imap("<CR>", function()
    close_input()
    open(selected())
  end)
  imap("<Esc>", close_input) -- keeps the filter; <Esc> in the list clears it
  imap("<C-n>", move(1))
  imap("<Down>", move(1))
  imap("<C-p>", move(-1))
  imap("<Up>", move(-1))
end

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------

local HELP = [[
Music player
  j/k gg G      move              <Tab>/<S-Tab>  next / previous tab
  l  <Right>    open (or play)    1..5           jump to a tab
  h  <BS>       back              /              filter (live; ⏎ opens, <Esc> keeps)
  <CR>          play: a playlist in order, an album/artist via the queue,
                a song in its context (album, playlist, library)
  P             play the selection (also in cover grids)
  a             add to the queue (Queue tab; starts it if nothing plays)
  o             reveal the playing song in its album
  <Space>       play / pause      n / p          next / previous track
  < / >         seek ∓10s         - / +          volume
  s / r         shuffle / repeat  R              reload the library
  q / <Esc>     close (<Esc> clears an active filter first)
In cover grids (albums, playlists): hjkl move between covers, <CR> opens,
  <BS> goes back, P plays the album / playlist]]

function M.close()
  if ui.tick then ui.tick:stop() end
  music.player_open = false
  if ui.augroup then pcall(vim.api.nvim_del_augroup_by_id, ui.augroup) end
  clear_covers()
  ui.grid, ui.gen, ui.footer = nil, (ui.gen or 0) + 1, nil
  -- by key, not ipairs over { ui.input, ... }: input is usually nil, and
  -- ipairs stops at the first nil, which closed nothing at all
  for _, key in ipairs({ "input", "art", "card", "win" }) do
    if valid_win(ui[key]) then pcall(vim.api.nvim_win_close, ui[key], true) end
  end
  ui.win, ui.card, ui.art, ui.input, ui.buf, ui.card_buf, ui.art_id, ui.augroup = nil, nil, nil, nil, nil, nil, nil, nil
end

local function ours(win)
  return win == ui.win or win == ui.card or win == ui.art or win == ui.input
end

local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = ui.buf, nowait = true }) end

local function keymaps()
  local cfg = music.config
  -- in a cover grid hjkl move between covers and <CR> opens; in a list
  -- j/k are native, l/h go in/out and <CR> plays
  local function grid_or(grid_fn, list_fn)
    return function() if ui.grid then grid_fn() else list_fn() end end
  end
  local function native(key)
    return function() vim.cmd.normal({ vim.v.count1 .. key, bang = true }) end
  end
  local function per() return ui.grid and ui.grid.per or 1 end
  map("l", grid_or(function() grid_move(1) end, function() open(selected()) end))
  map("<Right>", grid_or(function() grid_move(1) end, function() open(selected()) end))
  map("h", grid_or(function() grid_move(-1) end, back))
  map("<Left>", grid_or(function() grid_move(-1) end, back))
  map("j", grid_or(function() grid_move(per()) end, native("j")))
  map("<Down>", grid_or(function() grid_move(per()) end, native("j")))
  map("k", grid_or(function() grid_move(-per()) end, native("k")))
  map("<Up>", grid_or(function() grid_move(-per()) end, native("k")))
  map("<CR>", grid_or(function() open(selected()) end, function() play(selected()) end))
  map("P", function() play(selected()) end)
  map("<BS>", back)
  map("<Tab>", function() set_tab(nav.tab + 1) end)
  map("<S-Tab>", function() set_tab(nav.tab - 1) end)
  for i = 1, #TABS do map(tostring(i), function() set_tab(i, i == QUEUE_TAB) end) end
  map("/", filter)
  map("a", function() enqueue(selected()) end)
  map("o", reveal)
  map("<Space>", music.toggle)
  map("n", music.next)
  map("p", music.prev)
  map("<", function() music.seek(-cfg.seek_step) end)
  map(">", function() music.seek(cfg.seek_step) end)
  map("-", function() music.volume(-cfg.volume_step) end)
  map("+", function() music.volume(cfg.volume_step) end)
  map("=", function() music.volume(cfg.volume_step) end)
  map("s", music.shuffle)
  map("r", music.cycle_repeat)
  map("R", function()
    nav.stacks = {}
    lib.reload(function() set_tab(nav.tab) end)
  end)
  map("?", function() vim.notify(HELP) end)
  map("q", M.close)
  map("<Esc>", function()
    local v = view()
    if v and v.filter ~= "" then
      v.filter, v.cursor = "", 1
      render_list()
    else
      M.close()
    end
  end)
end

-- opts.tab: tab number to show; opts.filter: start typing a filter.
function M.open(opts)
  opts = opts or {}
  if valid_win(ui.win) then
    vim.api.nvim_set_current_win(ui.win)
  else
    ui.art_cols = art_cols(ART_ROWS)
    ui.footer = LIST_HINTS
    local w = math.min(math.max(76, width(LIST_HINTS) + 2), vim.o.columns - 4)
    local list_h = math.max(5, math.min(22, vim.o.lines - CARD_H - 8))
    -- a whole number of cover rows below the winbar, so no row is sliced
    local th = GRID_ART + 3
    if list_h > th then list_h = 1 + th * math.floor((list_h - 1) / th) end
    local top = math.max(0, math.floor((vim.o.lines - (list_h + CARD_H + 4)) / 2) - 1)
    local col = math.floor((vim.o.columns - w) / 2)

    ui.buf = scratch()
    vim.bo[ui.buf].filetype = "music"
    ui.win = vim.api.nvim_open_win(ui.buf, true, {
      relative = "editor", row = top, col = col, width = w, height = list_h,
      style = "minimal", border = "rounded",
      title = " 󰎈 Music ", title_pos = "center",
      footer = { { LIST_HINTS, "MusicMuted" } }, footer_pos = "center",
    })
    -- the cursorline is the selection marker (music is unmanaged_ft in cursorline.lua)
    vim.wo[ui.win].cursorline = true
    vim.wo[ui.win].cursorlineopt = "line"
    vim.wo[ui.win].winhighlight = "CursorLine:MusicSel"
    vim.wo[ui.win].winblend = 0
    -- covers use snacks' conceal overlay path; with conceal active it would
    -- also hide the captions between a cover's first and last row
    vim.wo[ui.win].conceallevel = 0

    ui.card_buf = scratch()
    ui.card = vim.api.nvim_open_win(ui.card_buf, false, {
      relative = "editor", row = top + list_h + 2, col = col, width = w, height = CARD_H,
      style = "minimal", border = "rounded", focusable = false,
    })
    vim.w[ui.card].no_cursorline = true
    vim.wo[ui.card].winblend = 0

    ui.art = vim.api.nvim_open_win(scratch(), false, {
      relative = "win", win = ui.card, row = 1, col = 2,
      width = ui.art_cols, height = ART_ROWS,
      style = "minimal", focusable = false, zindex = 51,
    })
    vim.w[ui.art].no_cursorline = true
    -- kitty finds an image by its placeholder cells' fg colour; the global
    -- winblend would blend that colour and the art would silently not draw
    vim.wo[ui.art].winblend = 0

    keymaps()
    ui.augroup = vim.api.nvim_create_augroup("music_ui", { clear = true })
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = ui.augroup,
      buffer = ui.buf,
      callback = function()
        local v = view()
        if not v or ui.rendering then return end
        if ui.grid then grid_follow_cursor() else v.cursor = vim.api.nvim_win_get_cursor(ui.win)[1] end
      end,
    })
    vim.api.nvim_create_autocmd("User", {
      group = ui.augroup,
      pattern = "MusicChanged",
      callback = function()
        render_card()
        update_art()
        -- moves the ▶ marker; grids have none, and redrawing them re-places every cover
        if not ui.grid then render_list() end
      end,
    })
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = ui.augroup,
      callback = function() render_card(); render_list() end,
    })
    -- close when focus goes anywhere but our own windows (the filter input is one)
    vim.api.nvim_create_autocmd("WinLeave", {
      group = ui.augroup,
      callback = function()
        vim.schedule(function()
          if ui.win and not ours(vim.api.nvim_get_current_win()) then M.close() end
        end)
      end,
    })
    vim.api.nvim_create_autocmd("VimResized", {
      group = ui.augroup,
      callback = function() M.close(); M.open() end,
    })

    music.player_open = true
    ui.tick = ui.tick or vim.uv.new_timer()
    ui.tick:start(1000, 1000, vim.schedule_wrap(render_card)) -- progress bar
    render_card()
    update_art()
    music.poll()
  end
  set_tab(opts.tab or nav.tab)
  if opts.filter then filter() end
end

function M.toggle()
  if valid_win(ui.win) then M.close() else M.open() end
end

return M
