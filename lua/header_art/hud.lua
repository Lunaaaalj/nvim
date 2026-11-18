-- hud: a heads-up display built around the dashboard's content, from the
-- `HUD Module Deck` mockup (https://claude.ai/artifact/GkKQbvccwN5H3B77HBrK7y,
-- 160 x 44 grid, speed 0.4 = the dashboard default, so no time scaling).
--
-- Modules (each can be turned off in `header_art_opts.hud.modules`):
--   frame     rulers on all four edges, row letters, corner marks
--   brackets  heavy corners outside the content box; title = cwd // branch
--   tape      heading tape above the content
--   panel     left panel: a simulated terminal (default), or rings / globe / radar
--   ladder    altitude ladder on the right edge
--   spectrum  bar spectrum with falling peak markers, bottom right
--   wave      waveform under the content
--   matrix    process map: the listed buffers first (bright = modified)
--   sys       readouts: version, lazy plugins + startup, RSS, load, uptime, buffers / LSP / diagnostics
--   clock     local time to the centisecond, uplink, signal
--   log       event log: real editor events (hud_data.lua) between ambient lines
--   barcode, coords   decoration
--   reticle   a target lock that glides between points outside the content
--   scan      a bright band rolling down over everything
--   alert     a banner every 20 s; it reports diagnostic errors when there are any
--   glitch    rows torn sideways for one beat
--   boot      modules type / grow in when the piece is built (startup, resize)
--
-- Zones (`header_art_opts.hud.zones`): the free space a large window leaves
-- around these modules, filled by hud_extra.lua (icosa, globe, strip, orrery,
-- hexdump, helix); a zone too small for its module is skipped.
--
-- Layout: every module is placed relative to the padded content box `P`, in
-- four zones kept 9 columns / 5 rows clear of it (so nothing sits in its
-- fade); a module that doesn't fit is skipped. The builder gets `P` as its
-- third argument (pieces.uses_box); the picker preview passes nil and a
-- centred stand-in is used.

local G = require("header_art.glyph")
local D = require("header_art.hud_data")
local X = require("header_art.hud_extra")
local K = require("header_art.hud_core")

local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local sin, cos, exp, pi = math.sin, math.cos, math.exp, math.pi
local TAU = 2 * pi
local hash, slope_char, clamp, smooth, chars = G.hash, G.slope_char, G.clamp, G.smooth, G.chars

local function pad(n, k) return string.format("%0" .. k .. "d", floor(n)) end
local function round(x) return floor(x + 0.5) end

local M = {}

M.config = {
  panel = "terminal", -- terminal | rings | globe | radar
  modules = {
    frame = true, brackets = true, tape = true, panel = true, ladder = true, spectrum = true,
    wave = true, matrix = true, sys = true, clock = true, log = true, barcode = true,
    coords = true, reticle = true, scan = true, alert = true, glitch = true, boot = true,
  },
  -- free-zone modules (hud_extra.lua): a module name, or false
  zones = { z1 = "icosa", z2 = "globe", z3 = "strip", z4 = "orrery", z5 = "hexdump", z6 = "helix" },
  -- the dashboard content as an instrument panel (hud_core.lua):
  -- { keys = { { key, hint }, ... }, stats = function() -> { prs, issues, contributions, streak } }
  content = {},
}

function M.configure(opts)
  if type(opts) == "table" then M.config = vim.tbl_deep_extend("force", M.config, opts) end
end

-- Boot delays (in t units; 0.4 per second at the default speed).
local BOOT = {
  frame = 0, brackets = 0.08, tape = 0.16, sys = 0.2, clock = 0.24, panel = 0.3, log = 0.34, ladder = 0.38,
  spectrum = 0.42, wave = 0.46, matrix = 0.5, coords = 0.54, barcode = 0.56, reticle = 0.6,
  z1 = 0.64, z2 = 0.68, z3 = 0.72, z4 = 0.76, z5 = 0.8, z6 = 0.84, core = 0.1,
}

local AMBIENT = {
  "handshake 10.0.4.17 ok", "decrypt sector 7F", "route via node 3", "uplink resync", "trace 172.16.9.2",
  "checksum 0xA41C ok", "mount /vault ro", "key exchange done", "packet loss 0.3%", "carrier lock -64 dBm",
  "tunnel up wg0", "sync shard 12/16",
}
local AMBIENT_EVERY = 2.5 -- wall seconds between ambient log lines
local ALERTS = { "SIGNAL DEGRADED", "INTRUSION DETECTED", "COOLANT LOW", "UNAUTHORIZED ACCESS" }
local BARS = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
local BAR8 = { "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█" }

---------------------------------------------------------------------------
-- simulated terminal: a looping script on a fixed timeline (t units)
---------------------------------------------------------------------------

local TERM_PROMPT = "ghost@nvim ~ % "
local TERM_SCRIPT = {
  { cmd = "git pull --rebase", out = { "remote: Enumerating objects: 42, done.", "remote: Compressing objects: 100% (17/17)", { bar = "unpacking", dur = 0.9 }, "Updating e60640a..4c94939", "Fast-forward", " lua/header_art/hud.lua | 694 +++", " 1 file changed, 694 insertions(+)" } },
  { cmd = "nmap -sV 10.0.4.0/24", out = { "Starting Nmap 7.95", "PORT      STATE    SERVICE", "22/tcp    open     ssh", "443/tcp   open     https", "8080/tcp  filtered http-proxy", "Nmap done: 256 IPs (4 hosts up)" } },
  { cmd = "ssh ghost@10.0.4.17", out = { "Authenticated with ED25519 key", "Last login: Tue Nov 17 02:14", "node-17 :: uplink stable" } },
  { cmd = "decrypt --key ~/.vault/k7 sector7f.bin", out = { "reading 2,411,724 bytes", { bar = "decrypting", dur = 1.6 }, "sha256 a41c09f3..e77b  ok", "wrote sector7f.out" } },
  { cmd = "make -j8", out = { "[ 12%] Building C object core.o", "[ 37%] Building C object net.o", "[ 61%] Building C object crypt.o", "[ 88%] Linking C executable relay", "[100%] Built target relay" } },
  { cmd = "tail -n4 /var/log/uplink.log", out = { "02:14:07 carrier lock  -64 dBm", "02:14:09 resync node-3", "02:14:12 packet loss 0.3%", "02:14:15 tunnel up  wg0" } },
  { cmd = "clear", out = {} },
}
local TERM_TYPE, TERM_LINE, TERM_LEAD, TERM_TAIL = 12, 0.12, 0.9, 0.25

local TERM_TL, TERM_TOTAL = {}, 0
for _, s in ipairs(TERM_SCRIPT) do
  local outs = 0
  for _, o in ipairs(s.out) do outs = outs + (type(o) == "string" and TERM_LINE or o.dur) end
  local e = { s = s, start = TERM_TOTAL, out_start = TERM_LEAD + #s.cmd / TERM_TYPE + 0.15 }
  TERM_TL[#TERM_TL + 1] = e
  TERM_TOTAL = TERM_TOTAL + e.out_start + outs + TERM_TAIL
end

-- Screen lines at script time tt: replay every command started so far
-- (`clear` empties the list), so nothing is stored between frames.
local function term_lines(tt, barw)
  local lines = {}
  for _, e in ipairs(TERM_TL) do
    if e.start > tt then break end
    local loc = tt - e.start
    local n = max(0, floor((loc - TERM_LEAD) * TERM_TYPE))
    lines[#lines + 1] = { prompt = true, text = e.s.cmd:sub(1, n), cursor = n < #e.s.cmd or loc < e.out_start }
    if loc >= e.out_start then
      if e.s.cmd == "clear" then
        lines = {}
      else
        local o = loc - e.out_start
        for _, out in ipairs(e.s.out) do
          if o < 0 then break end
          if type(out) == "string" then
            lines[#lines + 1] = { text = out }
            o = o - TERM_LINE
          else
            local f = clamp(o / out.dur)
            local k = round(f * barw)
            lines[#lines + 1] = { text = "[" .. ("#"):rep(k) .. ("-"):rep(barw - k) .. "] " .. string.format("%3d%% ", round(f * 100)) .. out.bar, bar = true }
            o = o - out.dur
          end
        end
      end
    end
  end
  if #lines == 0 or not lines[#lines].prompt then lines[#lines + 1] = { prompt = true, text = "", cursor = true } end
  return lines
end

---------------------------------------------------------------------------
-- builder
---------------------------------------------------------------------------

function M.build(w, h, box)
  local P = box and { c0 = box.c0, c1 = box.c1, r0 = box.r0, r1 = box.r1 }
    or { c0 = floor(w * 0.35), c1 = floor(w * 0.65), r0 = floor(h * 0.4), r1 = floor(h * 0.6) }
  local L = {
    leftX1 = P.c0 - 9, rightX0 = P.c1 + 9, topY1 = P.r0 - 5, botY0 = P.r1 + 5,
    cx = round((P.c0 + P.c1) / 2), cy = round((P.r0 + P.r1) / 2),
    B = { c0 = P.c0 - 5, c1 = P.c1 + 5, r0 = P.r0 - 3, r1 = P.r1 + 3 },
  }
  local function inside(x, y) return x > P.c0 - 6 and x < P.c1 + 6 and y > P.r0 - 3 and y < P.r1 + 3 end
  local function target(k)
    for j = 0, 29 do
      local x, y = 4 + hash(k, j, 1) * (w - 8), 3 + hash(k, j, 2) * (h - 6)
      if not inside(x, y) then return x, y end
    end
    return 4, 3
  end
  local C = G.canvas(w, h)
  local put, set = C.put, C.set
  local t0

  -- free zones that fit their module (resolved per build: the box is fixed)
  local zones = X.zones(w, h, P, L, max(16, min(64, w - 72)) / 2, max(8, min(28, w - L.rightX0 - 6)), min(h - 6, L.botY0 + 2))
  local extras, cap_log = {}, false
  for _, id in ipairs(X.ZONE_IDS) do
    local name = (M.config.zones or {})[id]
    local m, z = name and X.MODULES[name], zones[id]
    if m and z.w >= m.min[1] and z.h >= m.min[2] then
      extras[#extras + 1] = { id = id, m = m, r = z, A = X.api(C, z) }
      cap_log = cap_log or id == "z6"
    end
  end

  return function(t, val, chr)
    C.begin(val, chr)
    if not t0 or t < t0 then t0 = t end
    local cfg = M.config
    local mods = cfg.modules
    local data = D.sample()

    local function age(id)
      if mods.boot and BOOT[id] then return t - t0 - BOOT[id] end
      return 99
    end
    local function on(id) return mods[id] and age(id) > 0 end
    local function grow(id) return clamp(age(id) * 4) end
    -- Text, typed in while its module boots (`a` = age; 140 characters per unit).
    -- `opaque` blanks the cells under spaces (titles drawn over a border).
    local function text(x, y, s, v, a, opaque)
      local cs = chars(s)
      local n = min(#cs, floor((a or 99) * 140))
      for i = 1, n do
        if cs[i] ~= " " then
          set(x + i - 1, y, v, cs[i])
        elseif opaque then
          set(x + i - 1, y, 0)
        end
      end
      if n < #cs and (a or 99) > 0 then set(x + n, y, 0.9, "█") end
    end
    local function line(x0, y0, x1, y1, v)
      local ch = slope_char(x1 - x0, y1 - y0)
      local n = math.ceil(max(abs(x1 - x0), abs(y1 - y0) * 2)) + 1
      for q = 0, n do put(x0 + (x1 - x0) * q / n, y0 + (y1 - y0) * q / n, v, ch) end
    end
    local function ring(cx, cy, R, segs, rot, v)
      local n = math.ceil(TAU * R * 1.5)
      for i = 0, n - 1 do
        local a = i / n * TAU
        if segs == 0 or (a / TAU * segs + rot) % 1 <= 0.62 then
          local X, Y = R * cos(a), R * sin(a)
          put(cx + X, cy + Y / 2, v, slope_char(-Y, X / 2))
        end
      end
    end

    -- frame: rulers on all four edges, row letters, corner marks
    if on("frame") then
      local reach = min(1, age("frame") * 3)
      for x = 0, floor(w * reach) - 1 do
        put(x, 0, x % 10 == 0 and 0.3 or (x % 5 == 0 and 0.2 or 0.1), x % 5 == 0 and "┬" or "─")
        put(w - 1 - x, h - 1, x % 10 == 0 and 0.25 or 0.08, x % 5 == 0 and "┴" or "─")
      end
      for x = 10, w * reach - 4, 10 do text(x - 1, 1, pad(x, 3), 0.18) end
      for y = 1, floor(h * reach) - 2 do
        put(0, y, y % 4 == 0 and 0.25 or 0.1, y % 4 == 0 and "├" or "│")
        put(w - 1, h - 1 - y, y % 4 == 0 and 0.2 or 0.08, y % 4 == 0 and "┤" or "│")
      end
      for y = 4, h * reach - 2, 8 do text(1, y, string.char(64 + floor(y / 4)), 0.18) end
      set(0, 0, 0.5, "┌"); set(w - 1, 0, 0.5, "┐"); set(0, h - 1, 0.5, "└"); set(w - 1, h - 1, 0.5, "┘")
    end

    -- brackets around the content, title (cwd // branch), progress rail
    if on("brackets") then
      local a, B = age("brackets"), L.B
      local pulse, arm = 0.55 + 0.3 * sin(t * 2.5), round(4 * grow("brackets"))
      local function corner(x, y, sx, sy, c)
        put(x, y, pulse, c)
        for i = 1, arm do put(x + sx * i, y, pulse, "━") end
        put(x, y + sy, pulse, "┃")
      end
      corner(B.c0, B.r0, 1, 1, "┏"); corner(B.c1, B.r0, -1, 1, "┓")
      corner(B.c0, B.r1, 1, -1, "┗"); corner(B.c1, B.r1, -1, -1, "┛")
      local room = B.c1 - B.c0 - 12
      local title = string.format("[ %s  //  %s  //  SESSION 0x%02X ]", data.cwd, data.branch or "no git", data.pid % 256)
      if #chars(title) > room then title = string.format("[ %s  //  %s ]", data.cwd, data.branch or "no git") end
      if #chars(title) <= room then text(round((B.c0 + B.c1 - #chars(title)) / 2), B.r0, title, 0.5, a - 0.1) end
      local r0, r1 = B.c0 + 7, B.c1 - 7
      if r1 > r0 then
        for x = r0, r1, 2 do put(x, B.r1, 0.14, "┈") end
        local pip = r0 + (t * 6) % (r1 - r0)
        put(pip, B.r1, 0.85, "■"); put(pip - 2, B.r1, 0.4, "─"); put(pip - 4, B.r1, 0.25, "─")
      end
    end

    -- heading tape above the content
    if on("tape") then
      local yT = max(4, floor((3 + L.topY1) / 2) + 1)
      local tw = max(16, min(64, w - 72)) * grow("tape")
      local heading = (90 + 40 * sin(t * 0.3) + t * 5) % 360
      for x = round(L.cx - tw / 2), L.cx + tw / 2 do
        local d = x - L.cx + heading
        if d % 10 < 1 then
          put(x, yT, 0.4, "┬")
          local q = round(d / 10)
          text(x - 1, yT - 1, pad((q * 10) % 360, 3), q % 3 == 0 and 0.5 or 0.3)
        elseif d % 5 < 1 then
          put(x, yT, 0.25, "┬")
        else
          put(x, yT, 0.13, "─")
        end
      end
      set(L.cx, yT + 1, 0.95, "^")
      text(L.cx - 4, yT + 2, "HDG " .. pad(heading, 3), 0.6, age("tape") - 0.2)
    end

    -- system readouts (live)
    if on("sys") then
      local a, up = age("sys"), data.uptime
      local ld = data.load
      local rows = {
        { "SYS", "NVIM " .. data.version .. "  // ONLINE" },
        { "PLG", data.plugins and string.format("%d/%d  %.1f ms", data.loaded, data.plugins, data.startup) or "--" },
        { "MEM", string.format("%.1f MB", data.mem) },
        { "LOAD", string.format("%.2f %.2f %.2f", ld[1] or 0, ld[2] or 0, ld[3] or 0) },
        { "UP", string.format("%02d:%02d:%02d", floor(up / 3600), floor(up / 60) % 60, floor(up) % 60) },
        { "BUF", string.format("%d   LSP %d   DIAG %d", data.bufs, data.lsp, data.diag) },
      }
      for i, r in ipairs(rows) do
        local d = (i - 1) * 0.04
        text(3, 2 + i, r[1], 0.25, a - d)
        text(9, 2 + i, r[2], i == 1 and 0.6 or 0.45, a - d - 0.02)
      end
      if a > 0.3 then
        local fill, bx = round(min(1, data.mem / 1024) * 12), 9 + #rows[3][2] + 2
        for i = 0, 11 do put(bx + i, 5, i < fill and 0.5 or 0.12, i < fill and "▓" or "░") end
      end
    end

    -- clock + uplink, top right
    if on("clock") then
      local a, x = age("clock"), w - 28
      local s, us = D.now()
      text(x, 3, "TIME " .. os.date("%H:%M:%S", s) .. string.format(".%02d", floor(us / 1e4)), 0.6, a)
      local up = floor((t * 0.6) % 1 * 12)
      text(x, 4, "UPLINK", 0.35, a - 0.05)
      if a > 0.1 then
        for i = 0, 11 do put(x + 7 + i, 4, i < up and 0.6 or 0.15, i < up and "▓" or "░") end
      end
      text(x, 5, string.format("SIG  %d dBm", -62 - round(6 * hash(floor(t * 4), 9, 9))), 0.35, a - 0.1)
      text(x, 6, "T+   " .. pad((t * 25) % 100000, 5), 0.3, a - 0.15)
    end

    -- left panel: simulated terminal, or a gauge
    if on("panel") then
      local a = age("panel")
      if cfg.panel == "terminal" then
        local x0, x1 = 3, L.leftX1
        local y0 = max(L.topY1 + 1, 12)
        local y1 = mods.matrix and L.botY0 - 3 or h - 6
        if x1 - x0 >= 24 and y1 - y0 >= 6 then
          local yb = round(y0 + (y1 - y0) * grow("panel"))
          for x = x0 + 1, x1 - 1 do
            put(x, y0, 0.35, "─")
            if yb == y1 then put(x, y1, 0.35, "─") end
          end
          for y = y0 + 1, yb - 1 do put(x0, y, 0.35, "│"); put(x1, y, 0.35, "│") end
          put(x0, y0, 0.45, "┌"); put(x1, y0, 0.45, "┐")
          if yb == y1 then put(x0, y1, 0.45, "└"); put(x1, y1, 0.45, "┘") end
          text(x0 + 2, y0, "┤ zsh :: ttys004 ├", 0.5, a - 0.1, true)
          text(x1 - 6, y0, " ■ □ ", 0.35, a - 0.1, true)
          if a >= 0.35 then
            local inner, rows = x1 - x0 - 3, y1 - y0 - 1
            local lines = term_lines((t - t0) % TERM_TOTAL, max(6, min(20, inner - 18)))
            local first = max(1, #lines - rows + 1)
            for idx = first, #lines do
              local l, y = lines[idx], y0 + 1 + idx - first
              local s = l.prompt and (TERM_PROMPT .. l.text) or l.text
              if #s > inner then s = l.prompt and s:sub(#s - inner + 1) or s:sub(1, inner) end
              if l.prompt then
                local p = max(0, #TERM_PROMPT - (#TERM_PROMPT + #l.text - #s))
                text(x0 + 2, y, s:sub(1, p), 0.3)
                text(x0 + 2 + p, y, s:sub(p + 1), 0.7)
                if l.cursor and (t * 2.5) % 1 < 0.6 then set(x0 + 2 + #s, y, 0.9, "█") end
              else
                text(x0 + 2, y, s, l.bar and 0.6 or (idx == #lines and 0.55 or 0.38))
              end
            end
          end
        end
      else
        local lx, ly = round((2 + L.leftX1) / 2), L.cy
        local R = min((L.leftX1 - 6) / 2, P.r1 - P.r0 + 8) * grow("panel")
        if R >= 4 then
          if cfg.panel == "rings" then
            ring(lx, ly, R, 12, t * 0.25, 0.55)
            ring(lx, ly, R * 0.62, 5, -t * 0.4, 0.35)
            for k = 0, 35 do
              local an, rr = k / 36 * TAU, R * 1.14
              put(lx + rr * cos(an), ly + rr * sin(an) / 2, k % 9 == 0 and 0.5 or 0.18, k % 9 == 0 and "+" or ".")
            end
            local na = t * 0.9
            line(lx, ly, lx + R * 0.5 * cos(na), ly + R * 0.25 * sin(na), 0.8)
            put(lx, ly, 0.9, "+")
            text(lx - 4, round(ly + R / 2 + 2), "GYRO " .. pad((na * 57.3) % 360, 3), 0.45, a - 0.3)
          elseif cfg.panel == "globe" then
            local rot, ct, st = t * 0.6, cos(0.4), sin(0.4)
            local function proj(phi, lam)
              local x, y, z = cos(phi) * cos(lam + rot), sin(phi), cos(phi) * sin(lam + rot)
              local y2, z2 = y * ct - z * st, y * st + z * ct
              return lx + x * R, ly - y2 * R / 2, z2
            end
            local function trace(f, n)
              local px, py, pz = f(0)
              for i = 1, n do
                local x, y, z = f(i / n)
                put(x, y, pz < 0 and 0.6 or 0.15, slope_char(x - px, y - py))
                px, py, pz = x, y, z
              end
            end
            for _, la in ipairs({ -60, -30, 0, 30, 60 }) do
              trace(function(u) return proj(la * pi / 180, u * TAU) end, 120)
            end
            for k = 0, 7 do
              trace(function(u) return proj(-pi / 2 + u * pi, k * pi / 4) end, 80)
            end
            ring(lx, ly, R + 1.5, 0, 0, 0.3)
            text(lx - 6, round(ly + R / 2 + 2), "ORBIT " .. pad((rot * 57.3) % 360, 3) .. " DEG", 0.45, a - 0.3)
          else -- radar
            local sweep = (t * 1.1) % TAU
            for y = floor(ly - R / 2), ly + R / 2 do
              for x = floor(lx - R), lx + R do
                local X, Y = x - lx, (y - ly) * 2
                local rr = math.sqrt(X * X + Y * Y)
                if rr <= R + 0.5 then
                  local behind = (sweep - math.atan2(Y, X)) % TAU
                  local glow = exp(-behind * 2.4)
                  if behind * rr < 0.8 and rr > 1 then
                    put(x, y, 0.9, slope_char(X, Y / 2))
                  else
                    for _, f in ipairs({ 1 / 3, 2 / 3, 1 }) do
                      if abs(rr - R * f) < 0.55 then put(x, y, 0.12 + glow * 0.4, slope_char(-Y, X / 2)) end
                    end
                    if hash(x, y, 5) < 0.04 then put(x, y, 0.1 + glow * 0.85, "+") end
                  end
                end
              end
            end
            text(lx - 5, round(ly + R / 2 + 2), "SCAN " .. pad((sweep * 57.3) % 360, 3), 0.45, a - 0.3)
          end
        end
      end
    end

    -- altitude ladder, right edge
    if on("ladder") then
      local x, y0, y1 = w - 3, L.topY1 + 2, L.botY0 - 2
      local alt, mid = 1200 + 300 * sin(t * 0.4), round((y0 + y1) / 2)
      for y = y0, y1 do
        if abs(y - mid) <= (y1 - y0) / 2 * grow("ladder") then
          local v = alt + (mid - y) * 10
          local major = v % 50 < 10
          put(x, y, major and 0.35 or 0.14, major and "┤" or "│")
          if major and y ~= mid then text(x - 5, y, pad(round(v / 50) * 50, 4), 0.25) end
        end
      end
      text(x - 7, mid, "<" .. pad(alt, 4) .. "]", 0.85, age("ladder") - 0.2)
    end

    -- event log: real events (bright) between ambient lines
    if on("log") then
      local a, x0 = age("log"), L.rightX0
      local x1 = cap_log and min(w - 11, x0 + 44) or w - 11
      local width = x1 - x0
      local y0, y1 = L.topY1 + 3, L.botY0 - 2
      local rows = y1 - y0
      if width >= 14 and rows >= 2 then
        text(x0, y0 - 1, "── EVENT LOG " .. ("─"):rep(width - 13), 0.3, a)
        local now = D.wall()
        local items = {}
        for _, e in ipairs(D.events) do items[#items + 1] = { time = e.time, text = e.text, real = true } end
        local kmax = floor((now - D.start_wall) / AMBIENT_EVERY)
        for k = max(0, kmax - rows), kmax do
          items[#items + 1] = { time = D.start_wall + k * AMBIENT_EVERY, text = AMBIENT[floor(hash(k, 3, 3) * #AMBIENT) + 1] }
        end
        table.sort(items, function(p, q) return p.time < q.time end)
        local first = max(1, #items - rows + 1)
        for idx = first, #items do
          local it, k = items[idx], idx - first
          local newest = idx == #items
          local s = os.date("%H:%M:%S", floor(it.time)) .. " " .. it.text
          local cs = chars(s)
          if #cs > width then s = table.concat(cs, "", 1, width) end
          local v = it.real and (newest and 0.85 or 0.55) or (newest and 0.6 or 0.12 + 0.25 * (k / rows))
          text(x0, y0 + k, s, v, newest and (now - it.time) * 40 / 140 or 99)
        end
      end
    end

    -- spectrum with falling peaks, bottom right
    if on("spectrum") then
      local nb = max(8, min(28, w - L.rightX0 - 6))
      local bx, base, H6 = w - 5 - nb, h - 3, 6
      local g = grow("spectrum")
      local function hv(i, tt)
        return (0.5 + 0.5 * sin(i * 1.7 + tt * 2.3 + sin(tt * 0.7 + i))) * H6 * (1 - i / nb * 0.35) * g
      end
      text(bx, base - H6 - 1, "SPECTRUM", 0.3, age("spectrum"))
      for i = 0, nb - 1 do
        local v = hv(i, t)
        for j = 0, H6 - 1 do
          local f = clamp(v - j)
          if f <= 0 then break end
          put(bx + i, base - j, 0.3 + 0.05 * j, BARS[max(1, round(f * 8))])
        end
        local peak = 0
        for k = 0, 9 do peak = max(peak, hv(i, t - k * 0.06) * (1 - k * 0.05)) end
        put(bx + i, base - min(H6 - 1, floor(peak)), 0.6, "▔")
      end
      for i, lab in ipairs({ "20", "200", "2k", "20k" }) do
        if (i - 1) * 7 < nb then text(bx + (i - 1) * 7, base + 1, lab, 0.18) end
      end
    end

    -- waveform under the content
    if on("wave") then
      local yc, x0, x1, amp = min(h - 6, L.botY0 + 2), P.c0 + 2, P.c1 - 2, 2
      local span = (x1 - x0) * grow("wave")
      local env = 0.6 + 0.4 * sin(t * 0.7)
      local tq = floor(t * 12)
      local function sig(x)
        return yc + amp * (sin(x * 0.23 - t * 4) * 0.7 + sin(x * 0.61 - t * 6.3) * 0.25 + (hash(x, tq, 4) - 0.5) * 0.25) * env
      end
      for x = x0, x0 + span, 2 do put(x, yc, 0.1, "┈") end
      for x = x0 + 1, x0 + span do line(x - 1, sig(x - 1), x, sig(x), 0.55) end
      text(x0, yc - amp - 1, string.format("CH1  2V/div  %d Hz", 48 + round(4 * sin(t))), 0.3, age("wave"))
    end

    -- process map: listed buffers first (bright = modified), then ambient cells
    if on("matrix") then
      local a, y0 = age("matrix"), L.botY0
      text(3, y0 - 1, string.format("PROC MAP  %d BUF", data.bufs), 0.3, a)
      for i = 0, 63 do
        if i / 64 > a * 2 then break end
        local x, y = 3 + i % 16, y0 + floor(i / 16)
        local b = data.buflist[i + 1]
        if b then
          put(x, y, b.modified and 0.95 or 0.5, b.modified and "█" or "▓")
        else
          local ph = t * 2 + hash(i, 1, 1) * 3
          local act = hash(i, floor(ph), 2) < 0.45
          put(x, y, act and ((ph % 1 < 0.15) and 0.45 or 0.25) or 0.1, act and "▒" or "░")
        end
      end
    end

    -- barcode
    if on("barcode") then
      local a, y = age("barcode"), 10
      local e = floor(t * 0.5)
      for i = 0, min(25, floor(a * 120)) do put(3 + i, y, 0.35, BAR8[floor(hash(i, e, 7) * 8) + 1]) end
      text(3, y + 1, "ID 7F3A-" .. pad(hash(e, 2, 2) * 9999, 4), 0.2, a - 0.1)
    end

    -- coordinates
    if on("coords") then
      local a = age("coords")
      text(3, h - 4, "LAT 35.6895N  LON 139.6917E", 0.22, a)
      text(3, h - 3, "GRID 7-ALPHA  //  SECTOR " .. pad((t / 3) % 100, 2), 0.22, a - 0.05)
    end

    -- free-zone modules (hud_extra.lua)
    for _, e in ipairs(extras) do
      local a = age(e.id)
      if a > 0 then e.m.draw(e.A, e.r, t, grow(e.id), a, data) end
    end

    -- reticle: glides to a target outside the content, locks, moves on
    if on("reticle") then
      local k, ph = floor(t * 0.25), (t * 0.25) % 1
      local e = smooth(0, 0.55, ph)
      local ax, ay = target(k - 1)
      local bx, by = target(k)
      local rx, ry = ax + (bx - ax) * e, ay + (by - ay) * e
      local locked = ph > 0.6
      local s = locked and 2 or 4 - 2 * smooth(0.45, 0.6, ph)
      for x = 0, w - 1, 2 do put(x, ry, 0.07, "┈") end
      for y = 0, h - 1 do put(rx, y, 0.07, "┊") end
      local sx, sy, cv = round(s * 1.5), s > 2.5 and 2 or 1, locked and 0.95 or 0.7
      put(rx - sx, ry - sy, cv, "┌"); put(rx + sx, ry - sy, cv, "┐")
      put(rx - sx, ry + sy, cv, "└"); put(rx + sx, ry + sy, cv, "┘")
      put(rx, ry, 0.95, "+")
      local lx, ly = round(rx) + sx + 2, round(ry) - sy
      text(lx, ly, "TGT-" .. pad(hash(k, 3, 3) * 900 + 100, 3), 0.55)
      if locked then
        if (t * 10) % 1 < 0.6 then text(lx, ly + 1, "LOCK", 0.9) end
        text(lx, ly + 2, string.format("RNG %.2fkm", 0.4 + hash(k, 4, 4) * 3), 0.4)
      else
        text(lx, ly + 1, "ACQ" .. ("."):rep(floor(ph * 8) % 4), 0.4)
      end
    end

    -- alert banner every 8 t (20 s at speed 0.4); real errors when there are any
    if mods.alert then
      local cyc = t % 8
      if cyc > 0.2 and cyc < 1.4 then
        local what = data.errors > 0 and string.format("%d DIAGNOSTIC ERROR%s", data.errors, data.errors == 1 and "" or "S")
          or ALERTS[floor(t / 8) % #ALERTS + 1]
        local msg = "╱╱╱  !! " .. what .. " !!  ╱╱╱"
        text(round(L.cx - #chars(msg) / 2), min(h - 2, P.r1 + 3), msg, (t * 6) % 1 < 0.6 and 0.9 or 0.3)
      end
    end

    -- scan bar: a bright band rolling down over everything drawn
    if mods.scan then
      local sy = (t * 2.5) % (h + 10) - 5
      for y = max(0, floor(sy - 2)), min(h - 1, sy + 2) do
        local b = 0.3 * (1 - abs(y - sy) / 2)
        if b > 0 then
          for x = 0, w - 1 do
            local i = y * w + x + 1
            if val[i] > 0 then val[i] = clamp(val[i] + b) end
          end
        end
      end
    end

    -- glitch: a band of rows torn sideways for one beat
    if mods.glitch then
      local e = floor(t * 6)
      if hash(e, 1, 1) < 0.14 then
        local y0, n = floor(hash(e, 2, 2) * h), 1 + floor(hash(e, 3, 3) * 3)
        local sh = (hash(e, 4, 4) < 0.5 and -1 or 1) * (1 + floor(hash(e, 5, 5) * 5))
        for y = y0, min(h, y0 + n) - 1 do
          local rv, rc = {}, {}
          for x = 0, w - 1 do rv[x], rc[x] = val[y * w + x + 1], chr[y * w + x + 1] end
          for x = 0, w - 1 do
            local s = (x - sh) % w
            val[y * w + x + 1], chr[y * w + x + 1] = rv[s], rc[s]
          end
        end
      end
    end

    -- the dashboard's content (hud_core.lua), drawn last on a cleared box so
    -- the reticle, scan bar and glitch never cross it
    for y = max(0, P.r0), min(h - 1, P.r1) do
      for x = max(0, P.c0), min(w - 1, P.c1) do
        val[y * w + x + 1], chr[y * w + x + 1] = 0, false
      end
    end
    local ix, iy = P.c0 + 6, P.r0 + 1 -- the box is padded 6 cols / 1 row (header_art PAD_C/PAD_R)
    if box and P.c1 - P.c0 + 1 >= K.W + 12 and P.r1 - P.r0 + 1 >= K.H + 2 then
      K.draw(set, ix + floor((P.c1 - P.c0 + 1 - 12 - K.W) / 2), iy, age("core"), cfg.content)
    else
      K.draw_compact(set, L.cx, L.cy)
    end
  end
end

return M
