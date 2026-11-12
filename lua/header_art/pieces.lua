-- Generative pieces for the dashboard background.
--
-- Each piece is `function(w, h) -> frame(t, val)`: it is built once per window
-- size and `frame` then fills `val` (a flat 1-based array, index = y * w + x + 1,
-- x/y zero-based) with a level in 0..1 for time `t` in seconds.
-- `frame` also gets a third argument, `chr` (same indexing, cleared to `false`
-- every frame): a piece may put a character in a cell, which then replaces the
-- charset's (descent draws its contours with their direction this way).
--
-- Terminal cells are about twice as tall as they are wide, and windows differ in
-- size, so the field pieces work in a normalised space: u runs 0..65 across the
-- window and v 0..44 down it (what a 65 x 22 header looks like), whatever the
-- real size. That is why every piece keeps its look when stretched.

local sin, cos, sqrt, exp, hypot = math.sin, math.cos, math.sqrt, math.exp, function(a, b) return math.sqrt(a * a + b * b) end
local floor, min, max, pi = math.floor, math.min, math.max, math.pi

local function clamp(v) return v < 0 and 0 or (v > 1 and 1 or v) end

-- Tiny deterministic generator, so a piece never touches math.random's state.
local function rng(seed)
  return function()
    seed = (seed * 1664525 + 1013904223) % 4294967296
    return seed / 4294967296
  end
end

local M = {}

function M.plasma(w, h)
  local n = w * h
  local U, V, D = {}, {}, {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local i = y * w + x + 1
      local u, v = x * 65 / w, y * 44 / h
      U[i], V[i], D[i] = u, v, hypot(u - 32.5, v - 22)
    end
  end
  return function(t, val)
    local t13, t07, t14 = t * 1.3, t * 0.7, t * 1.4
    for i = 1, n do
      local u, v = U[i], V[i]
      local s = sin(u * 0.16 + t) + sin(v * 0.12 + t13) + sin((u + v) * 0.09 + t07) + sin(D[i] * 0.14 - t14)
      val[i] = clamp(((s + 4) / 8 - 0.12) * 1.3)
    end
  end
end

function M.torus(w, h)
  local n = w * h
  local sc = min(w / 65, h / 22)
  local K1, K2 = 30 * sc, 5
  local zb = {}
  return function(t, val)
    for i = 1, n do val[i], zb[i] = 0, 0 end
    local A, B = t * 0.9, t * 0.55
    local cA, sA, cB, sB = cos(A), sin(A), cos(B), sin(B)
    local th = 0
    while th < 2 * pi do
      local ct, st = cos(th), sin(th)
      local ph = 0
      while ph < 2 * pi do
        local cp, sp = cos(ph), sin(ph)
        local cx, cy = 2 + ct, st
        local x = cx * (cB * cp + sA * sB * sp) - cy * cA * sB
        local y = cx * (sB * cp - sA * cB * sp) + cy * cA * cB
        local ooz = 1 / (K2 + cA * cx * sp + cy * sA)
        local xp, yp = floor(w / 2 + K1 * ooz * x), floor(h / 2 - K1 * ooz * y * 0.5)
        local L = cp * ct * sB - cA * ct * sp - sA * st + cB * (cA * st - ct * sA * sp)
        if L > 0 and xp >= 0 and xp < w and yp >= 0 and yp < h then
          local i = yp * w + xp + 1
          if ooz > zb[i] then zb[i], val[i] = ooz, (L / 1.414) ^ 0.8 end
        end
        ph = ph + 0.025 / sc
      end
      th = th + 0.06 / sc
    end
  end
end

function M.orb(w, h)
  local cx, cy = w / 2, h / 2
  local R = 10 * min(w / 65, h / 22) * 1.35
  return function(t, val)
    local lx, ly, lz = cos(t * 0.5), -0.5, sin(t * 0.5)
    local ln = sqrt(lx * lx + ly * ly + lz * lz)
    local cr, sr = cos(t * 0.35), sin(t * 0.35)
    for y = 0, h - 1 do
      local ny = (y - cy) / R
      for x = 0, w - 1 do
        local nx = (x - cx) / (R * 2)
        local r2 = nx * nx + ny * ny
        local i = y * w + x + 1
        if r2 >= 1 then
          val[i] = exp(-(sqrt(r2) - 1) * 9) * 0.35
        else
          local nz = sqrt(1 - r2)
          local u = nx * cr + nz * sr
          local tex = 0.5 + 0.5 * sin(u * 7 + sin(ny * 5 + t * 0.8) * 1.6 + ny * 2)
          local diff = clamp((nx * lx + ny * ly + nz * lz) / ln)
          val[i] = clamp(0.08 + diff * (0.55 + 0.45 * tex) + (1 - nz) ^ 3 * 0.25)
        end
      end
    end
  end
end

function M.rings(w, h)
  local n = w * h
  local U, V = {}, {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local i = y * w + x + 1
      U[i], V[i] = x * 65 / w, y * 44 / h
    end
  end
  return function(t, val)
    local ax, ay = 65 * 0.3 + sin(t * 0.5) * 10, 22 + cos(t * 0.4) * 8
    local bx, by = 65 * 0.7 + cos(t * 0.45) * 10, 22 + sin(t * 0.6) * 8
    local ph = t * 2.2
    for i = 1, n do
      local u, v = U[i], V[i]
      local s = sin(hypot(u - ax, v - ay) * 0.75 - ph) + sin(hypot(u - bx, v - by) * 0.75 - ph)
      val[i] = clamp(((s + 2) / 4) ^ 2.2 * 1.2)
    end
  end
end

function M.flow(w, h)
  local n = w * h
  local rand = rng(11)
  local sx, sy = w / 65, h / 22
  local P = {}
  for k = 1, floor(70 * sx * sy + 0.5) do P[k] = { x = rand() * w, y = rand() * h, age = rand() * 60 } end
  local buf = {}
  for i = 1, n do buf[i] = 0 end
  local last
  local function ang(x, y, t)
    local u, v = x / sx, y / sy * 2
    return (sin(u * 0.09 + t * 0.4) + cos(v * 0.15 - t * 0.3) + sin((u + v) * 0.05 + t * 0.2)) * 1.7
  end
  return function(t, val)
    if last and t > last then
      for _ = 1, 2 do
        for i = 1, n do buf[i] = buf[i] * 0.92 end
        for _, p in ipairs(P) do
          local a = ang(p.x, p.y, t)
          p.x, p.y, p.age = p.x + cos(a) * 0.9 * sx, p.y + sin(a) * 0.45 * sy, p.age + 1
          if p.age > 70 or p.x < 0 or p.x >= w or p.y < 0 or p.y >= h then
            p.x, p.y, p.age = rand() * w, rand() * h, 0
          else
            local i = floor(p.y) * w + floor(p.x) + 1
            buf[i] = min(1, buf[i] + 0.5)
          end
        end
      end
    end
    last = t
    for i = 1, n do val[i] = buf[i] end
  end
end

function M.terrain(w, h)
  local n = w * h
  local sy = h / 22
  local rows = max(2, floor(13 * sy + 0.5))
  return function(t, val)
    for i = 1, n do val[i] = 0 end
    for r = 0, rows - 1 do
      local f = r / (rows - 1)
      local base = (5 + f * 13 * 1.35) * sy
      local level = 0.35 + 0.65 * f
      local ii = r * 13 / rows
      for x = 0, w - 1 do
        local u = x * 65 / w
        local env = exp(-((u - 32.5) / 17) ^ 2)
        local hh = env * (3.2 + 2.2 * f) * sy
          * (0.55 + 0.45 * sin(u * 0.55 + ii * 1.7 - t * 1.3) * sin(u * 0.23 - t * 0.7 + ii)
            + 0.2 * sin(u * 1.3 + ii * 3 + t * 2))
        local y = floor(base - hh + 0.5)
        for yy = max(0, y), h - 1 do val[yy * w + x + 1] = 0 end -- hide what is behind this ridge
        if y >= 0 and y < h then val[y * w + x + 1] = level end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Particle galaxies (galaxy, galaxies). Picked from a browser mockup of seven
-- variants; the same LCG and the same order of rand() calls reproduce exactly
-- the stars shown there. Stars are scattered (gaussian) around logarithmic
-- arms, plus an exponential disk and a bulge; every frame they are turned
-- rigidly (the arms trail: th = ln(r)/tan(pitch) grows outward, so the
-- rotation goes toward -th) and splatted bilinearly into the grid. Brightness
-- is 1 - exp(-acc * gain), with `gain` fixed on the first frame from the 98.5th
-- percentile, so the bulge doesn't wash the arms out.
---------------------------------------------------------------------------

local log, abs = math.log, math.abs

-- The browser mockups ran at speed 1; the dashboard's default is 0.4. Scale
-- time so the default looks like what was chosen there (galaxy, galaxies,
-- descent).
local MOCKUP_TIME = 2.5

local function gauss(rand)
  local u = 0
  while u == 0 do u = rand() end
  return sqrt(-2 * log(u)) * cos(2 * pi * rand())
end

-- o: n, arms, pitch (deg), width (arm half-width, disk units), bulge/disk
-- (fractions of stars), knots (fraction of bright star-forming knots), seed.
-- Returns { r (0..1), theta, weight } per star.
local function make_stars(o)
  local rand = rng(o.seed)
  local cot = 1 / math.tan(math.rad(o.pitch))
  local stars = {}
  for k = 1, o.n do
    local kind = rand()
    local rad, th, wgt
    if kind < o.bulge then
      rad = abs(gauss(rand)) * (o.bulge_r or 0.06)
      th = rand() * 2 * pi
      wgt = 1.2
    elseif kind < o.bulge + o.disk then
      rad = -log(1 - rand()) * 0.25
      th = rand() * 2 * pi
      wgt = 0.45
    else
      rad = 0.07 - log(1 - rand()) * 0.26
      if rad > 1 then rad = 0.07 + rand() * 0.9 end
      local arm = floor(rand() * o.arms)
      local width = o.width * (0.7 + rad) -- arms widen outward
      th = log(rad) * cot + arm * 2 * pi / o.arms + gauss(rand) * width / rad
      wgt = rand() < o.knots and 3.5 or 1
    end
    stars[k] = { rad, th, wgt }
  end
  return stars
end

-- g: cx, cy (cells), R (disk radius in cell widths), ci (cos inclination),
-- pa (position angle), omega (pattern speed, rad per second of t).
local function splat(acc, w, h, stars, g, t)
  local cp, sp, rot = cos(g.pa), sin(g.pa), -g.omega * t
  local R, Rh, ci = g.R, g.R * 0.5, g.ci -- rows count double
  for k = 1, #stars do
    local s = stars[k]
    local th = s[2] + rot
    local x, y = s[1] * cos(th), s[1] * sin(th) * ci
    local px, py = g.cx + (x * cp - y * sp) * R, g.cy + (x * sp + y * cp) * Rh
    local x0, y0 = floor(px), floor(py)
    local fx, fy, wv = px - x0, py - y0, s[3]
    if y0 >= 0 and y0 < h then
      local b = y0 * w + x0 + 1
      if x0 >= 0 and x0 < w then acc[b] = acc[b] + (1 - fx) * (1 - fy) * wv end
      if x0 + 1 >= 0 and x0 + 1 < w then acc[b + 1] = acc[b + 1] + fx * (1 - fy) * wv end
    end
    if y0 + 1 >= 0 and y0 + 1 < h then
      local b = (y0 + 1) * w + x0 + 1
      if x0 >= 0 and x0 < w then acc[b] = acc[b] + (1 - fx) * fy * wv end
      if x0 + 1 >= 0 and x0 + 1 < w then acc[b + 1] = acc[b + 1] + fx * fy * wv end
    end
  end
end

local function exposure(acc, q)
  local nz = {}
  for i = 1, #acc do
    if acc[i] > 0 then nz[#nz + 1] = acc[i] end
  end
  if #nz == 0 then return 1 end
  table.sort(nz)
  return 2.6 / nz[min(#nz, floor(#nz * q) + 1)]
end

-- specs: list of make_stars options, each with place(w, h) -> splat's `g`.
-- stars: density of twinkling background stars (per cell).
local function particle_piece(specs, stars_density)
  return function(w, h)
    local n = w * h
    local gals = {}
    for k, sp in ipairs(specs) do gals[k] = { stars = make_stars(sp), g = sp.place(w, h) } end
    local rand = rng(99)
    local sky = {}
    for k = 1, floor(n * stars_density) do sky[k] = { floor(rand() * n) + 1, rand() * 2 * pi, 0.5 + rand() * 2 } end
    local acc, gain = {}, nil
    return function(t, val)
      t = t * MOCKUP_TIME
      for i = 1, n do acc[i] = 0 end
      for _, gl in ipairs(gals) do splat(acc, w, h, gl.stars, gl.g, t) end
      gain = gain or exposure(acc, 0.985)
      for i = 1, n do val[i] = 1 - exp(-acc[i] * gain) end
      for _, s in ipairs(sky) do
        local i = s[1]
        val[i] = max(val[i], 0.28 + 0.22 * sin(t * s[3] * 3 + s[2]))
      end
    end
  end
end

-- Mockup "A": one Sc spiral around the content, its arms leaving by all four
-- sides (the bulge sits under the clock).
M.galaxy = particle_piece({
  {
    n = 9000, arms = 2, pitch = 22, width = 0.035, bulge = 0.08, disk = 0.22, knots = 0.06, seed = 3,
    place = function(w, h) return { cx = w / 2, cy = h / 2, R = w * 0.5, ci = 0.62, pa = 0.35, omega = 0.12 } end,
  },
}, 0.004)

-- Mockup "F": four small spirals in the corners the content leaves free, each
-- with its own tilt and speed, over a field of stars.
M.galaxies = particle_piece({
  {
    n = 2600, arms = 2, pitch = 22, width = 0.04, bulge = 0.1, disk = 0.2, knots = 0.05, seed = 11,
    place = function(w, h) return { cx = w * 0.13, cy = h * 0.26, R = w * 0.13, ci = 0.8, pa = 0.5, omega = 0.18 } end,
  },
  {
    n = 2200, arms = 2, pitch = 26, width = 0.045, bulge = 0.1, disk = 0.2, knots = 0.05, seed = 12,
    place = function(w, h) return { cx = w * 0.86, cy = h * 0.22, R = w * 0.11, ci = 0.45, pa = -0.6, omega = 0.22 } end,
  },
  {
    n = 2400, arms = 3, pitch = 28, width = 0.04, bulge = 0.08, disk = 0.25, knots = 0.06, seed = 13,
    place = function(w, h) return { cx = w * 0.8, cy = h * 0.84, R = w * 0.12, ci = 0.92, pa = 0.0, omega = 0.15 } end,
  },
  {
    n = 1400, arms = 2, pitch = 20, width = 0.04, bulge = 0.14, disk = 0.25, knots = 0.03, seed = 14,
    place = function(w, h) return { cx = w * 0.2, cy = h * 0.84, R = w * 0.08, ci = 0.28, pa = 0.25, omega = 0.25 } end,
  },
}, 0.006)

---------------------------------------------------------------------------
-- descent: the portfolio's loss surface (~/Downloads/GitHub/portfolio,
-- src/scripts/surface.ts), picked from a browser mockup ("Superficie de
-- pérdida", proposal C). Its level sets are drawn as one-cell hairlines with a
-- character for their direction, and every half second a short graphite probe
-- descends the gradient from a random point and fades; a probe that settles in
-- a well sends out two ripples. Uses frame's third argument, `chr`.
--
-- Coordinates: x in cells, y in square units (2 per row). The generator and the
-- order of its calls match the mockup, so the same probes fall in the same
-- places.
---------------------------------------------------------------------------

-- The portfolio's generator (Park-Miller).
local function rng_pm(seed)
  local s = seed % 2147483647
  if s == 0 then s = 1 end
  return function()
    s = (s * 16807) % 2147483647
    return s / 2147483647
  end
end

-- A well in each corner the dashboard's content leaves free, a ridge between
-- neighbouring wells, seeded bumps for structure, a gentle tilt down.
local function loss_surface(w, h, seed)
  local rand, H2 = rng_pm(seed), h * 2
  local s0 = min(w, H2) * 0.2
  local basins = {}
  for k, c in ipairs({ { 0.13, 0.24 }, { 0.86, 0.22 }, { 0.85, 0.8 }, { 0.15, 0.78 } }) do
    basins[k] = { x = c[1] * w, y = c[2] * H2 }
  end
  local G = {}
  for k, c in ipairs(basins) do
    G[#G + 1] = { x = c.x, y = c.y, a = k == 1 and -1.3 or -1, s = s0 * (k == 1 and 1.3 or 0.9 + 0.25 * rand()) }
    local nb = basins[k % #basins + 1]
    local gx = (c.x + nb.x) / 2 + (rand() - 0.5) * s0
    local gy = (c.y + nb.y) / 2 + (rand() - 0.5) * s0
    G[#G + 1] = { x = gx, y = gy, a = 0.42, s = s0 * 1.1 }
  end
  for _ = 1, 16 do
    local gx, gy = rand() * w, rand() * H2
    local a = (rand() < 0.5 and -1 or 1) * (0.16 + 0.28 * rand())
    G[#G + 1] = { x = gx, y = gy, a = a, s = s0 * (0.45 + 0.7 * rand()) }
  end
  local T = H2 * 2.5
  local function f(x, y)
    local v = -y / T
    for _, g in ipairs(G) do
      local dx, dy = x - g.x, y - g.y
      v = v + g.a * exp(-(dx * dx + dy * dy) / (2 * g.s * g.s))
    end
    return v
  end
  local function grad(x, y)
    local gx, gy = 0, -1 / T
    for _, g in ipairs(G) do
      local dx, dy, s2 = x - g.x, y - g.y, g.s * g.s
      local d2 = dx * dx + dy * dy
      if d2 <= 16 * s2 then
        local e = g.a * exp(-d2 / (2 * s2)) / s2
        gx, gy = gx - e * dx, gy - e * dy
      end
    end
    return gx, gy
  end
  return { f = f, grad = grad, w = w, h = h, s0 = s0 }
end

-- Character for a direction (tx, ty) in square units, y down.
local dir_chars = { [0] = "-", "\\", "|", "/" }
local function dir_char(tx, ty)
  local a = math.atan2(ty, tx)
  if a < 0 then a = a + pi end
  return dir_chars[floor(a / (pi / 4) + 0.5) % 4]
end

function M.descent(w, h)
  local n, S = w * h, loss_surface(w, h, 19)
  -- D scales with the wells (s0 = 18.4 at the mockup's 150x46) so the lines
  -- per cell stay the same in a small window, such as the picker's preview.
  local D, rip, HAIR, INDEX = 0.15 * 18.4 / S.s0, 0.03, 0.3, 0.55
  -- Level sets: a cell holds a line when a D-level falls between it and its
  -- right or lower neighbour (one cell thick, as in marching squares); every
  -- fifth level is an index contour. Two or more levels between neighbours
  -- means they crowd: drop them rather than mat. A slow ripple breathes.
  local F, DC, V = {}, {}, {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local i = y * w + x + 1
      local px, py = x + 0.5, y * 2 + 1
      F[i] = S.f(px, py)
      local gx, gy = S.grad(px, py)
      DC[i] = dir_char(-gy, gx) -- the level set runs across the gradient
    end
  end

  local rand, probes, nxt = rng_pm(5), {}, 0
  local function spawn(t0)
    local x, y, vx, vy = rand() * w, rand() * h * 2, 0, 0
    local pts, settled = {}, false
    for k = 0, 159 do
      local gx, gy = S.grad(x, y)
      vx, vy = 0.85 * vx - 120 * gx, 0.85 * vy - 120 * gy
      local sp = sqrt(vx * vx + vy * vy)
      if sp > 1 then vx, vy = vx / sp, vy / sp end
      x, y = x + vx, y + vy
      pts[#pts + 1] = { x, y, dir_char(vx, vy) }
      if k > 15 and sp < 0.03 then
        settled = true
        break
      end
    end
    probes[#probes + 1] = { pts = pts, t0 = t0, settled = settled }
  end

  return function(t, val, chr)
    t = t * MOCKUP_TIME
    for i = 1, n do val[i] = 0 end
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local i = y * w + x + 1
        V[i] = (F[i] + rip * sin((x + 0.5) * 0.07 + t * 0.2) * sin((y * 2 + 1) * 0.05 + t * 0.13)) / D
      end
    end
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local i = y * w + x + 1
        local a = floor(V[i])
        local lv, crowd = nil, false
        if x + 1 < w then
          local b = floor(V[i + 1])
          if a ~= b then
            if abs(a - b) > 1 then crowd = true else lv = max(a, b) end
          end
        end
        if not crowd and y + 1 < h then
          local b = floor(V[i + w])
          if a ~= b then
            if abs(a - b) > 1 then crowd = true else lv = max(a, b) end
          end
        end
        if lv and not crowd then
          val[i] = lv % 5 == 0 and INDEX or HAIR
          chr[i] = DC[i]
        end
      end
    end

    while nxt <= t do
      spawn(nxt)
      nxt = nxt + 0.5
    end
    while probes[1] and t - probes[1].t0 > 4.6 do table.remove(probes, 1) end -- kept until its last ripple fades

    for _, p in ipairs(probes) do
      local age = t - p.t0
      -- Ripples: a probe that settled in a well rings twice once fully grown.
      if p.settled and age > 0.9 then
        local e = p.pts[#p.pts]
        for k = 0, 1 do
          local ra = age - 0.9 - k * 0.5
          if ra > 0 and ra < 2.2 then
            local rad, rb = 1.2 + ra * 6, 0.75 * (1 - ra / 2.2)
            local a = 0
            while a < 2 * pi do
              local cx, cy = floor(e[1] + cos(a) * rad), floor((e[2] + sin(a) * rad) / 2)
              if cx >= 0 and cx < w and cy >= 0 and cy < h then
                local i = cy * w + cx + 1
                if val[i] < rb or chr[i] ~= "·" then
                  val[i] = max(rb, chr[i] == "·" and val[i] or 0)
                  chr[i] = "·"
                end
              end
              a = a + 0.8 / rad
            end
          end
        end
      end
      -- The probe itself: grows over 0.9 s, fades out from 1.2 s to 2.6 s.
      if age <= 2.6 then
        local grow, b = clamp(age / 0.9), 1 - clamp((age - 1.2) / 1.4)
        local m = floor(#p.pts * grow)
        for k = 0, m - 1 do
          local q = p.pts[k + 1]
          local cx, cy = floor(q[1]), floor(q[2] / 2)
          if cx >= 0 and cx < w and cy >= 0 and cy < h then
            local i = cy * w + cx + 1
            local bb = b * (0.45 + 0.55 * (k / max(1, m)))
            if not (val[i] > bb and not chr[i]) then
              val[i] = bb
              chr[i] = k == m - 1 and "•" or q[3]
            end
          end
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- spiral: four logarithmic arms, r = a * e^(b * th). Picked as sketch B of the
-- `Log Spiral Sketches` mockup (pitch 0.26, mockup speed 0.7).
--
-- Turning a logarithmic spiral gives the same picture as scaling it, so one
-- phase term does both: psi = n * (th - ln(rho) / b) - w * t. The bands are
-- cos(psi) sharpened, a slow wave runs outward along the arms, and the whole
-- thing dims toward the edge. Geometry is isotropic (a row counts two cell
-- widths) and rho is scaled so the window's corner sits at 1.41, as in the
-- mockup's 56 x 28 grid, so the arms keep their shape at any window size.
---------------------------------------------------------------------------

local SPIRAL = { arms = 4, pitch = 0.26, spin = 1.2, wave = 2.5, time = 0.7 / 0.4 }

local function smooth(a, b, x)
  local t = clamp((x - a) / (b - a))
  return t * t * (3 - 2 * t)
end

function M.spiral(w, h)
  local n = w * h
  local TH, S, ENV, DIM = {}, {}, {}, {}
  local unit = hypot(w / 2, h) / 1.414 -- cell widths per rho = 1
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local i = y * w + x + 1
      local px, py = x + 0.5 - w / 2, (y + 0.5 - h / 2) * 2
      local rho = hypot(px, py) / unit
      TH[i] = math.atan2(-py, px)
      S[i] = log(max(rho, 0.02)) / SPIRAL.pitch
      ENV[i] = smooth(0.107, 0.32, rho) * (1 - smooth(1.07, 1.57, rho))
      DIM[i] = 1 - 0.45 * smooth(0.29, 1.43, rho)
    end
  end
  local N = SPIRAL.arms
  return function(t, val)
    t = t * SPIRAL.time
    for i = 1, n do
      local env = ENV[i]
      if env <= 0 then
        val[i] = 0
      else
        local s = S[i]
        local band = (0.5 + 0.5 * cos(N * (TH[i] - s) - SPIRAL.spin * t)) ^ 2.4
        local wave = 0.75 + 0.25 * sin(0.9 * s - SPIRAL.wave * t)
        val[i] = band * env * wave * DIM[i]
      end
    end
  end
end

---------------------------------------------------------------------------
-- Second set: hilbert, rain, aurora, turing, attention, kmeans, matrix, warp,
-- life. Picked from the `Art Sketches` mockup (a 56 x 28 grid at speed 0.4,
-- which is the dashboard's default, so time needs no scaling) with the knob
-- values chosen there baked in. The mockup works in cell widths (a row counts
-- two), and each piece scales that to the window it is built for.
-- Pieces that keep state (turing, kmeans, life) step by the time between calls
-- and ignore a clock that runs backwards (the picker drives its own).
---------------------------------------------------------------------------

local TAU = 2 * pi

-- Seconds since the previous call: 0 on the first call or after a jump back,
-- capped so a stalled frame doesn't fast-forward a simulation.
local function clock()
  local last
  return function(t)
    local dt = last and (t - last) or 0
    last = t
    if dt < 0 then dt = 0 elseif dt > 0.25 then dt = 0.25 end
    return dt
  end
end

-- Put a level at isotropic coordinates (cell widths, origin at the centre,
-- y down and counted in half rows).
local function iso_put(val, w, h, X, Y, v, chr, ch)
  local ix, iy = floor(w / 2 + X), floor(h / 2 + Y / 2)
  if ix < 0 or ix >= w or iy < 0 or iy >= h then return end
  local i = iy * w + ix + 1
  if v > val[i] then
    val[i] = v
    if ch then chr[i] = ch end
  end
end

---------------------------------------------------------------------------
-- hilbert: order-4 curve drawn with box-drawing glyphs. A bright head runs
-- along it, it holds, fades and starts again. Steps are `sc` columns by
-- `sc / 2` rows, so the square stays square in a 2:1 cell.
---------------------------------------------------------------------------

local function hilbert_xy(side, d)
  local x, y, t, s = 0, 0, d, 1
  while s < side do
    local rx = floor(t / 2) % 2
    local ry = (t % 2 + rx) % 2
    if ry == 0 then
      if rx == 1 then x, y = s - 1 - x, s - 1 - y end
      x, y = y, x
    end
    x, y = x + s * rx, y + s * ry
    t, s = floor(t / 4), s * 2
  end
  return x, y
end

local HILBERT_GLYPH = { LR = "─", UD = "│", RD = "┌", LD = "┐", RU = "└", LU = "┘", L = "─", R = "─", U = "│", D = "│" }

function M.hilbert(w, h)
  local n, side = w * h, 16
  local steps = side - 1
  local sc = max(1, min((w - 2) / steps, 2 * (h - 2) / steps))
  local sr = sc / 2
  local x0, y0 = floor((w - steps * sc) / 2), floor((h - floor(steps * sr + 0.5)) / 2)

  local px, py = {}, {}
  for d = 0, side * side - 1 do
    local x, y = hilbert_xy(side, d)
    px[d + 1], py[d + 1] = x0 + floor(x * sc + 0.5), y0 + floor(y * sr + 0.5)
  end
  -- Consecutive points differ along one axis only, so walk cell by cell.
  local cx, cy = { px[1] }, { py[1] }
  for j = 2, #px do
    local sx = px[j] > px[j - 1] and 1 or (px[j] < px[j - 1] and -1 or 0)
    local sy = py[j] > py[j - 1] and 1 or (py[j] < py[j - 1] and -1 or 0)
    local x, y = px[j - 1], py[j - 1]
    while x ~= px[j] or y ~= py[j] do
      x, y = x + sx, y + sy
      cx[#cx + 1], cy[#cy + 1] = x, y
    end
  end
  local L = #cx
  local function side_of(j, k)
    if cx[k] > cx[j] then return "R" elseif cx[k] < cx[j] then return "L" elseif cy[k] < cy[j] then return "U" end
    return "D"
  end
  local order = { L = 1, R = 2, U = 3, D = 4 }
  local glyph = {}
  for j = 1, L do
    local s = {}
    if j > 1 then s[#s + 1] = side_of(j, j - 1) end
    if j < L then s[#s + 1] = side_of(j, j + 1) end
    table.sort(s, function(a, b) return order[a] < order[b] end)
    glyph[j] = HILBERT_GLYPH[table.concat(s)] or "─"
  end

  local CYC = 6
  return function(t, val, chr)
    for i = 1, n do val[i] = 0 end
    local ph = (t % CYC) / CYC
    local head = min(1, ph / 0.6) * L
    local fade = ph > 0.85 and 1 - (ph - 0.85) / 0.15 or 1
    for j = 1, L do
      if j - 1 > head then break end
      if cx[j] >= 0 and cx[j] < w and cy[j] >= 0 and cy[j] < h then
        local i = cy[j] * w + cx[j] + 1
        val[i] = (0.28 + 0.72 * exp(-(head - (j - 1)) / (0.1 * L))) * fade
        chr[i] = glyph[j]
      end
    end
  end
end

---------------------------------------------------------------------------
-- rain: a drop every 2 s (0.5 per second) at a seeded point, sending out
-- rings that add up where they cross. Stateless, a pure function of `t`.
---------------------------------------------------------------------------

function M.rain(w, h)
  local n, LIFE, SPEED, CAD = w * h, 6, 9, 2
  local sc = max(0.6, min(2, min(w, 2 * h) / 56)) -- rings grow with the window
  return function(t, val)
    local drops = {}
    for k = max(0, floor((t - LIFE) / CAD)), floor(t / CAD) do
      local age = t - k * CAD
      if age < LIFE then
        local r = rng((k * 2654435 + 17) % 4294967296)
        local dx = (r() - 0.5) * w * 0.93
        local dy = (r() - 0.5) * 2 * h * 0.79
        drops[#drops + 1] = { x = dx, y = dy, age = age, amp = (1 - age / LIFE) ^ 1.5 }
      end
    end
    for y = 0, h - 1 do
      local Y = (y + 0.5 - h / 2) * 2
      for x = 0, w - 1 do
        local X, s = x + 0.5 - w / 2, 0
        for d = 1, #drops do
          local q = drops[d]
          local dd = hypot(X - q.x, Y - q.y) / sc - SPEED * q.age
          if dd <= 3 and dd >= -11 then
            s = s + q.amp * (exp(-dd * dd / 2.25) + 0.55 * exp(-((dd + 4) / 1.6) ^ 2) + 0.3 * exp(-((dd + 8) / 1.8) ^ 2))
          end
        end
        val[y * w + x + 1] = clamp(s)
      end
    end
  end
end

---------------------------------------------------------------------------
-- aurora: three hanging curtains, bright along a swaying lower edge and fading
-- upward, with vertical rays that shimmer. Sway wavelengths scale with the
-- window width, vertical sizes with its height.
---------------------------------------------------------------------------

function M.aurora(w, h)
  local n, NC = w * h, 3
  local sy, sx = h / 28, 56 / w
  return function(t, val)
    for i = 1, n do val[i] = 0 end
    for x = 0, w - 1 do
      local xn = x * sx
      for j = 0, NC - 1 do
        local b = h * (0.42 + 0.07 * j) + sy * (3.2 * sin(0.13 * xn + 0.45 * t + 1.7 * j) + 1.8 * sin(0.31 * xn - 0.7 * t + j))
        local len = max(2.5, 6 + 3.5 * sin(0.09 * xn + 0.3 * t + 2 * j) + 2 * sin(0.4 * xn + 0.9 * t)) * sy
        local ray = 0.55 + 0.45 * sin(1.9 * x + 2.2 * sin(0.17 * x + 0.6 * t) + j * 3)
        local gain = (j == 0 and 1 or 0.8) * ray
        for y = 0, h - 1 do
          local dy = b - (y + 0.5)
          local p = dy >= 0 and exp(-dy / len) or exp(dy / 0.8)
          local i = y * w + x + 1
          val[i] = clamp(val[i] + p * gain * smooth(0, 3, y + 0.5))
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- turing: Gray-Scott reaction-diffusion, the "mitosis" preset (F 0.0367,
-- k 0.0649): spots grow and divide. The kernel is anisotropic (a row is twice
-- as tall as a cell is wide), so the spots come out round. Seeds scale with the
-- window's area, a new one drops in every 5 s, and a short warm-up lets the
-- first blobs grow before the first frame.
---------------------------------------------------------------------------

function M.turing(w, h)
  local n, F, KK = w * h, 0.0367, 0.0649
  local U, V, U2, V2 = {}, {}, {}, {}
  local dtf, acc, last_seed = clock(), 0, nil

  local function blob(r)
    local cx, cy = floor(r() * w), floor(r() * h)
    for dy = -1, 1 do
      for dx = -2, 2 do
        local i = ((cy + dy) % h) * w + (cx + dx) % w + 1
        U[i], V[i] = 0.5, 0.25
      end
    end
  end

  local function step()
    for y = 0, h - 1 do
      local ym, yp, yc = ((y - 1) % h) * w, ((y + 1) % h) * w, y * w
      for x = 0, w - 1 do
        local xm, xp = (x - 1) % w, (x + 1) % w
        local i = yc + x + 1
        local u, v = U[i], V[i]
        local lu = 0.25 * (U[yc + xm + 1] + U[yc + xp + 1] - 2 * u) + 0.0625 * (U[ym + x + 1] + U[yp + x + 1] - 2 * u)
        local lv = 0.25 * (V[yc + xm + 1] + V[yc + xp + 1] - 2 * v) + 0.0625 * (V[ym + x + 1] + V[yp + x + 1] - 2 * v)
        local uvv = u * v * v
        U2[i] = u + lu - uvv + F * (1 - u)
        V2[i] = v + 0.5 * lv + uvv - (F + KK) * v
      end
    end
    U, U2, V, V2 = U2, U, V2, V
  end

  for i = 1, n do U[i], V[i] = 1, 0 end
  local r = rng(4242 + 17)
  for _ = 1, max(4, floor(14 * n / 1568 + 0.5)) do blob(r) end
  for _ = 1, 400 do step() end

  return function(t, val)
    local dt = dtf(t)
    local sd = floor(t / 5)
    if last_seed ~= sd then
      if last_seed then blob(rng(sd * 31 + 7)) end
      last_seed = sd
    end
    acc = acc + dt * 450
    local k = min(20, floor(acc))
    acc = acc - floor(acc)
    for _ = 1, k do step() end
    for i = 1, n do val[i] = smooth(0.04, 0.33, V[i]) end
  end
end

---------------------------------------------------------------------------
-- attention: a causal softmax map of 14 x 14 tokens (rows are queries, columns
-- keys). A local band blends into a strided pattern, the first column is an
-- attention sink, sharpness 1. The grid is square (a block is s columns by
-- s / 2 rows) and centred; blocks leave a one-column gap when they are wide
-- enough.
---------------------------------------------------------------------------

function M.attention(w, h)
  local n, T, SHARP = w * h, 14, 1.0
  local bw = min(w, 2 * h) / T
  local bh = bw / 2
  local x0, y0 = (w - T * bw) / 2, (h - T * bh) / 2
  local tj, ti = {}, {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local fx, fy = (x + 0.5 - x0) / bw, (y + 0.5 - y0) / bh
      local j, i = floor(fx), floor(fy)
      local k = y * w + x + 1
      tj[k], ti[k] = 0, 0
      if j >= 0 and j < T and i >= 0 and i < T and j <= i and not (bw >= 3 and fx - j > 1 - 1 / bw) then
        tj[k], ti[k] = j + 1, i + 1
      end
    end
  end
  local V = {}
  for i = 1, T do V[i] = {} end
  return function(t, val)
    local w1 = 0.5 + 0.5 * sin(0.35 * t)
    for i = 0, T - 1 do
      local sc, mx = {}, -1e9
      for j = 0, i do
        local s = w1 * (-0.55 * (i - j)) + (1 - w1) * (-0.9 * (((i - j) % 4) ~= 0 and 1 or 0)) + (j == 0 and 1.5 or 0)
          + 0.9 * sin(1.31 * i + 0.77 * j + 0.8 * t + 1.9 * sin(0.5 * t + i))
        s = s * SHARP
        sc[j], mx = s, max(mx, s)
      end
      local sum, wt, wmax = 0, {}, 0
      for j = 0, i do
        wt[j] = exp(sc[j] - mx)
        sum = sum + wt[j]
      end
      for j = 0, i do
        wt[j] = wt[j] / sum
        wmax = max(wmax, wt[j])
      end
      for j = 0, i do V[i + 1][j + 1] = (wt[j] / wmax) ^ 0.8 end
    end
    for k = 1, n do
      val[k] = tj[k] > 0 and V[ti[k]][tj[k]] or 0
    end
  end
end

---------------------------------------------------------------------------
-- kmeans: points settle into 3 clusters while the centroids slide to their
-- means, with the Voronoi borders drawn as hairlines. Once converged it holds
-- for a moment and reseeds. Sizes scale with the window.
---------------------------------------------------------------------------

function M.kmeans(w, h)
  local n, KC = w * h, 3
  local k = min(w, 2 * h) / 56
  local npts = floor(96 * min(2, max(1, n / 1568)) + 0.5)
  local pts, cent, stable, hold, seed_idx = {}, {}, 0, 0, 0
  local ids, dtf = {}, clock()

  local function init()
    local r = rng(seed_idx * 7919 + 101)
    local cs = {}
    for b = 1, KC do cs[b] = { (r() - 0.5) * 38 * (w / 56), (r() - 0.5) * 34 * (2 * h / 56) } end
    pts, cent = {}, {}
    for i = 1, npts do
      local c = cs[(i - 1) % KC + 1]
      pts[i] = { c[1] + gauss(r) * 5.2 * k, c[2] + gauss(r) * 5.2 * k }
    end
    for b = 1, KC do
      local p = pts[floor(r() * #pts) + 1]
      cent[b] = { p[1], p[2] }
    end
    stable, hold = 0, 0
  end
  local function nearest(x, y)
    local best, bd = 1, math.huge
    for b = 1, KC do
      local dx, dy = x - cent[b][1], y - cent[b][2]
      local d = dx * dx + dy * dy
      if d < bd then best, bd = b, d end
    end
    return best
  end
  init()

  return function(t, val, chr)
    local dt = dtf(t)
    if dt > 0 then
      if hold > 0 then
        hold = hold - dt
        if hold <= 0 then
          seed_idx = seed_idx + 1
          init()
        end
      else
        local sx, sy, cn = {}, {}, {}
        for b = 1, KC do sx[b], sy[b], cn[b] = 0, 0, 0 end
        for i = 1, #pts do
          local a = nearest(pts[i][1], pts[i][2])
          sx[a], sy[a], cn[a] = sx[a] + pts[i][1], sy[a] + pts[i][2], cn[a] + 1
        end
        local mv, f = 0, min(1, dt * 1.6)
        for b = 1, KC do
          if cn[b] > 0 then
            local mx, my = (sx[b] / cn[b] - cent[b][1]) * f, (sy[b] / cn[b] - cent[b][2]) * f
            cent[b][1], cent[b][2] = cent[b][1] + mx, cent[b][2] + my
            mv = mv + hypot(mx, my)
          end
        end
        if mv / dt / KC < 0.5 * k then stable = stable + dt else stable = 0 end
        if stable > 1 then hold = 2.2 end
      end
    end
    for y = 0, h - 1 do
      local Y = (y + 0.5 - h / 2) * 2
      for x = 0, w - 1 do ids[y * w + x + 1] = nearest(x + 0.5 - w / 2, Y) end
    end
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local i = y * w + x + 1
        local r, d = x + 1 < w and ids[i + 1] ~= ids[i], y + 1 < h and ids[i + w] ~= ids[i]
        if r or d then
          val[i] = 0.42
          chr[i] = (r and d) and "+" or (r and "|" or "-")
        else
          val[i] = 0
        end
      end
    end
    for i = 1, #pts do iso_put(val, w, h, pts[i][1], pts[i][2], 0.5 + 0.08 * (nearest(pts[i][1], pts[i][2]) - 1), chr, "o") end
    for b = 1, KC do iso_put(val, w, h, cent[b][1], cent[b][2], 1, chr, "@") end
  end
end

---------------------------------------------------------------------------
-- matrix: falling streams, two per used column (every other column, half of
-- them at density 0.5), each with its own speed and length. A white head, a
-- fading tail and glyphs that change slowly while they fall. ASCII only, so
-- every glyph is one cell wide in any font.
---------------------------------------------------------------------------

local MATRIX_GLYPHS = "0123456789:=+*<>|/\\-_ZXKTSH"

function M.matrix(w, h)
  local n, DENS = w * h, 0.5
  local r, cols = rng(31), {}
  for x = 0, w - 1 do
    local c = { act = r(), s = {} }
    for q = 1, 2 do
      local sp = 5 + 9 * r()
      local off = r() * 80
      local len = 8 + 10 * r()
      c.s[q] = { sp = sp, off = off, len = len }
    end
    cols[x] = c
  end
  local G = #MATRIX_GLYPHS
  return function(t, val, chr)
    for i = 1, n do val[i] = 0 end
    for x = 0, w - 1, 2 do
      local c = cols[x]
      if c.act < DENS then
        for q = 1, 2 do
          local s = c.s[q]
          local head = (t * s.sp + s.off) % (h + s.len)
          for y = max(0, floor(head - s.len)), min(h - 1, floor(head)) do
            local d = head - y
            if d >= 0 and d < s.len then
              local v = d < 1 and 1 or (1 - d / s.len) ^ 1.4
              local i = y * w + x + 1
              if v > val[i] then
                val[i] = v
                local seed = floor(t * 2.2 + y * 0.31 + x * 0.17)
                local hs = (x * 374761393 + y * 668265263 + seed * 1013904223) % 4294967296
                hs = (hs * 1664525 + 1013904223) % 4294967296
                local g = floor(hs / 4294967296 * G) + 1
                chr[i] = MATRIX_GLYPHS:sub(g, g)
              end
            end
          end
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- warp: a perspective starfield flying at you. Stars brighten as they come
-- close and stretch into streaks (0.035 of the depth range) toward the edge.
-- Stateless; the star count grows with the window.
---------------------------------------------------------------------------

function M.warp(w, h)
  local n, STREAK = w * h, 0.035
  local r, stars = rng(77), {}
  for i = 1, floor(260 * min(3, max(1, n / 1568)) + 0.5) do
    local a = r() * TAU
    local rad = 0.1 + 0.9 * sqrt(r())
    stars[i] = { x = cos(a) * rad, y = sin(a) * rad, z = r() }
  end
  local f = 4 * hypot(w / 2, h) / hypot(28, 28)
  return function(t, val)
    for i = 1, n do val[i] = 0 end
    for i = 1, #stars do
      local s = stars[i]
      local z = (s.z - t * 0.25) % 1
      if z >= 0.04 then
        local zp, v = min(1, z + STREAK), (1 - z) ^ 1.2
        for m = 0, 8 do
          local zz = zp + (z - zp) * m / 8
          iso_put(val, w, h, s.x * f / zz, s.y * f / zz, v * (0.4 + 0.6 * m / 8))
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- life: Conway's Game of Life on a torus the size of the window, seeded at
-- density 0.16, twelve generations per second. Dead cells fade out over a few
-- generations. When it dies out or falls into a short cycle it fades and
-- reseeds.
---------------------------------------------------------------------------

function M.life(w, h)
  local n, DENS = w * h, 0.16
  local A, B, Lv = {}, {}, {}
  local acc, seed_idx, hist, dead = 0, 0, {}, 0
  local dtf = clock()

  local function gen(check)
    local alive, sig = 0, 0
    for y = 0, h - 1 do
      local ym, yp, yc = ((y - 1) % h) * w, ((y + 1) % h) * w, y * w
      for x = 0, w - 1 do
        local xm, xp = (x - 1) % w, (x + 1) % w
        local nb = A[ym + xm + 1] + A[ym + x + 1] + A[ym + xp + 1] + A[yc + xm + 1] + A[yc + xp + 1]
          + A[yp + xm + 1] + A[yp + x + 1] + A[yp + xp + 1]
        local i = yc + x + 1
        local nv = (nb == 3 or (A[i] == 1 and nb == 2)) and 1 or 0
        B[i] = nv
        if nv == 1 then
          alive = alive + 1
          sig = sig + i * i + i
        end
        Lv[i] = nv == 1 and 1 or Lv[i] * 0.8
      end
    end
    A, B = B, A
    if check then
      local seen = false
      for _, s in ipairs(hist) do
        if s == sig then seen = true break end
      end
      if alive < max(4, floor(n * 10 / 1568)) or seen then dead = 2.5 end
      hist[#hist + 1] = sig
      if #hist > 16 then table.remove(hist, 1) end
    end
  end

  local function init()
    local r = rng(seed_idx * 104729 + 5)
    for i = 1, n do
      A[i] = r() < DENS and 1 or 0
      Lv[i] = 0
    end
    hist, dead = {}, 0
    for _ = 1, 25 do gen(false) end
  end
  init()

  return function(t, val)
    local dt = dtf(t)
    if dt > 0 then
      if dead > 0 then
        dead = dead - dt
        local f = max(0, 1 - dt * 2)
        for i = 1, n do Lv[i] = Lv[i] * f end
        if dead <= 0 then
          seed_idx = seed_idx + 1
          init()
        end
      else
        acc = acc + dt * 12
        local k = min(6, floor(acc))
        acc = acc - floor(acc)
        for _ = 1, k do gen(true) end
      end
    end
    for i = 1, n do val[i] = (dead <= 0 and A[i] == 1) and 1 or Lv[i] end
  end
end

M.names = { "plasma", "torus", "orb", "rings", "flow", "terrain", "galaxy", "galaxies", "descent", "spiral", "hilbert", "rain", "aurora", "turing", "attention", "kmeans", "matrix", "warp", "life" }

return M
