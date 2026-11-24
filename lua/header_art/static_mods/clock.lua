-- Hero band: a seven-segment clock (unlit segments stay faintly visible, like
-- the HUD panel's), the date, and a "needs you" strip answering "what wants me
-- before I touch a key". Minute resolution; the live dot is why it ticks once a
-- second (`live_dot = false` makes it a once-a-minute field, `clock.seconds`
-- adds a small :SS field and a sweep bar).
local U = require("header_art.static_util")

local M = {
  id = "clock",
  bare = true,
  noflash = true,
}

-- a top, b upper right, c lower right, d bottom, e lower left, f upper left, g middle
-- (same table as hud_core.lua's panel)
local SEG = {
  ["0"] = "abcdef", ["1"] = "bc", ["2"] = "abged", ["3"] = "abgcd", ["4"] = "fgbc",
  ["5"] = "afgcd", ["6"] = "afgedc", ["7"] = "abc", ["8"] = "abcdefg", ["9"] = "abfgcd",
}

local function opts()
  local o = require("header_art.static").opts
  return o.live_dot, (o.clock or {}).seconds
end

function M.every()
  local live, secs = opts()
  return (live or secs) and 1 or 60
end

--- Five rows of segments for "HH:MM".
local function digits(txt, colon_on)
  local rows = { {}, {}, {}, {}, {} }
  local function add(r, text, cls) rows[r][#rows[r] + 1] = { text, cls } end
  for i = 1, #txt do
    local ch = txt:sub(i, i)
    if i > 1 then for r = 1, 5 do add(r, " ", "") end end
    if ch == ":" then
      for r = 1, 5 do
        if r == 2 or r == 4 then add(r, "●", colon_on and "acc" or "faint") else add(r, " ", "") end
      end
    else
      local on = SEG[ch]
      local function k(seg) return on:find(seg, 1, true) and "b" or "faint" end
      add(1, " ", ""); add(1, "━━━", k("a")); add(1, " ", "")
      add(2, "┃", k("f")); add(2, "   ", ""); add(2, "┃", k("b"))
      add(3, " ", ""); add(3, "━━━", k("g")); add(3, " ", "")
      add(4, "┃", k("e")); add(4, "   ", ""); add(4, "┃", k("c"))
      add(5, " ", ""); add(5, "━━━", k("d")); add(5, " ", "")
    end
  end
  return rows
end

--- What needs attention, as segments. Each source is optional: a missing module
--- or an unauthenticated gh just contributes nothing.
function M.attention()
  local items = {}
  local ok, data = pcall(function() return require("defaults.dashboard_data").stats() end)
  if ok and type(data) == "table" then
    local n = type(data.reviews) == "table" and data.reviews.count or 0
    if n and n > 0 then items[#items + 1] = { { "◆ ", "acc" }, { n .. (n == 1 and " review" or " reviews"), "" } } end
    local failing = data.failing or 0
    if failing > 0 then items[#items + 1] = { { "● ", "err" }, { failing .. " failing run" .. (failing == 1 and "" or "s"), "" } } end
  end
  local okt, terms = pcall(function() return require("terminals") end)
  if okt then
    for _, t in ipairs(terms.list() or {}) do
      local info = terms.info(t.id)
      if info.kind == "shell" and info.exit and info.exit ~= 0 then
        items[#items + 1] = { { "● ", "err" }, { "shell " .. t.id .. " exit " .. info.exit, "" } }
      end
    end
  end
  local line = { { "needs you  ", "dim" } }
  if #items == 0 then
    line[#line + 1] = { "nothing right now", "mid" }
    return line
  end
  for i, it in ipairs(items) do
    if i > 1 then line[#line + 1] = { "   ", "" } end
    vim.list_extend(line, it)
  end
  return line
end

function M.render(w)
  local live, secs = opts()
  local now = os.time()
  local sec = tonumber(os.date("%S", now))
  local colon = not secs or sec % 2 == 0
  local rows = digits(os.date("%H:%M", now), colon)
  local cw = U.width(rows[1])
  if secs then
    rows[5][#rows[5] + 1] = { "  :" .. os.date("%S", now), "dim" }
    cw = cw + 5
  end
  local iw = w - cw - 4
  local info = {
    { { os.date("%A %d %B"):upper(), "b" } },
    { { ("week %s · day %d"):format(os.date("%V", now), tonumber(os.date("%j", now))), "dim" } },
    {},
    M.attention(),
  }
  if secs then
    local f = math.floor(sec / 60 * 30 + 0.5)
    info[5] = { { string.rep("━", f), "acc" }, { "╺", "acc" }, { string.rep("─", 30 - f), "dim" } }
  end
  local out = {}
  for r = 1, 5 do
    local left = vim.list_extend({}, U.pad(rows[r], cw))
    left[#left + 1] = { "    ", "" }
    vim.list_extend(left, U.fit(info[r] or {}, iw))
    local right = {}
    if r == 1 and live then right = { { "● live", sec % 2 == 0 and "ok" or "dim" } } end
    out[r] = U.row(left, right, w)
  end
  return out
end

return M
