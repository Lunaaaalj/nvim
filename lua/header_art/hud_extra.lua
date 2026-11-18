-- hud_extra: modules that fill the free zones a large window leaves around
-- the HUD, from the `HUD Expansion Deck` mockup
-- (https://claude.ai/artifact/3NExSM42EYBygV24HfzwqW). Most HUD modules sit at
-- fixed offsets from the window edges, so at fullscreen the top and bottom
-- bands open up; each zone below is a rect computed from the same `P` / `L`
-- as hud.lua, and a module is drawn only when the rect meets its minimum
-- size (so a half-width window looks exactly as before).
--
-- Zones (`header_art_opts.hud.zones`, module name or false):
--   z1  top band, between the readouts and the heading tape
--   z2  top band, between the heading tape and the clock
--   z3  bottom band, between the process map and the waveform
--   z4  bottom band, between the waveform and the spectrum
--   z5  under the waveform
--   z6  the event log's spare width (the log is capped at 44 columns then)
--
-- Modules: icosa, globe, strip, orrery, hexdump, helix. Each is
-- `draw(A, r, t, g, a, data)`: `A` draws clipped to the zone rect `r`, `g` is
-- the boot growth (0..1), `a` the boot age (for typed-in text).

local G = require("header_art.glyph")

-- Interpreted on purpose: these modules are many short, branchy loops through
-- closures, and LuaJIT kept aborting their traces (and once miscompiled the
-- helix loop), so a 240x64 HUD frame took 1-25 ms; with this file
-- interpreted the whole frame is 2.5-4 ms.
jit.off(true, true)

local floor, min, max, abs, sqrt = math.floor, math.min, math.max, math.abs, math.sqrt
local sin, cos, atan2, asin, pi = math.sin, math.cos, math.atan2, math.asin, math.pi
local TAU = 2 * pi
local hash, slope_char, clamp, chars = G.hash, G.slope_char, G.clamp, G.chars

local function round(x) return floor(x + 0.5) end

local M = {}

M.ZONE_IDS = { "z1", "z2", "z3", "z4", "z5", "z6" }

-- Zone rects (inclusive) for a w x h window. `tape_half` and `nb` (spectrum
-- bars) and `wave_y` are hud.lua's own values, so the zones hug its modules.
function M.zones(w, h, P, L, tape_half, nb, wave_y)
  local Z = {
    z1 = { x0 = 40, x1 = floor(L.cx - tape_half - 3), y0 = 3, y1 = L.topY1 - 1 },
    z2 = { x0 = math.ceil(L.cx + tape_half + 3), x1 = w - 31, y0 = 3, y1 = L.topY1 - 1 },
    z3 = { x0 = 33, x1 = L.leftX1, y0 = L.botY0 + 1, y1 = h - 3 },
    z4 = { x0 = L.rightX0, x1 = w - 5 - nb - 3, y0 = L.botY0 + 1, y1 = h - 3 },
    z5 = { x0 = P.c0 + 2, x1 = P.c1 - 2, y0 = wave_y + 4, y1 = h - 3 },
    z6 = { x0 = L.rightX0 + 47, x1 = w - 12, y0 = L.topY1 + 2, y1 = L.botY0 - 2 },
  }
  for _, z in pairs(Z) do
    z.w, z.h = z.x1 - z.x0 + 1, z.y1 - z.y0 + 1
  end
  return Z
end

-- Drawing helpers clipped to `r` (same contract as hud.lua's: `put` keeps the
-- brighter level, `set` paints over, `text` types in with age `a`).
function M.api(C, r)
  -- Kept flat (bounds in upvalues, rounding inline, one call into the
  -- canvas): this runs for every cell a module draws.
  local A = {}
  local cput, cset = C.put, C.set
  local cx0, cx1, cy0, cy1 = r.x0, r.x1, r.y0, r.y1
  function A.put(x, y, v, ch)
    x, y = floor(x + 0.5), floor(y + 0.5)
    if x >= cx0 and x <= cx1 and y >= cy0 and y <= cy1 then cput(x, y, v, ch) end
  end
  function A.set(x, y, v, ch)
    x, y = floor(x + 0.5), floor(y + 0.5)
    if x >= cx0 and x <= cx1 and y >= cy0 and y <= cy1 then cset(x, y, v, ch) end
  end
  function A.text(x, y, s, v, a)
    local cs = chars(s)
    local n = min(#cs, floor((a or 99) * 140))
    for i = 1, n do
      if cs[i] ~= " " then A.set(x + i - 1, y, v, cs[i]) end
    end
    if n < #cs and (a or 99) > 0 then A.set(x + n, y, 0.9, "█") end
  end
  function A.line(x0, y0, x1, y1, v)
    local ch = slope_char(x1 - x0, y1 - y0)
    local n = math.ceil(max(abs(x1 - x0), abs(y1 - y0) * 2)) + 1
    for q = 0, n do A.put(x0 + (x1 - x0) * q / n, y0 + (y1 - y0) * q / n, v, ch) end
  end
  -- An ellipse R columns wide and R * ry rows tall.
  function A.ring(cx, cy, R, v, ry)
    ry = ry or 0.5
    local n = math.ceil(TAU * R * 1.5)
    for i = 0, n - 1 do
      local an = i / n * TAU
      A.put(cx + R * cos(an), cy + R * sin(an) * ry, v, slope_char(-sin(an), cos(an) * ry))
    end
  end
  return A
end

-- "── LABEL ─────" across the top row of the zone.
local function header(A, r, label, a)
  A.text(r.x0, r.y0, "── " .. label .. " " .. ("─"):rep(max(0, r.w - #chars(label) - 4)), 0.3, a)
end

-- Rotate a point around X, then Y, then Z.
local function rot(x, y, z, ax, ay, az)
  local c, s = cos(ax), sin(ax)
  y, z = y * c - z * s, y * s + z * c
  c, s = cos(ay), sin(ay)
  x, z = x * c + z * s, -x * s + z * c
  c, s = cos(az), sin(az)
  x, y = x * c - y * s, x * s + y * c
  return x, y, z
end

-- Perspective projection; a row is two columns tall.
local function project(x, y, z, S, cx, cy, f)
  local k = (f or 4.2) / ((f or 4.2) - z)
  return cx + x * S * k, cy - y * S * k * 0.5, z
end

---------------------------------------------------------------------------
-- icosa: a 20-face wireframe solid, hidden edges dimmed via face normals
---------------------------------------------------------------------------

local ICO_V, ICO_E, ICO_F = {}, {}, {}
do
  local p = (1 + sqrt(5)) / 2
  local n = sqrt(1 + p * p)
  for _, v in ipairs({ { 0, 1, p }, { 0, -1, p }, { 0, 1, -p }, { 0, -1, -p }, { 1, p, 0 }, { -1, p, 0 },
    { 1, -p, 0 }, { -1, -p, 0 }, { p, 0, 1 }, { -p, 0, 1 }, { p, 0, -1 }, { -p, 0, -1 } }) do
    ICO_V[#ICO_V + 1] = { v[1] / n, v[2] / n, v[3] / n }
  end
  local e0 = 2 / n
  local function adj(i, j)
    local a, b = ICO_V[i], ICO_V[j]
    return abs(sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2) - e0) < 1e-3
  end
  for i = 1, 12 do
    for j = i + 1, 12 do
      if adj(i, j) then
        ICO_E[#ICO_E + 1] = { i, j }
        for k = j + 1, 12 do
          if adj(i, k) and adj(j, k) then ICO_F[#ICO_F + 1] = { i, j, k } end
        end
      end
    end
  end
  -- the (up to two) faces each edge borders
  for _, e in ipairs(ICO_E) do
    e.faces = {}
    for fi, f in ipairs(ICO_F) do
      local has_i, has_j = false, false
      for _, v in ipairs(f) do
        has_i = has_i or v == e[1]
        has_j = has_j or v == e[2]
      end
      if has_i and has_j then e.faces[#e.faces + 1] = fi end
    end
  end
end

local function icosa(A, r, t, g, a)
  header(A, r, "OBJ ICOSA-20", a)
  local S = min((r.w - 6) / 2, r.h - 5) * g
  if S < 3 then return end
  local cx, cy = r.x0 + r.w / 2, r.y0 + 1 + (r.h - 3) / 2
  local ax, ay, az = t * 0.55, t * 0.8, 0.3 * sin(t * 0.3)
  local V, Pp = {}, {}
  for i, v in ipairs(ICO_V) do
    local x, y, z = rot(v[1], v[2], v[3], ax, ay, az)
    V[i] = { x, y, z }
    Pp[i] = { project(x, y, z, S, cx, cy) }
  end
  local front = {}
  for fi, f in ipairs(ICO_F) do front[fi] = V[f[1]][3] + V[f[2]][3] + V[f[3]][3] > 0 end
  for _, e in ipairs(ICO_E) do
    local vis = false
    for _, fi in ipairs(e.faces) do vis = vis or front[fi] end
    local p, q = Pp[e[1]], Pp[e[2]]
    A.line(p[1], p[2], q[1], q[2], vis and 0.72 or 0.15)
  end
  local bx0, bx1, by0, by1 = math.huge, -math.huge, math.huge, -math.huge
  for _, p in ipairs(Pp) do
    bx0, bx1, by0, by1 = min(bx0, p[1]), max(bx1, p[1]), min(by0, p[2]), max(by1, p[2])
    if p[3] > 0.15 then A.set(p[1], p[2], 0.95, "●") end
  end
  A.put(bx0 - 2, by0 - 1, 0.45, "┌"); A.put(bx1 + 2, by0 - 1, 0.45, "┐")
  A.put(bx0 - 2, by1 + 1, 0.45, "└"); A.put(bx1 + 2, by1 + 1, 0.45, "┘")
  A.text(r.x0, r.y1, string.format("ROT X%03d Y%03d  V12 E30 F20", floor(ax * 57.3) % 360, floor(ay * 57.3) % 360), 0.35, a - 0.2)
end

---------------------------------------------------------------------------
-- globe: landmasses, a live day/night terminator, city lights, a satellite
---------------------------------------------------------------------------

local function vnoise(x, y, z)
  local xi, yi, zi = floor(x), floor(y), floor(z)
  local xf, yf, zf = x - xi, y - yi, z - zi
  local u, v, w = xf * xf * (3 - 2 * xf), yf * yf * (3 - 2 * yf), zf * zf * (3 - 2 * zf)
  local function h(i, j, k) return hash(xi + i, yi + j, zi + k + 977) end
  local function l(p, q, s) return p + (q - p) * s end
  return l(l(l(h(0, 0, 0), h(1, 0, 0), u), l(h(0, 1, 0), h(1, 1, 0), u), v),
    l(l(h(0, 0, 1), h(1, 0, 1), u), l(h(0, 1, 1), h(1, 1, 1), u), v), w)
end

-- Land map (LAND_W x LAND_H, longitude x latitude), built on first use from
-- noise sampled on the unit sphere, so it has no seam.
local LAND_W, LAND_H, LAND = 96, 48, nil
local function land_map()
  if LAND then return LAND end
  LAND = {}
  for j = 0, LAND_H - 1 do
    local phi = (j + 0.5) / LAND_H * pi - pi / 2
    for i = 0, LAND_W - 1 do
      local lam = (i + 0.5) / LAND_W * TAU - pi
      local x, y, z = cos(phi) * cos(lam) * 1.9 + 3, sin(phi) * 1.9, cos(phi) * sin(lam) * 1.9
      local n = vnoise(x, y, z) * 0.55 + vnoise(x * 2.1, y * 2.1, z * 2.1) * 0.3 + vnoise(x * 4.3, y * 4.3, z * 4.3) * 0.15
      LAND[j * LAND_W + i + 1] = n > 0.53
    end
  end
  return LAND
end

-- Local UTC offset in hours (DST-aware).
local function utc_offset()
  local now = os.time()
  local u = os.date("!*t", now) --[[@as osdateparam]]
  u.isdst = os.date("*t", now).isdst
  return os.difftime(now, os.time(u)) / 3600
end

local function globe(A, r, t, g, a)
  header(A, r, "GEO // TERMINATOR LIVE", a)
  local R = min((r.w - 4) / 2, r.h - 4) * g
  if R < 3 then return end
  local land = land_map()
  local cx, cy = r.x0 + r.w / 2, r.y0 + 1.5 + (r.h - 3) / 2
  local spin, tilt = t * 0.22, 0.38
  local ct, st = cos(tilt), sin(tilt)
  -- the sun from the real UTC time and day of the year
  local u = os.date("!*t")
  local dec = -23.44 * cos(TAU / 365 * (u.yday + 10)) * pi / 180
  local sl = -((u.hour + u.min / 60) - 12) * 15 * pi / 180
  local sx, sy, sz = cos(dec) * cos(sl), sin(dec), cos(dec) * sin(sl)
  for y = floor(cy - R / 2) - 1, math.ceil(cy + R / 2) + 1 do
    for x = floor(cx - R) - 1, math.ceil(cx + R) + 1 do
      local X, Y = (x - cx) / R, -(y - cy) * 2 / R
      local d = X * X + Y * Y
      if d <= 1 then
        local Z = sqrt(1 - d)
        -- view -> earth-fixed: undo the tilt, then the spin
        local py, pz = Y * ct + Z * st, -Y * st + Z * ct
        local lam = atan2(pz, X) - spin
        local phi = asin(max(-1, min(1, py)))
        local ex, ey, ez = cos(phi) * cos(lam), sin(phi), cos(phi) * sin(lam)
        local light = ex * sx + ey * sy + ez * sz
        local li = floor(((lam + pi) / TAU % 1) * LAND_W)
        local lj = max(0, min(LAND_H - 1, floor((phi + pi / 2) / pi * LAND_H)))
        local rim = 0.55 + 0.45 * Z
        if land[lj * LAND_W + li + 1] then
          if light > 0.08 then
            A.put(x, y, (0.45 + 0.45 * light) * rim, light > 0.4 and "▓" or "▒")
          elseif light > -0.08 then
            A.put(x, y, 0.32 * rim, "░")
          elseif hash(x, y, 7) < 0.13 then
            A.put(x, y, 0.75, ".") -- city lights
          else
            A.put(x, y, 0.14, "░")
          end
        else
          local latd, lond = phi * 180 / pi, (lam * 180 / pi) % 360
          if abs(latd % 30) < 1.6 or lond % 30 < 2.2 then A.put(x, y, (light > 0 and 0.24 or 0.1) * rim, "·") end
        end
      end
    end
  end
  A.ring(cx, cy, R + 1.2, 0.22)
  -- a satellite on an inertial orbit (it doesn't spin with the earth)
  local inc, Ro = 51.6 * pi / 180, 1.28
  local function orb(an)
    return rot(cos(an), sin(an) * sin(inc), sin(an) * cos(inc), tilt, 0.6, 0)
  end
  local function hidden(x, y, z) return z < 0 and (x * x + y * y) * Ro * Ro < 1 end
  for i = 0, 159 do
    local x, y, z = orb(i / 160 * TAU)
    if not hidden(x, y, z) then A.put(cx + x * Ro * R, cy - y * Ro * R / 2, z < 0 and 0.14 or 0.3, "·") end
  end
  local ox, oy, oz = orb(t * 1.1)
  if not hidden(ox, oy, oz) then
    local px, py = cx + ox * Ro * R, cy - oy * Ro * R / 2
    A.set(px, py, 0.95, "◆")
    A.text(round(px) + 2, round(py), "SAT-1 408km", 0.5, a - 0.3)
  end
  -- your timezone's longitude
  local tz = utc_offset()
  local tl, tp = tz * 15 * pi / 180, 22 * pi / 180
  local mx, my, mz = cos(tp) * cos(tl + spin), sin(tp), cos(tp) * sin(tl + spin)
  local vy, vz = my * ct - mz * st, my * st + mz * ct
  if vz > 0.05 then
    local px, py = cx + mx * R, cy - vy * R / 2
    A.set(px, py, 0.95, "◉")
    A.text(round(px) - 3, round(py), "TZ", 0.5, a - 0.3)
  end
  local decd, sld = dec * 180 / pi, ((sl * 180 / pi) + 540) % 360 - 180
  A.text(r.x0, r.y1, string.format("SUBSOLAR %4.1f%s %5.1f%s   UTC%+g", abs(decd), decd >= 0 and "N" or "S",
    abs(sld), sld >= 0 and "E" or "W", tz), 0.35, a - 0.2)
end

---------------------------------------------------------------------------
-- strip: memory and load history (one sample per second, hud_data.history)
---------------------------------------------------------------------------

local function strip(A, r, _, g, a, data)
  header(A, r, "TELEMETRY 120 s  RSS / LOAD", a)
  local x0, x1, y0, y1 = r.x0 + 1, r.x1 - 12, r.y0 + 2, r.y1 - 1
  if x1 - x0 < 10 or y1 - y0 < 3 then return end
  for y = y0, y1, 2 do
    for x = x0, x1, 3 do A.put(x, y, 0.1, "·") end
  end
  local hist = data.history or {}
  local span = floor((x1 - x0) * g)
  local n = min(#hist, span + 1)
  if n == 0 then return end
  local series = {
    { key = "mem", lab = "RSS", fmt = function(v) return string.format("%.0fM", v) end, v = 0.75, floor = 8 },
    { key = "load", lab = "LD", fmt = function(v) return string.format("%.2f", v) end, v = 0.45, floor = 0.5 },
  }
  local used
  for _, s in ipairs(series) do
    -- each series scaled to its own visible range (at least `floor` tall)
    local lo, hi = math.huge, -math.huge
    for i = #hist - n + 1, #hist do
      local v = hist[i][s.key]
      lo, hi = min(lo, v), max(hi, v)
    end
    local mid, half = (lo + hi) / 2, max(hi - lo, s.floor) / 2 * 1.15
    local function yof(v) return y1 - clamp((v - (mid - half)) / (2 * half)) * (y1 - y0) end
    local px, py
    for i = #hist - n + 1, #hist do
      local x, y = x1 - (#hist - i), yof(hist[i][s.key])
      if px then A.line(px, py, x, y, s.v) end
      px, py = x, y
    end
    A.set(px, py, 0.98, "●")
    -- the two end labels never share a row
    local ly = round(py)
    if ly == used then ly = ly + (ly + 1 <= y1 and 1 or -1) end
    used = ly
    A.text(px + 2, ly, s.lab .. " " .. s.fmt(hist[#hist][s.key]), s.v, a - 0.2)
  end
end

---------------------------------------------------------------------------
-- orrery: language servers orbiting, one moon per attached buffer
---------------------------------------------------------------------------

local function orrery(A, r, t, g, a, data, live)
  local cl = data.clients or {}
  local nbuf = 0
  for _, c in ipairs(cl) do nbuf = nbuf + c.bufs end
  header(A, r, string.format("%sLSP ORRERY  %d CLIENT%s  %d BUF", (live and live.avail) and "[6] " or "", #cl, #cl == 1 and "" or "S", nbuf), a)
  local Rm = min((r.w - 16) / 2, (r.h - 4) / 0.7) * g
  if Rm < 5 then return end
  local cx, cy, ry = r.x0 + (r.w - 10) / 2, r.y0 + 1.5 + (r.h - 3) / 2, 0.34
  A.set(cx, cy, 0.95, "◎")
  if #cl == 0 then
    A.ring(cx, cy, Rm * 0.7, 0.12, ry)
    A.text(round(cx) - 5, round(cy + Rm * 0.7 * ry) + 1, "NO CLIENTS", 0.35, a - 0.2)
  end
  for k, c in ipairs(cl) do
    if k > 5 then break end
    local f = #cl == 1 and 0.7 or 0.42 + 0.58 * (k - 1) / (min(#cl, 5) - 1)
    local R = Rm * f
    A.ring(cx, cy, R, 0.14, ry)
    local an = t * 0.3 * (Rm / R) ^ 1.5 + k * 2.1
    local px, py = cx + R * cos(an), cy + R * sin(an) * ry
    local v = sin(an) < 0 and 0.55 or 0.9 -- behind the centre: dimmer
    for m = 0, c.bufs - 1 do
      local ma = t * 3 + m * TAU / c.bufs
      A.put(px + 2.4 * cos(ma), py + 0.6 * sin(ma), v * 0.6, "·")
    end
    A.set(px, py, v, "●")
    A.text(round(px) + 2, round(py), c.name, v * 0.7, a - 0.2 - k * 0.04)
  end
  A.text(r.x0, r.y1, "PERIOD ∝ R^1.5   MOONS = BUFFERS", 0.3, a - 0.2)
end

---------------------------------------------------------------------------
-- hexdump: the last edited buffer as hex + ASCII, scrolling
---------------------------------------------------------------------------

local function hexdump(A, r, t, g, a, data, live)
  local src = data.hex or { name = "?", bytes = "" }
  local bytes = src.bytes
  if #bytes == 0 then bytes = "(empty)" end
  local bpr, rows = r.w >= 78 and 16 or 8, r.h - 1
  -- peeked (hud_live): the real buffer sits in a float over the rows
  if live and live.peek then return header(A, r, "[3] PEEK " .. live.peek .. "  ·  q close · O pop out", a) end
  header(A, r, string.format("%sMEM 0x7F3A0000  %s  %.1f KB", (live and live.avail) and "[3] " or "", src.name, #bytes / 1024), a)
  local step = floor(t * 2.2)
  for k = 0, rows - 1 do
    if k / rows > g then break end
    local row, y = step + k, r.y0 + 1 + k
    local last = k == rows - 1
    local base = (row * bpr) % #bytes
    A.text(r.x0, y, string.format("%08x", (0x7f3a0000 + row * bpr) % 0x100000000), 0.18)
    local asc = {}
    for b = 0, bpr - 1 do
      local by = bytes:byte((base + b) % #bytes + 1)
      local cur = last and b == floor((t * 9) % bpr)
      local flare = hash(row, b, floor(t * 3)) < 0.025
      A.text(r.x0 + 10 + b * 3 + (b >= 8 and 1 or 0), y, string.format("%02x", by),
        cur and 0.98 or (flare and 0.75 or (last and 0.5 or 0.22 + 0.12 * k / rows)))
      asc[#asc + 1] = (by >= 32 and by < 127) and string.char(by) or "."
    end
    A.text(r.x0 + 11 + bpr * 3 + 1, y, "│" .. table.concat(asc) .. "│", last and 0.45 or 0.16)
  end
end

---------------------------------------------------------------------------
-- helix: a double helix whose base pairs spell the HEAD commit hash
---------------------------------------------------------------------------

local PAIR = { A = "T", T = "A", C = "G", G = "C" }
local BASES = { "A", "C", "G", "T" }

-- The hash as bases, two bits per base (cached: HEAD rarely changes).
local seq_for, seq, seq_gc = nil, {}, 0
local function sequence(head)
  if head == seq_for then return seq, seq_gc end
  seq, seq_gc, seq_for = {}, 0, head
  for i = 1, #head do
    local d = tonumber(head:sub(i, i), 16) or 0
    for _, q in ipairs({ d % 4, floor(d / 4) % 4 }) do
      local b = BASES[q + 1]
      seq[#seq + 1] = b
      if b == "G" or b == "C" then seq_gc = seq_gc + 1 end
    end
  end
  return seq, seq_gc
end

local function helix(A, r, t, g, a, data)
  local head = data.head or vim.fn.sha256(data.cwd or "")
  A.text(r.x0, r.y0, "SEQ " .. (data.head and head:sub(1, 7) or "no git"), 0.35, a)
  local bases, gc = sequence(head)
  local nb = #bases
  local cx, amp, sc = r.x0 + r.w / 2, min((r.w - 3) / 2, 6) * g, floor(t * 1.4)
  local scan = r.y0 + 2 + floor((t * 3) % max(1, r.h - 4))
  for y = r.y0 + 2, r.y1 - 2 do
    local ph = y * 0.45 + t * 1.6
    local s, c = sin(ph), cos(ph)
    local xa, xb = cx + amp * s, cx - amp * s
    if y % 2 == 0 then
      local lo, hi = round(min(xa, xb)), round(max(xa, xb))
      for x = lo + 1, hi - 1 do A.put(x, y, 0.16, "─") end
      if hi - lo > 3 then
        local b1 = bases[(y + sc) % nb + 1]
        local b2, hot = PAIR[b1], y == scan or y == scan + 1
        A.put(lo + 1, y, hot and 0.95 or 0.4, s > 0 and b2 or b1)
        A.put(hi - 1, y, hot and 0.95 or 0.4, s > 0 and b1 or b2)
      end
    end
    A.put(xa, y, c > 0 and 0.85 or 0.25, slope_char(amp * c * 0.45, 1))
    A.put(xb, y, c > 0 and 0.25 or 0.85, slope_char(-amp * c * 0.45, 1))
  end
  A.set(r.x0, scan, 0.9, "▶")
  A.text(r.x0, r.y1, string.format("GC %d%%", round(gc / nb * 100)), 0.35, a - 0.2)
end

-- min = { columns, rows } the zone must have
M.MODULES = {
  icosa = { min = { 20, 10 }, draw = icosa },
  globe = { min = { 26, 11 }, draw = globe },
  strip = { min = { 32, 8 }, draw = strip },
  orrery = { min = { 30, 11 }, draw = orrery },
  hexdump = { min = { 45, 5 }, draw = hexdump },
  helix = { min = { 10, 12 }, draw = helix },
}

return M
