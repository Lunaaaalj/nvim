-- Helpers for the static HUD's modules (header_art/static_mods/*.lua).
--
-- A module's `render(w)` returns a list of lines; a line is
-- `{ s = { { text, class }, ... }, act = fn? }`. `class` is a space-separated
-- list of tokens ("b", "dim", "mid", "acc", "ok", "warn", "err", "faint",
-- "key"); static.lua maps it to a highlight group derived from the scheme.
-- `act` runs on <CR> while the cursor is on the line.

local M = {}

local sw = vim.api.nvim_strwidth

---@param segs table[]
function M.width(segs)
  local n = 0
  for _, s in ipairs(segs) do n = n + sw(s[1]) end
  return n
end

--- Truncate to `w` cells, ending in an ellipsis when something was cut.
function M.fit(segs, w)
  local out, n = {}, 0
  for _, s in ipairs(segs) do
    local cw = sw(s[1])
    if n + cw <= w then
      out[#out + 1] = s
      n = n + cw
    else
      local room = w - n
      if room > 0 then
        local text, acc = "", 0
        for _, ch in ipairs(vim.fn.split(s[1], "\\zs")) do
          local c = sw(ch)
          if acc + c > room - 1 then break end
          text, acc = text .. ch, acc + c
        end
        out[#out + 1] = { text .. "…", s[2] }
      end
      break
    end
  end
  return out
end

--- Pad with spaces to exactly `w` cells (truncating first if longer).
function M.pad(segs, w)
  local out = M.fit(segs, w)
  local n = M.width(out)
  if n < w then out[#out + 1] = { string.rep(" ", w - n), "" } end
  return out
end

--- `left` and `right` (segment lists) on one line `w` cells wide; the left side
--- gives way when they collide.
function M.row(left, right, w, act)
  right = right or {}
  local rw = M.width(right)
  local l = M.fit(left, math.max(0, w - rw - (rw > 0 and 1 or 0)))
  local s = vim.list_extend({}, l)
  s[#s + 1] = { string.rep(" ", math.max(0, w - M.width(l) - rw)), "" }
  vim.list_extend(s, right)
  return { s = s, act = act }
end

function M.line(segs, act) return { s = segs, act = act } end

local BARS = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
function M.spark(list)
  local mx = 1
  for _, v in ipairs(list) do mx = math.max(mx, v) end
  local out = {}
  for i, v in ipairs(list) do out[i] = BARS[math.min(8, math.floor(v / mx * 7.999) + 1)] end
  return table.concat(out)
end

--- Seconds since `t` (epoch) as "now", "12m", "5h", "3d".
function M.age(t)
  local d = os.time() - t
  if d < 60 then return "now" end
  if d < 3600 then return math.floor(d / 60) .. "m" end
  if d < 86400 then return math.floor(d / 3600) .. "h" end
  return math.floor(d / 86400) .. "d"
end

--- Open a file in the current window (the dashboard's), at an optional line.
function M.open_file(path, lnum)
  vim.cmd.edit(vim.fn.fnameescape(path))
  if lnum then pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 }) end
end

--- Shorten a path for display: ~ for home, and only the last `n` components.
function M.short_path(path, n)
  local p = vim.fn.fnamemodify(path, ":~")
  local parts = vim.split(p, "/", { plain = true })
  if #parts <= (n or 2) then return p end
  return table.concat(vim.list_slice(parts, #parts - (n or 2) + 1), "/")
end

return M
