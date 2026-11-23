-- hud_live: HUD modules that become real tools. When the dashboard is the
-- only window (no neo-tree, splits or panels), the number keys bring them to
-- life:
--
--   0  terminal panel  -> a real shell in the cwd (a lua/terminals shell)
--   1  event log       -> a Claude chat (lua/claude_chats); grows over the
--                         right of the HUD while it has focus
--   2  process map     -> the buffer cells, walked with the real cursor;
--                         <CR> opens the buffer, d deletes it
--   3  hex dump        -> peek: the last edited buffer itself, over the zone
--   4  brackets title  -> lazygit over the whole HUD (framed by it)
--   5  spectrum        -> the Apple Music player (lua/music)
--   6  orrery / LSP    -> LSP menu: info, log, restart a client
--   7  DIAG readout    -> diagnostics (Telescope)
--
-- How: a borderless float pinned (relative = "win") over the module's area,
-- while hud.lua keeps drawing the frame and title around it. The sessions are
-- ordinary buffers owned elsewhere, so leaving the dashboard closes the floats
-- but they keep running; the same key shows them again.
--
-- Keys inside a float: <C-q> (terminal or normal mode) or q (normal) close it,
-- so the module goes back to its HUD drawing; O (normal mode) pops the
-- session / buffer out into the dashboard's window. A session that ends
-- (`exit`, Claude's /exit, lazygit's q) also gives the module back.
--
-- Colours: the terminals (shell, chat, lazygit) start with a monochrome
-- 16-colour palette built from the scheme (`b:terminal_color_N`, read at
-- TermOpen), the HUD's own dim -> Normal fg ramp, and Claude runs with its
-- ANSI-only theme so it draws with that palette. 24-bit colour bypasses it.
--
-- hud.lua publishes the module rects on each build (set_layout) and asks
-- `available()` / `is_open()` per frame to draw the badges and titles.

local api = vim.api

local M = {}

-- rects: { shell, log, claude_big, proc, hex, full } (inclusive cells of the
-- dashboard's text area); wins: id -> float window; expanded: the chat has
-- focus; procs: the buffer map's list + selection
local S = {
  rects = nil, wins = {}, shell_id = nil, claude_buf = nil, git_buf = nil, expanded = false,
  procs = { list = {}, sel = nil, buf = nil }, peek_buf = nil,
}

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
function M.rects() return S.rects end

--- The buffer map's selection for the HUD's label: "name [+]", or nil.
function M.proc_label()
  local b = S.procs.sel
  if not (b and M.is_open("procs")) then return nil end
  local name = b.name ~= "" and vim.fn.fnamemodify(b.name, ":t") or ("[No Name " .. b.buf .. "]")
  return name .. (vim.bo[b.buf].modified and " [+]" or "")
end

--- The peeked buffer's name for the hex dump's header, or nil.
function M.peek_label()
  if not (M.is_open("peek") and valid_buf(S.peek_buf)) then return nil end
  return vim.fn.fnamemodify(api.nvim_buf_get_name(S.peek_buf), ":t")
end

local function rect_for(id)
  local R = S.rects
  if not R then return nil end
  if id == "shell" then return R.shell end
  if id == "claude" then return (S.expanded and R.claude_big) or R.log end
  if id == "peek" then return R.hex end
  if id == "git" then return R.full end
  if id == "procs" and R.proc then
    local n = math.min(#S.procs.list, 64)
    return { x0 = R.proc.x0, y0 = R.proc.y0, x1 = R.proc.x0 + math.min(16, n) - 1, y1 = R.proc.y0 + math.ceil(n / 16) - 1 }
  end
end

local MIN = { procs = { 0, 0 } } -- smallest rect (cols - 1, rows - 1); others 8 x 2

local function geometry(id, dwin)
  local r = rect_for(id)
  local m = MIN[id] or { 8, 2 }
  if not r or r.x1 - r.x0 < m[1] or r.y1 - r.y0 < m[2] then return nil end
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

-- Keys set on a real file buffer while it is peeked (removed on close).
local PEEK_KEYS = { { { "n" }, "<C-q>" }, { { "n" }, "q" }, { { "n" }, "O" } }

local function close(id)
  if valid_win(S.wins[id]) then pcall(api.nvim_win_close, S.wins[id], true) end
  S.wins[id] = nil
  if id == "claude" then S.expanded = false end
  if id == "peek" and valid_buf(S.peek_buf) then
    for _, k in ipairs(PEEK_KEYS) do pcall(vim.keymap.del, k[1], k[2], { buffer = S.peek_buf }) end
    S.peek_buf = nil
  end
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

-- Close the float: the module shows its HUD drawing again; a session keeps
-- running in the background.
local function hide(id)
  vim.cmd("stopinsert")
  close(id)
  local dwin = dashboard_win()
  if dwin then api.nvim_set_current_win(dwin) end
end

-- Show `buf` in the dashboard's window (the dashboard goes away).
local function take_over(buf, cursor)
  local dwin = dashboard_win()
  if not dwin then return end
  api.nvim_win_set_buf(dwin, buf)
  api.nvim_set_current_win(dwin)
  if cursor then pcall(api.nvim_win_set_cursor, dwin, cursor) end
  if vim.bo[buf].buftype == "terminal" then vim.cmd("startinsert") end
end

local function pop_out(id)
  local w = S.wins[id]
  if not valid_win(w) then return end
  local buf, cursor = api.nvim_win_get_buf(w), api.nvim_win_get_cursor(w)
  close(id)
  take_over(buf, cursor)
end

-- Buffer-local keys while a session sits in a HUD float; they only act in
-- that float, so a popped-out session keeps the normal meaning of q / O.
local function map_keys(buf, id, opts)
  opts = opts or {}
  if not opts.temporary then
    if vim.b[buf].hud_live_keys then return end
    vim.b[buf].hud_live_keys = true
  end
  local function in_float() return M.is_focused(id) end
  local function key(modes, lhs, fn, desc)
    vim.keymap.set(modes, lhs, function()
      if in_float() then fn() else api.nvim_feedkeys(vim.keycode(lhs), "n", false) end
    end, { buffer = buf, desc = desc })
  end
  key(opts.temporary and { "n" } or { "t", "n" }, "<C-q>", function() hide(id) end, "HUD: close (back to the module)")
  key({ "n" }, "q", function() hide(id) end, "HUD: close (back to the module)")
  key({ "n" }, "O", function() pop_out(id) end, "HUD: pop out into the window")
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

-- A fresh buffer carrying the HUD palette, for a terminal job.
local function palette_buf()
  local buf = api.nvim_create_buf(false, false)
  for i, c in ipairs(M.palette()) do vim.b[buf]["terminal_color_" .. (i - 1)] = c end
  return buf
end

local function job_alive(job) return job and vim.fn.jobwait({ job }, 0)[1] == -1 end

local function gate()
  local dwin = M.alone()
  if not dwin or not S.rects then
    vim.notify("HUD modules are live only when the dashboard is the only window", vim.log.levels.INFO)
    return nil
  end
  return dwin
end

-- Focus an already open float; true when there was one.
local function refocus(id, insert)
  if not valid_win(S.wins[id]) then return false end
  api.nvim_set_current_win(S.wins[id])
  if insert then vim.cmd("startinsert") end
  return true
end

---------------------------------------------------------------------------
-- 0 shell, 1 claude
---------------------------------------------------------------------------

local function open_shell(dwin)
  local terms = require("terminals")
  local t = S.shell_id and terms.get(S.shell_id)
  local buf = t and t.bufnr --[[@as integer?]]
  if not (valid_buf(buf) and job_alive(t and t.job_id)) then
    local fresh = palette_buf()
    S.shell_id, buf = terms.spawn({ dir = vim.fn.getcwd(), buf = fresh })
    if not buf then
      pcall(api.nvim_buf_delete, fresh, { force = true })
      return false
    end
  end
  if not open_float("shell", buf, dwin) then return false end
  map_keys(buf, "shell")
  vim.cmd("startinsert")
  return true
end

local function open_claude(dwin)
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
  return true
end

---------------------------------------------------------------------------
-- 2 buffer map
---------------------------------------------------------------------------

local function list_buffers()
  local out = {}
  for _, b in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    out[#out + 1] = { buf = b.bufnr, name = b.name }
  end
  return out
end

local procs_ns = api.nvim_create_namespace("hud_live_procs")

local function render_procs()
  local P, buf = S.procs, S.procs.buf
  if not valid_buf(buf) then return end
  local steps = require("header_art").options().steps or 8
  local lines = {}
  for i, b in ipairs(P.list) do
    if i > 64 then break end
    local r = math.floor((i - 1) / 16) + 1
    lines[r] = (lines[r] or "") .. (vim.bo[b.buf].modified and "█" or "▓")
  end
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, procs_ns, 0, -1)
  for i, b in ipairs(P.list) do
    if i > 64 then break end
    local r, c = math.floor((i - 1) / 16), (i - 1) % 16
    local hl = (P.sel == b) and ("HeaderArt" .. (steps + 1))
      or (vim.bo[b.buf].modified and ("HeaderArt" .. steps) or ("HeaderArt" .. math.max(1, math.floor(steps * 0.6))))
    api.nvim_buf_set_extmark(buf, procs_ns, r, c * 3, { end_col = c * 3 + 3, hl_group = hl })
  end
end

local function procs_select()
  local w = S.wins.procs
  if not valid_win(w) then return end
  local row, col = unpack(api.nvim_win_get_cursor(w))
  local idx = (row - 1) * 16 + math.floor(col / 3) + 1 -- each cell is one 3-byte glyph
  local n = math.min(#S.procs.list, 64)
  if idx > n then
    idx = n
    pcall(api.nvim_win_set_cursor, w, { math.floor((n - 1) / 16) + 1, ((n - 1) % 16) * 3 })
  end
  S.procs.sel = S.procs.list[idx]
  render_procs()
end

local function open_procs(dwin)
  if not S.rects.proc then
    vim.notify("The process map isn't on screen", vim.log.levels.INFO)
    return false
  end
  S.procs.list = list_buffers()
  if #S.procs.list == 0 then
    vim.notify("No listed buffers", vim.log.levels.INFO)
    return false
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  S.procs.buf = buf
  if not open_float("procs", buf, dwin) then return false end
  S.procs.sel = S.procs.list[1]
  render_procs()
  api.nvim_create_autocmd("CursorMoved", { buffer = buf, callback = procs_select })
  local function key(lhs, fn, desc) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = desc }) end
  local function done() hide("procs") end
  key("q", done, "HUD: close"); key("<Esc>", done, "HUD: close"); key("<C-q>", done, "HUD: close")
  key("<CR>", function()
    local b = S.procs.sel
    hide("procs")
    if b and valid_buf(b.buf) then take_over(b.buf) end
  end, "HUD: open the buffer")
  key("d", function()
    local b = S.procs.sel
    if not (b and valid_buf(b.buf)) then return end
    if vim.bo[b.buf].modified then
      return vim.notify("Buffer has unsaved changes", vim.log.levels.WARN)
    end
    pcall(api.nvim_buf_delete, b.buf, {})
    S.procs.list = list_buffers()
    if #S.procs.list == 0 then return hide("procs") end
    place("procs")
    procs_select()
  end, "HUD: delete the buffer")
  return true
end

---------------------------------------------------------------------------
-- 3 peek
---------------------------------------------------------------------------

local function open_peek(dwin)
  if not S.rects.hex then
    vim.notify("The hex dump isn't on screen", vim.log.levels.INFO)
    return false
  end
  local src = require("header_art.hud_data").sample().hex
  local buf = src and src.buf
  if not (buf and buf > 0 and valid_buf(buf)) then
    vim.notify("No file buffer to peek", vim.log.levels.INFO)
    return false
  end
  S.peek_buf = buf
  local w = open_float("peek", buf, dwin)
  if not w then S.peek_buf = nil; return false end
  vim.wo[w].number = true
  local mark = api.nvim_buf_get_mark(buf, '"')
  if mark[1] > 0 then pcall(api.nvim_win_set_cursor, w, mark) end
  map_keys(buf, "peek", { temporary = true }) -- a real file: removed on close
  return true
end

---------------------------------------------------------------------------
-- 4 git (lazygit)
---------------------------------------------------------------------------

local function open_git(dwin)
  if vim.fn.executable("lazygit") ~= 1 then
    vim.notify("lazygit isn't installed", vim.log.levels.WARN)
    return false
  end
  if valid_buf(S.git_buf) and job_alive(vim.b[S.git_buf].terminal_job_id) then
    if not open_float("git", S.git_buf, dwin) then return false end
  else
    local buf = palette_buf()
    local w = open_float("git", buf, dwin)
    if not w then
      pcall(api.nvim_buf_delete, buf, { force = true })
      return false
    end
    api.nvim_win_call(w, function() vim.fn.jobstart({ "lazygit" }, { term = true, cwd = vim.fn.getcwd() }) end)
    S.git_buf = buf
  end
  map_keys(S.git_buf, "git")
  vim.cmd("startinsert")
  return true
end

---------------------------------------------------------------------------
-- 5 music, 6 LSP, 7 diagnostics (actions, no float)
---------------------------------------------------------------------------

local function music()
  local ok, ui = pcall(require, "music.ui")
  if not ok then return vim.notify("lua/music isn't available", vim.log.levels.WARN) end
  ui.open()
end

local function lsp_menu()
  local items = {
    { label = "Info (:checkhealth vim.lsp)", run = function() vim.cmd("LspInfo") end },
    { label = "Log", run = function() vim.cmd("LspLog") end },
  }
  for _, c in ipairs(vim.lsp.get_clients()) do
    local n = vim.tbl_count(c.attached_buffers or {})
    items[#items + 1] = {
      label = ("Restart %s (%d buffer%s)"):format(c.name, n, n == 1 and "" or "s"),
      run = function() vim.cmd("LspRestart " .. c.name) end,
    }
  end
  vim.ui.select(items, { prompt = "LSP", format_item = function(i) return i.label end }, function(choice)
    if choice then choice.run() end
  end)
end

local function diagnostics()
  local ok, builtin = pcall(require, "telescope.builtin")
  if ok then return builtin.diagnostics() end
  vim.diagnostic.setqflist()
end

---------------------------------------------------------------------------
-- entry point
---------------------------------------------------------------------------

local OPEN = {
  shell = { open_shell, insert = true },
  claude = { open_claude, insert = true },
  procs = { open_procs },
  peek = { open_peek },
  git = { open_git, insert = true },
}
local ACTIONS = { music = music, lsp = lsp_menu, diagnostics = diagnostics }

--- The actions that need no panel rectangle (music player, LSP menu, diagnostics
--- list), for the static HUD's number keys. false for anything else.
function M.action(id)
  if not ACTIONS[id] then return false end
  ACTIONS[id]()
  return true
end

--- `id`: shell | claude | procs | peek | git (a float) or music | lsp |
--- diagnostics (an action). Returns false when it isn't possible.
function M.focus(id)
  local dwin = gate()
  if not dwin then return false end
  if ACTIONS[id] then
    ACTIONS[id]()
    return true
  end
  local o = OPEN[id]
  if not o then return false end
  if refocus(id, o.insert) then return true end
  if id == "claude" then S.expanded = true; place("claude") end
  return o[1](dwin) ~= false
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
          if not valid_win(w) then
            if id == "peek" then close(id) else S.wins[id] = nil end
          end
        end
      end)
    end,
  })
  -- A session that ends (claude_chats and toggleterm delete the buffer on
  -- exit, lazygit's terminal closes) gives its module back.
  api.nvim_create_autocmd({ "BufDelete", "TermClose" }, {
    group = grp,
    callback = function(ev)
      if ev.buf == S.claude_buf then S.claude_buf = nil end
      local git = ev.buf == S.git_buf
      if git then S.git_buf = nil end
      for id, w in pairs(S.wins) do
        if valid_win(w) and api.nvim_win_get_buf(w) == ev.buf then
          if id == "shell" then S.shell_id = nil end
          vim.schedule(function()
            if valid_win(S.wins[id]) and api.nvim_win_get_buf(S.wins[id]) == ev.buf then hide(id) end
            if not valid_win(S.wins[id]) then S.wins[id] = nil end
            if id == "claude" and not S.wins.claude then S.expanded = false end
          end)
        end
      end
      -- lazygit's buffer is only a viewport: wipe it once the job is done
      if git and ev.event == "TermClose" then
        vim.schedule(function() pcall(api.nvim_buf_delete, ev.buf, { force = true }) end)
      end
    end,
  })
end

return M
