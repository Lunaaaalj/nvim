-- Helpers shared by the glyph pieces (pieces.lua's third set and hud.lua):
-- a stateless hash, a slope -> line-glyph mapper and a small canvas over the
-- renderer's `val` / `chr` arrays.

local bit = require("bit")
local floor = math.floor

local M = {}

function M.clamp(v) return v < 0 and 0 or (v > 1 and 1 or v) end

function M.smooth(a, b, x)
  local t = M.clamp((x - a) / (b - a))
  return t * t * (3 - 2 * t)
end

-- 32-bit multiply (Math.imul): a * b mod 2^32 without losing bits to doubles.
local function imul(a, b)
  a = bit.tobit(a)
  local bl, bh = b % 65536, floor(b / 65536) % 65536
  return bit.tobit(a * bl + bit.lshift(bit.tobit(a * bh), 16))
end

-- Stateless integer hash -> 0..1, so a piece can flicker without keeping state
-- (and still works when the picker runs time backwards).
function M.hash(a, b, c)
  local hh = bit.bxor(imul(floor(a), 374761393), imul(floor(b), 668265263), imul(floor(c) + 0x9e37, 2246822519))
  hh = imul(bit.bxor(hh, bit.rshift(hh, 13)), 1274126177)
  hh = bit.bxor(hh, bit.rshift(hh, 16))
  return (hh % 4294967296) / 4294967296
end

-- Direction of a segment (dx columns, dy rows) -> one line glyph. A row is two
-- columns tall, so dy counts double.
function M.slope_char(dx, dy)
  local ax, ay = math.abs(dx), math.abs(dy) * 2
  if ax > ay * 2.4 then return "─" end
  if ay > ax * 2.4 then return "│" end
  return (dx * dy > 0) and "\\" or "/"
end

-- UTF-8 string -> list of characters (ASCII fast path).
function M.chars(s)
  local t = {}
  if not s:find("[\128-\255]") then
    for i = 1, #s do t[i] = s:sub(i, i) end
  else
    for c in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do t[#t + 1] = c end
  end
  return t
end

-- Drawing helpers over val/chr: `put` keeps the brighter level, `set` paints
-- over (for opaque shapes: towers, slabs, text). A nil glyph means "use the
-- charset". `begin` zeroes `val` for a new frame (`chr` is cleared by the
-- renderer).
function M.canvas(w, h)
  local C, val, chr = {}, nil, nil
  function C.begin(v, c)
    val, chr = v, c
    for i = 1, w * h do v[i] = 0 end
  end
  function C.put(x, y, v, ch)
    x, y = floor(x + 0.5), floor(y + 0.5)
    if x < 0 or y < 0 or x >= w or y >= h then return end
    local i = y * w + x + 1
    if v > val[i] then
      val[i] = v
      chr[i] = ch or false
    end
  end
  function C.set(x, y, v, ch)
    x, y = floor(x + 0.5), floor(y + 0.5)
    if x < 0 or y < 0 or x >= w or y >= h then return end
    local i = y * w + x + 1
    val[i] = v
    chr[i] = ch or false
  end
  function C.text(x, y, s, v)
    for k = 1, #s do
      local c = s:sub(k, k)
      if c ~= " " then C.set(x + k - 1, y, v, c) end
    end
  end
  return C
end

return M
