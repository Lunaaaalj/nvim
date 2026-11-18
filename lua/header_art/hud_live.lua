-- hud_live: HUD modules that become real sessions. When the dashboard is the
-- only window (no neo-tree, splits or panels), `0` turns the terminal panel
-- into a real shell in the cwd and `1` turns the event log into a Claude chat.
--
-- How: a borderless float pinned (relative = "win") over the module's area,
-- while hud.lua keeps drawing the frame and title around it. The sessions are
-- ordinary buffers owned elsewhere: the shell is a lua/terminals terminal
-- (spawned windowless, so <leader>tt and the neo-tree Terminals tab know it),
-- the chat a lua/claude_chats buffer. Leaving the dashboard closes the floats
-- but the sessions keep running; `0` / `1` again shows the same ones.
--
-- Keys inside a float: <C-q> (terminal or normal mode) or q (normal) close it, so
-- the module goes back to its fake terminal / event log (the session keeps
-- running; `0` / `1` shows it again); O (normal mode) pops the session out
-- into the dashboard's window. A session that ends (`exit`, Claude's /exit)
-- also gives the module back. The chat grows over the right of the HUD while
-- it has focus and shrinks back into the log when it loses it.
--
-- Colours: both sessions start with a monochrome 16-colour palette built
-- from the scheme (`b:terminal_color_N`, read at TermOpen), the HUD's own
-- dim -> Normal fg ramp, and Claude runs with its ANSI-only theme
-- (`--settings {"theme":"dark-ansi"}`) so it draws with that palette instead
-- of its RGB colours. Programs that print 24-bit colour bypass the palette.
--
-- hud.lua publishes the module rects on each build (set_layout) and asks
-- `available()` / `is_open()` per frame to draw the badges and titles.

local api = vim.api

local M = {}

-- rects: { shell = r, log = r, claude_big = r }, inclusive cells of the
-- dashboard's text area; wins: id -> float window; expanded: chat is focused
local S = { rects = nil, wins = {}, shell_id = nil, claude_buf = nil, expanded = false }

-- The HUD's palette for a terminal: every ANSI colour becomes a step on the
-- dim -> Normal fg ramp (brights brighter), so output reads like the HUD.
function M.palette()
  local C = require("defaults.colors")
  local fg = C.fg("Normal") or 0xc8c8c8
  local bg = C.bg()
  local function at(k) return C.hex(C.blend(fg, bg, k)) end
  return {
    at(0.22), at(0.78), at(0.62), at(0.72), at(0.56), at(0.66), at(0.6), at(0.84), -- 0-7
    at(0.42), at(0.95), at(0.82), at(0.9), at(0.76), at(0.86), at(0.8), C.hex(fg), -- 8-15
  }
end

local function valid_win(w) return w ~= nil and api.nvim_win_is_valid(w) end
local function valid_buf(b) return b ~= nil and api.nvim_buf_is_valid(b) end

local function dashboard_win()
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.bo[api.nvim_win_get_buf(w)].filetype == "snacks_dashboard" and api.nvim_win_get_config(w).relative == "" then
      return w
    end
  end
end

--- The dashboard window when it is the only regular window, else nil.
function M.alone()
  local dwin, n = nil, 0
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_config(w).relative == "" then
      n = n + 1
      if vim.bo[api.nvim_win_get_buf(w)].filetype == "snacks_dashboard" then dwin = w end
    end
  end
  return n == 1 and dwin or nil
end

--- Badges and keys are live: the HUD has laid out its modules and the
--- dashboard is alone.
function M.available() return S.rects ~= nil and M.alone() ~= nil end

function M.is_open(id) return valid_win(S.wins[id]) end
function M.is_focused(id) return valid_win(S.wins[id]) and api.nvim_get_current_win() == S.wins[id] end
function M.expanded() return S.expanded and M.is_open("claude") end
function M.shell_id() return S.shell_id end

local function rect_for(id)
  if not S.rects then return nil end
  if id == "shell" then return S.rects.shell end
  return (S.expanded and S.rects.claude_big) or S.rects.log
end

local function geometry(id, dwin)
  local r = rect_for(id)
  if not r or r.x1 - r.x0 < 8 or r.y1 - r.y0 < 2 then return nil end
  local textoff = vim.fn.getwininfo(dwin)[1].textoff
  return {
    relative = "win", win = dwin,
    row = r.y0, col = r.x0 + textoff,
    width = r.x1 - r.x0 + 1, height = r.y1 - r.y0 + 1,
  }
end

local function place(id)
  local w, dwin = S.wins[id], dashboard_win()
  if not (valid_win(w) and dwin) then return end
  local g = geometry(id, dwin)
  if g then api.nvim_win_set_config(w, g) end
end

local function close(id)
  if valid_win(S.wins[id]) then pcall(api.nvim_win_close, S.wins[id], true) end
  S.wins[id] = nil
  if id == "claude" then S.expanded = false end
end

function M.close_all()
  for id in pairs(S.wins) do close(id) end
end

--- Called by hud.lua whenever it rebuilds for the real dashboard (not the
--- picker preview): new rects, so open floats follow the modules.
function M.set_layout(rects)
  S.rects = rects
  if next(S.wins) then vim.schedule(function()
    for id in pairs(S.wins) do place(id) end
  end) end
end

-- Close the float: the module shows its fake terminal / log again and the
-- session keeps running in the background.
local function hide(id)
  vim.cmd("stopinsert")
  close(id)
  local dwin = dashboard_win()
  if dwin then api.nvim_set_current_win(dwin) end
end

-- Move the session into the dashboard's window (the dashboard goes away).
local function pop_out(id)
  local w, dwin = S.wins[id], dashboard_win()
  if not (valid_win(w) and dwin) then return end
  local buf = api.nvim_win_get_buf(w)
  close(id)
  api.nvim_win_set_buf(dwin, buf)
  api.nvim_set_current_win(dwin)
  vim.cmd("startinsert")
end

-- Buffer-local keys while the session sits in a HUD float; they only act in
-- that float, so a popped-out session keeps the normal meaning of q / O.
local function map_keys(buf, id)
  if vim.b[buf].hud_live_keys then return end
  vim.b[buf].hud_live_keys = true
  local function in_float() return M.is_focused(id) end
  vim.keymap.set({ "t", "n" }, "<C-q>", function()
    if in_float() then hide(id) else api.nvim_feedkeys(vim.keycode("<C-q>"), "n", false) end
  end, { buffer = buf, desc = "HUD: close (back to the module)" })
  vim.keymap.set("n", "q", function()
    if in_float() then hide(id) else api.nvim_feedkeys("q", "n", false) end
  end, { buffer = buf, desc = "HUD: close (back to the module)" })
  vim.keymap.set("n", "O", function()
    if in_float() then pop_out(id) else api.nvim_feedkeys("O", "n", false) end
  end, { buffer = buf, desc = "HUD: pop the session out" })
end

local function open_float(id, buf, dwin)
  local g = geometry(id, dwin)
  if not g then return nil end
  g.style, g.border, g.zindex, g.focusable = "minimal", "none", 45, true
  local w = api.nvim_open_win(buf, true, g)
  -- blend into the HUD: no float tint, no winblend (the global 10 would
  -- shade it), no cursorline
  vim.wo[w].winhighlight = "Normal:Normal,NormalNC:Normal,NormalFloat:Normal,FloatBorder:Normal"
  vim.wo[w].winblend = 0
  vim.w[w].no_cursorline = true
  vim.w[w].hud_live = id
  S.wins[id] = w
  return w
end

-- Show (or focus) a module's session. Returns false when it isn't possible.
local function show(id)
  local dwin = M.alone()
  if not dwin or not S.rects then
    vim.notify("HUD modules are live only when the dashboard is the only window", vim.log.levels.INFO)
    return false
  end
  if valid_win(S.wins[id]) then
    api.nvim_set_current_win(S.wins[id])
    vim.cmd("startinsert")
    return true
  end
  if id == "shell" then
    local terms = require("terminals")
    local t = S.shell_id and terms.get(S.shell_id)
    local buf = t and t.bufnr --[[@as integer?]]
    local alive = t and t.job_id and vim.fn.jobwait({ t.job_id }, 0)[1] == -1
    if not (valid_buf(buf) and alive) then
      local fresh = api.nvim_create_buf(false, false)
      for i, c in ipairs(M.palette()) do vim.b[fresh]["terminal_color_" .. (i - 1)] = c end
      S.shell_id, buf = terms.spawn({ dir = vim.fn.getcwd(), buf = fresh })
      if not buf then
        pcall(api.nvim_buf_delete, fresh, { force = true })
        return false
      end
    end
    if not open_float("shell", buf, dwin) then return false end
    map_keys(buf, "shell")
    vim.cmd("startinsert")
  else
    S.expanded = true -- it opens focused
    if valid_buf(S.claude_buf) then
      if not open_float("claude", S.claude_buf, dwin) then S.expanded = false; return false end
    else
      local scratch = api.nvim_create_buf(false, true)
      vim.bo[scratch].bufhidden = "wipe"
      local w = open_float("claude", scratch, dwin)
      if not w then S.expanded = false; return false end
      S.claude_buf = require("claude_chats").open({
        win = w,
        colors = M.palette(),
        settings = { theme = vim.o.background == "light" and "light-ansi" or "dark-ansi" },
      })
    end
    map_keys(S.claude_buf, "claude")
    vim.cmd("startinsert")
  end
  return true
end

function M.focus(id)
  -- the log becomes the chat; any other id is the shell
  return show(id == "claude" and "claude" or "shell")
end

-- The chat grows while focused and shrinks back into the log without it.
local function sync_expansion()
  if not M.is_open("claude") then return end
  local want = api.nvim_get_current_win() == S.wins.claude
  if want ~= S.expanded then
    S.expanded = want
    place("claude")
  end
end

function M.setup()
  local grp = api.nvim_create_augroup("HeaderArtHudLive", { clear = true })
  api.nvim_create_autocmd("WinEnter", { group = grp, callback = function() vim.schedule(sync_expansion) end })
  -- The floats only exist over a lone dashboard: close them when it goes
  -- away or another regular window appears. The sessions keep running.
  api.nvim_create_autocmd({ "WinNew", "WinClosed", "BufWinLeave", "TabEnter" }, {
    group = grp,
    callback = function()
      vim.schedule(function()
        if next(S.wins) and not M.alone() then M.close_all() end
        for id, w in pairs(S.wins) do
          if not valid_win(w) then S.wins[id] = nil end
        end
      end)
    end,
  })
  -- A session that ends (claude_chats and toggleterm delete the buffer on
  -- exit) gives its module back: forget it, close the float if still there.
  api.nvim_create_autocmd({ "BufDelete", "TermClose" }, {
    group = grp,
    callback = function(ev)
      for _, id in ipairs({ "shell", "claude" }) do
        local w = S.wins[id]
        local shows = valid_win(w) and api.nvim_win_get_buf(w) == ev.buf
        local owned = (id == "claude" and ev.buf == S.claude_buf)
        if shows or owned then
          if id == "claude" then S.claude_buf = nil else S.shell_id = nil end
          vim.schedule(function()
            if valid_win(S.wins[id]) and api.nvim_win_get_buf(S.wins[id]) == ev.buf then hide(id) end
            S.wins[id] = valid_win(S.wins[id]) and S.wins[id] or nil
            if id == "claude" and not S.wins.claude then S.expanded = false end
          end)
        end
      end
    end,
  })
end

return M
