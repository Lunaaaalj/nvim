-- hud_core: the dashboard's own content (clock, date, keys, GitHub stats)
-- redrawn by the HUD as an instrument panel, proposal B of the
-- `HUD Telemetry Core` mockup (https://claude.ai/artifact/7XD61iJ13TZLtZgPsPKZg9).
--
-- Snacks re-renders its text once a minute, so a clock with seconds and
-- centiseconds can only come from the art layer, which redraws at `fps`. In
-- HUD mode the snacks sections print a W x H block of no-break spaces (blank
-- on screen, but `content_box()` measures it, so the HUD's box is exactly
-- this panel) and keep every key bound as a hidden item; this module paints
-- the panel into that block (pieces.paints_box).
--
-- Levels are written as 1 + v: the renderer's content tier (header_art
-- cell()), which skips the art's `brightness` cap.
--
--   ┌─┤ LOCAL ├──────────────────┬─┤ REFERENCE ├───────┐
--   │ seven-segment HH:MM:SS.cc  │ UTC / EPOCH /       │
--   │                            │ SESSION / DOY WK Q  │
--   ├─┤ date ├───────────────────┴──────────┤ UTC-6 ├─┤
--   │ [f]FIND  [r]RECENT  ...                          │
--   ├──────────────────────────────────────────────────┤
--   │ seconds sweep                                    │
--   └─┤ GH  PR 03  ISS 05  CTB 1204  STK 12d ├─────────┘

local G = require("header_art.glyph")
local D = require("header_art.hud_data")

-- Interpreted, like hud_extra.lua: a few hundred text cells a frame, and
-- the closure-heavy helpers are the shape LuaJIT's traces kept aborting on.
jit.off(true, true)

local floor, min = math.floor, math.min
local chars = G.chars

local M = {}

M.W, M.H = 80, 12

local DEFAULT_KEYS = {
  { "f", "find" }, { "r", "recent" }, { "d", "cd" }, { "R", "repo" }, { "s", "session" }, { "c", "config" }, { "q", "quit" },
}

-- seven-segment digits: a (top) / f b (upper sides) / g / e c (lower sides) / d
local SEG = {
  ["0"] = "abcdef", ["1"] = "bc", ["2"] = "abged", ["3"] = "abgcd", ["4"] = "fgbc",
  ["5"] = "afgcd", ["6"] = "afgedc", ["7"] = "abc", ["8"] = "abcdefg", ["9"] = "abfgcd",
}
local SEG_W, SEG_OFF = 5, 0.09

-- Local UTC offset label (DST-aware), recomputed once a minute.
local tz_at, tz_label = -1, "UTC"
local function tz(s)
  if floor(s / 60) ~= tz_at then
    tz_at = floor(s / 60)
    local u = os.date("!*t", s) --[[@as osdateparam]]
    u.isdst = os.date("*t", s).isdst
    local off = os.difftime(s, os.time(u)) / 3600
    tz_label = string.format("UTC%+g", off)
  end
  return tz_label
end

local function thousands(n)
  local s = tostring(floor(n or 0))
  while true do
    local r, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
    s = r
    if k == 0 then return s end
  end
end

-- Draw the panel with its top-left cell at (x, y). `set(x, y, v, ch)` is the
-- HUD canvas' painter; `a` the boot age (text types in); `opts` is
-- `header_art_opts.hud.content` ({ keys = { {key, hint}, ... }, stats = fn }).
function M.draw(set, x, y, a, opts)
  opts = opts or {}
  local function cset(cx, cy, v, ch) set(cx, cy, 1 + v, ch) end
  local function text(cx, cy, s, v, opaque)
    local cs = chars(s)
    local n = min(#cs, floor((a or 99) * 140))
    for i = 1, n do
      if cs[i] ~= " " then
        cset(cx + i - 1, cy, v, cs[i])
      elseif opaque then
        set(cx + i - 1, cy, 0)
      end
    end
  end

  local s, us = D.now()
  local lt, ut = os.date("*t", s), os.date("!*t", s)
  local cs = floor(us / 1e4)
  local frac = string.format(".%02d", cs)
  local W, H = M.W, M.H
  local x1, y1, split = x + W - 1, y + H - 1, x + 50

  -- frame
  local frame_v = 0.35 * min(1, (a or 99) * 4)
  for i = x + 1, x1 - 1 do
    cset(i, y, frame_v, "─"); cset(i, y + 7, 0.3, "─"); cset(i, y + 9, 0.3, "─"); cset(i, y1, frame_v, "─")
  end
  for j = y + 1, y1 - 1 do
    cset(x, j, frame_v, "│"); cset(x1, j, frame_v, "│")
  end
  for j = y + 1, y + 6 do cset(split, j, 0.25, "│") end
  cset(x, y, 0.45, "┌"); cset(x1, y, 0.45, "┐"); cset(x, y1, 0.45, "└"); cset(x1, y1, 0.45, "┘")
  cset(split, y, 0.35, "┬"); cset(split, y + 7, 0.35, "┴")
  for _, j in ipairs({ 7, 9 }) do
    cset(x, y + j, 0.35, "├"); cset(x1, y + j, 0.35, "┤")
  end
  text(x + 2, y, "┤ LOCAL ├", 0.5, true)
  text(split + 2, y, "┤ REFERENCE ├", 0.5, true)

  -- big local time: seven-segment HH:MM:SS, fraction beside the last digit
  local cx, blink = x + 3, us < 5e5
  for ch in (string.format("%02d:%02d:%02d", lt.hour, lt.min, lt.sec)):gmatch(".") do
    if ch == ":" then
      cset(cx + 1, y + 2, blink and 0.95 or 0.12, "■"); cset(cx + 1, y + 4, blink and 0.95 or 0.12, "■")
      cx = cx + 3
    else
      local lit = SEG[ch]
      local function on(seg) return lit:find(seg, 1, true) and 0.95 or SEG_OFF end
      for i = 1, SEG_W - 2 do
        cset(cx + i, y + 1, on("a"), "━"); cset(cx + i, y + 3, on("g"), "━"); cset(cx + i, y + 5, on("d"), "━")
      end
      cset(cx, y + 2, on("f"), "┃"); cset(cx + SEG_W - 1, y + 2, on("b"), "┃")
      cset(cx, y + 4, on("e"), "┃"); cset(cx + SEG_W - 1, y + 4, on("c"), "┃")
      cx = cx + SEG_W + 1
    end
  end
  text(cx, y + 5, frac, 0.8)

  -- reference column
  local up = D.uptime()
  local rows = {
    { "UTC", string.format("%02d:%02d:%02d%s", ut.hour, ut.min, ut.sec, frac) },
    { "EPOCH", tostring(s) .. frac },
    { "SESSION", string.format("T+%02d:%02d:%02d.%d", floor(up / 3600), floor(up / 60) % 60, floor(up) % 60, floor(up * 10) % 10) },
    { "DOY", string.format("%03d   WK %s   Q%d", lt.yday, tostring(os.date("%V", s)), floor((lt.month - 1) / 3) + 1) },
  }
  for i, r in ipairs(rows) do
    text(split + 2, y + 1 + i, r[1], 0.3)
    text(split + 11, y + 1 + i, r[2], 0.7)
  end

  -- date divider
  text(x + 2, y + 7, "┤ " .. tostring(os.date("%Y-%m-%d  %A", s)):upper() .. " ├", 0.55, true)
  local tzs = "┤ " .. tz(s) .. " ├"
  text(x1 - #chars(tzs) - 1, y + 7, tzs, 0.35, true)

  -- keys as keycaps, centred
  local keys = opts.keys or DEFAULT_KEYS
  local width = -2
  for _, k in ipairs(keys) do width = width + 3 + #k[2] + 2 end
  local kx = x + floor((W - width) / 2)
  for _, k in ipairs(keys) do
    local label = k[2]:upper()
    text(kx, y + 8, "[", 0.3); text(kx + 1, y + 8, k[1], 0.95); text(kx + 2, y + 8, "]", 0.3); text(kx + 3, y + 8, label, 0.5)
    kx = kx + 3 + #label + 2
  end

  -- seconds sweep: fills over the minute, a major tick every 5 seconds
  local sx, sw = x + 2, W - 4
  local lit = (lt.sec + us / 1e6) / 60 * sw
  for i = 0, sw - 1 do
    local major = i % floor(sw / 12 + 0.5) == 0
    if i < lit then
      cset(sx + i, y + 10, major and 0.75 or 0.55, "━")
    else
      cset(sx + i, y + 10, major and 0.3 or 0.14, major and "┴" or "─")
    end
  end
  cset(sx + min(sw - 1, floor(lit)), y + 10, 0.98, "╋")

  -- GitHub stats in the bottom edge
  local st = opts.stats and opts.stats()
  local gh = st and string.format("┤ GH  PR %02d  ISS %02d  CTB %s  STK %dd ├", st.prs or 0, st.issues or 0,
    thousands(st.contributions), st.streak or 0) or "┤ GH  OFFLINE ├"
  text(x + 2, y1, gh, 0.45, true)
end

-- A one-line fallback for boxes too small for the panel (the picker preview).
function M.draw_compact(set, cx, cy)
  local s, us = D.now()
  local str = os.date("LOCAL %H:%M:%S", s) .. string.format(".%02d", floor(us / 1e4))
  local x0 = cx - floor(#str / 2)
  for i = 1, #str do
    local ch = str:sub(i, i)
    if ch ~= " " then set(x0 + i - 1, cy, i <= 5 and 1.3 or 1.95, ch) end
  end
end

return M
