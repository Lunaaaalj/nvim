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

M.names = { "plasma", "torus", "orb", "rings", "flow", "terrain", "galaxy", "galaxies", "descent" }

return M
