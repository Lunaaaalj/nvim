-- Running terminals (last command, exit code) and Claude chats (live, then the
-- latest past sessions for this directory). Fed by `User TermsChanged`.
local U = require("header_art.static_util")

local STATE = { running = "acc", failed = "err", unseen = "warn", idle = "dim" }

local function terminals()
  local ok, T = pcall(require, "terminals")
  if not ok then return nil end
  return T
end

local function rows()
  local T = terminals()
  local list = {}
  if T then
    for _, t in ipairs(T.list() or {}) do list[#list + 1] = t.id end
    table.sort(list)
  end
  return T, list
end

local function chats()
  local ok, C = pcall(require, "claude_chats")
  if not ok then return nil, {}, {} end
  local okr, running = pcall(C.running)
  local oks, past = pcall(C.sessions, vim.fn.getcwd())
  return C, okr and running or {}, oks and past or {}
end

return {
  id = "sessions",
  title = "SESSIONS",
  on = { "User TermsChanged" },
  every = 60, -- the chats' ages
  available = function()
    local _, list = rows()
    local _, running, past = chats()
    return #list > 0 or #running > 0 or #past > 0
  end,
  render = function(w)
    local T, list = rows()
    local out = {}
    for _, id in ipairs(list) do
      local st = T.state(id)
      local info = T.info(id)
      local glyph = info.exit and info.exit ~= 0 and "● " or (st == "running" and "● " or "● ")
      out[#out + 1] = U.row({
        { (id < 100 and tostring(id) or "·") .. " ", "acc" }, { (id < 100 and "shell " or "repl "), "mid" }, { T.label(id) },
      }, { { glyph, STATE[st] or "dim" }, { T.detail(id) or "", "dim" } }, w, function() T.open(id) end)
    end
    local C, running, past = chats()
    local live = {}
    for _, r in ipairs(running) do
      live[r.id] = true
      out[#out + 1] = U.row({ { "◉ ", "acc" }, { "claude ", "mid" }, { r.title or "chat" } }, { { "live", "ok" } }, w, function() C.open({ session_id = r.id }) end)
    end
    local shown = 0
    for _, s in ipairs(past) do
      if not live[s.id] and shown < 2 then
        shown = shown + 1
        out[#out + 1] = U.row({ { "◌ ", "dim" }, { "claude ", "mid" }, { s.title or "chat" } }, { { U.age(s.mtime), "dim" } }, w, function() C.open({ session_id = s.id, title = s.title }) end)
      end
    end
    return out
  end,
}
