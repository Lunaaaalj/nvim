-- Spell audit: walk every spelling issue in the buffer, one at a time, in a
-- float under the word, jumping to the next one after each action.
--
--   1-9 / <CR>   replace with that suggestion (<CR>: the one under the cursor)
--   R            replace every occurrence of the word with it
--   e            type the replacement yourself
--   s / <Space>  skip this one          S  ignore the word (this session)
--   a            add the word to your spellfile (zg)
--   u            undo the last action and go back to it
--   q / <Esc>    stop (`:SpellAudit` / <leader>sa again resumes)
--
-- Issues are found with `]s` + spellbadword(), not by checking strings, so
-- they are exactly what `]s` visits: syntax/treesitter @nospell regions (code
-- blocks, LaTeX commands) are left out. The buffer is rescanned after every
-- action, so edits never leave stale positions; skipped ones are extmarks, so
-- they move with the text.

local M = {}

M.config = { suggestions = 9 }

local api = vim.api
local ns = api.nvim_create_namespace("spellaudit") -- highlight of the current word
local ns_skip = api.nvim_create_namespace("spellaudit_skip")

local S -- the running audit

local KIND = { bad = "misspelled", caps = "capitalise", rare = "rare word", ["local"] = "other region" }

local function set_hl()
  local colors = require("defaults.colors")
  local acc = colors.accent()
  local bg = api.nvim_get_hl(0, { name = "NormalFloat", link = false }).bg
    or api.nvim_get_hl(0, { name = "Normal", link = false }).bg
    or tonumber(colors.terminal_bg:sub(2), 16)
  api.nvim_set_hl(0, "SpellAuditAccent", { fg = acc })
  api.nvim_set_hl(0, "SpellAuditTitle", { fg = acc, bold = true })
  api.nvim_set_hl(0, "SpellAuditMuted", { fg = colors.fg("Comment") })
  api.nvim_set_hl(0, "SpellAuditBad", { fg = colors.fg("DiagnosticError", "ErrorMsg"), bold = true, underline = true })
  api.nvim_set_hl(0, "SpellAuditWord", { bg = colors.blend(acc, bg, 0.35), bold = true })
  api.nvim_set_hl(0, "SpellAuditSel", { bg = colors.blend(acc, bg, 0.22) })
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Spell audit" })
end

local function skipped(buf, row, col)
  return #api.nvim_buf_get_extmarks(buf, ns_skip, { row - 1, col }, { row - 1, col }, {}) > 0
end

-- Every issue `]s` would visit in `win`: { row, col (0-based byte), word, kind }.
local function issues(win)
  local buf = api.nvim_win_get_buf(win)
  return api.nvim_win_call(win, function()
    local view, wrapscan = vim.fn.winsaveview(), vim.o.wrapscan
    vim.o.wrapscan = false
    local out = {}
    -- spellbadword(): the bad word under or after the cursor, in its line only.
    local function here()
      local r = vim.fn.spellbadword()
      if r[1] == "" then return false end
      local p = api.nvim_win_get_cursor(0)
      if not skipped(buf, p[1], p[2]) then
        out[#out + 1] = { row = p[1], col = p[2], word = r[1], kind = r[2] }
      end
      return true
    end
    api.nvim_win_set_cursor(0, { 1, 0 })
    here() -- `]s` from here would step over a word at the very start
    while true do
      local before = api.nvim_win_get_cursor(0)
      vim.cmd("silent! normal! ]s")
      local p = api.nvim_win_get_cursor(0)
      if (p[1] == before[1] and p[2] == before[2]) or not here() then break end
    end
    vim.o.wrapscan = wrapscan
    vim.fn.winrestview(view)
    return out
  end)
end

local function close_float()
  if S and S.float and api.nvim_win_is_valid(S.float) then
    S.closing = true
    api.nvim_win_close(S.float, true)
    S.closing = false
  end
end

local function finish(stopped)
  if not S then return end
  local s = S
  close_float()
  if api.nvim_buf_is_valid(s.buf) then api.nvim_buf_clear_namespace(s.buf, ns, 0, -1) end
  if api.nvim_win_is_valid(s.win) then api.nvim_set_current_win(s.win) end
  local c = s.count
  local summary = ("%d fixed, %d skipped, %d ignored, %d added"):format(c.fixed, c.skipped, c.ignored, c.added)
  if stopped then
    s.paused = true -- keep the counts and skips for a resume
    notify("Paused (" .. summary .. "). <leader>sa resumes.")
  else
    S = nil
    if api.nvim_buf_is_valid(s.buf) then api.nvim_buf_clear_namespace(s.buf, ns_skip, 0, -1) end
    if api.nvim_win_is_valid(s.win) then vim.wo[s.win].spell = s.spell_was end
    notify(s.total == 0 and "No spelling issues" or "Done: " .. summary)
  end
end

local function done() return S.count.fixed + S.count.skipped + S.count.ignored + S.count.added end

-- Lines of the float and where things are on them.
local function build(issue, sugg, width)
  local lines, hls = {}, {}
  local function add(text, groups)
    lines[#lines + 1] = text
    for _, g in ipairs(groups or {}) do hls[#hls + 1] = { #lines - 1, g[1], g[2], g[3] } end
  end

  -- The line, trimmed around the word.
  local text = api.nvim_buf_get_lines(S.buf, issue.row - 1, issue.row, false)[1] or ""
  local s, e = issue.col, issue.col + #issue.word
  local room = width - 4
  local left = math.max(0, s - math.floor((room - #issue.word) / 2))
  local pre = (left > 0 and "…" or "") .. text:sub(left + 1, s):gsub("^%s+", "")
  local post = text:sub(e + 1, e + room - vim.fn.strdisplaywidth(pre) - #issue.word)
  if e + #post < #text then post = post .. "…" end
  local ctx = " " .. pre .. issue.word .. post
  add(ctx, { { "SpellAuditMuted", 0, -1 }, { "SpellAuditBad", 1 + #pre, 1 + #pre + #issue.word } })
  add(" " .. (KIND[issue.kind] or issue.kind), { { "SpellAuditMuted", 0, -1 } })
  add("")

  local first = #lines + 1
  if #sugg == 0 then add("   no suggestions", { { "SpellAuditMuted", 0, -1 } }) end
  for i, w in ipairs(sugg) do add(("  %d  %s"):format(i, w), { { "SpellAuditAccent", 2, 3 } }) end
  return lines, hls, first
end

local FOOTER = " 1-9 fix · R all · e edit · s skip · S ignore · a add · u undo · q quit "

local function render(issue)
  local buf, win = S.buf, S.win
  S.issue = issue
  S.pos = { issue.row, issue.col }

  -- Put the word on screen and mark it.
  api.nvim_win_set_cursor(win, { issue.row, issue.col })
  api.nvim_win_call(win, function()
    vim.cmd("silent! normal! zv")
    local wl, wh = vim.fn.winline(), api.nvim_win_get_height(0)
    if wl < 3 or wl > wh - 3 then vim.cmd("normal! zz") end
  end)
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  api.nvim_buf_set_extmark(buf, ns, issue.row - 1, issue.col, {
    end_col = issue.col + #issue.word, hl_group = "SpellAuditWord", priority = 300,
  })

  S.sugg = api.nvim_win_call(win, function()
    return vim.fn.spellsuggest(issue.word, M.config.suggestions, issue.kind == "caps")
  end)

  local width = math.max(#FOOTER, 44)
  for _, w in ipairs(S.sugg) do width = math.max(width, #w + 8) end
  width = math.min(width, api.nvim_win_get_width(win) - 2)
  local lines, hls, first = build(issue, S.sugg, width)
  S.first = first

  if not (S.fbuf and api.nvim_buf_is_valid(S.fbuf)) then
    S.fbuf = api.nvim_create_buf(false, true)
    vim.bo[S.fbuf].bufhidden = "wipe"
    vim.bo[S.fbuf].filetype = "spellaudit" -- cursorline.lua's unmanaged_ft: the cursorline is the selection
    M.keymaps(S.fbuf)
  end
  vim.bo[S.fbuf].modifiable = true
  api.nvim_buf_set_lines(S.fbuf, 0, -1, false, lines)
  vim.bo[S.fbuf].modifiable = false
  api.nvim_buf_clear_namespace(S.fbuf, ns, 0, -1)
  for _, h in ipairs(hls) do
    api.nvim_buf_set_extmark(S.fbuf, ns, h[1], h[3], {
      end_row = h[4] == -1 and h[1] + 1 or h[1], end_col = h[4] ~= -1 and h[4] or 0, hl_group = h[2],
    })
  end

  -- Below the word, or above it when there's no room.
  local height = #lines
  local below = api.nvim_win_call(win, vim.fn.winline) + height + 3 <= api.nvim_win_get_height(win)
  local cfg = {
    relative = "win", win = win, bufpos = { issue.row - 1, issue.col },
    row = below and 1 or 0, col = -2, anchor = below and "NW" or "SW",
    width = width, height = height, border = "rounded", style = "minimal",
    title = (" Spell %d/%d "):format(done() + 1, done() + S.remaining), title_pos = "left",
    footer = FOOTER, footer_pos = "center",
  }
  if S.float and api.nvim_win_is_valid(S.float) then
    api.nvim_win_set_config(S.float, cfg)
  else
    cfg.zindex = 60
    S.float = api.nvim_open_win(S.fbuf, true, cfg)
    vim.wo[S.float].cursorline = true
    vim.wo[S.float].winhighlight = "CursorLine:SpellAuditSel,FloatTitle:SpellAuditTitle,FloatFooter:SpellAuditMuted"
    vim.wo[S.float].winblend = 0
    api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(S.float), once = true,
      callback = function() if S and not S.closing then vim.schedule(function() finish(true) end) end end,
    })
  end
  api.nvim_set_current_win(S.float)
  api.nvim_win_set_cursor(S.float, { first, 0 })
end

-- Show the first issue at or after the last position (wrapping around).
local function step()
  if not (api.nvim_win_is_valid(S.win) and api.nvim_buf_is_valid(S.buf)) then return finish(true) end
  local list = issues(S.win)
  S.remaining = #list
  if #list == 0 then return finish(false) end
  local pick = list[1]
  for _, it in ipairs(list) do
    if it.row > S.pos[1] or (it.row == S.pos[1] and it.col >= S.pos[2]) then pick = it break end
  end
  render(pick)
end

local function push(entry)
  entry.pos = { S.issue.row, S.issue.col }
  S.history[#S.history + 1] = entry
  S.count[entry.kind] = S.count[entry.kind] + 1
end

-- Start a new undo block and return the change number to undo back to, so
-- `u` reverts exactly one action even when edits arrive in one input burst.
local function checkpoint()
  return api.nvim_buf_call(S.buf, function()
    vim.cmd("let &l:undolevels = &l:undolevels") -- breaks the undo sequence
    return vim.fn.changenr()
  end)
end

local function replace_here(text)
  local it = S.issue
  local before = checkpoint()
  api.nvim_buf_set_text(S.buf, it.row - 1, it.col, it.row - 1, it.col + #it.word, { text })
  push({ kind = "fixed", change = before })
end

-- Whole-word, case-sensitive, using 'iskeyword' (so accented letters count).
local function replace_all(text)
  local word = S.issue.word
  local re = vim.regex("\\V\\C\\<" .. vim.fn.escape(word, "\\") .. "\\>")
  local n, before = 0, checkpoint()
  for lnum = 0, api.nvim_buf_line_count(S.buf) - 1 do
    local hits, start = {}, 0
    while true do
      local s, e = re:match_line(S.buf, lnum, start)
      if not s then break end
      hits[#hits + 1] = { start + s, start + e }
      start = start + e
    end
    for i = #hits, 1, -1 do
      api.nvim_buf_set_text(S.buf, lnum, hits[i][1], lnum, hits[i][2], { text })
      n = n + 1
    end
  end
  push({ kind = "fixed", change = before })
  S.count.fixed = S.count.fixed + n - 1
  S.history[#S.history].n = n
end

local function selected()
  local i = api.nvim_win_get_cursor(S.float)[1] - S.first + 1
  return S.sugg[i]
end

local actions = {}

function actions.pick(i)
  local w = S.sugg[i]
  if w then replace_here(w); step() end
end

function actions.cr()
  local w = selected()
  if w then replace_here(w); step() end
end

function actions.all()
  local w = selected() or S.sugg[1]
  if w then replace_all(w); step() end
end

function actions.edit()
  local it = S.issue
  vim.ui.input({ prompt = "Replace “" .. it.word .. "” with: ", default = selected() or it.word }, function(text)
    if not S then return end
    if text and text ~= "" and text ~= it.word then replace_here(text) end
    step()
  end)
end

function actions.skip()
  local it = S.issue
  local id = api.nvim_buf_set_extmark(S.buf, ns_skip, it.row - 1, it.col, {})
  push({ kind = "skipped", mark = id })
  S.pos = { it.row, it.col + 1 }
  step()
end

function actions.ignore()
  -- In the edited window: the float has 'spell' off and its own 'spelllang'.
  api.nvim_win_call(S.win, function() vim.cmd("silent spellgood! " .. vim.fn.fnameescape(S.issue.word)) end)
  push({ kind = "ignored", word = S.issue.word })
  step()
end

function actions.add()
  api.nvim_win_call(S.win, function() vim.cmd("silent spellgood " .. vim.fn.fnameescape(S.issue.word)) end)
  push({ kind = "added", word = S.issue.word })
  step()
end

function actions.undo()
  local e = table.remove(S.history)
  if not e then return notify("Nothing to undo", vim.log.levels.WARN) end
  S.count[e.kind] = S.count[e.kind] - (e.n or 1)
  if e.change then
    api.nvim_buf_call(S.buf, function() vim.cmd("silent undo " .. e.change) end)
  elseif e.kind == "skipped" then
    api.nvim_buf_del_extmark(S.buf, ns_skip, e.mark)
  elseif e.kind == "ignored" then
    api.nvim_win_call(S.win, function() vim.cmd("silent spellundo! " .. vim.fn.fnameescape(e.word)) end)
  elseif e.kind == "added" then
    api.nvim_win_call(S.win, function() vim.cmd("silent spellundo " .. vim.fn.fnameescape(e.word)) end)
  end
  S.pos = e.pos
  step()
end

function actions.quit() finish(true) end

function M.keymaps(buf)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = "Spell audit: " .. desc })
  end
  for i = 1, 9 do map(tostring(i), function() actions.pick(i) end, "use suggestion " .. i) end
  map("<CR>", actions.cr, "use suggestion under cursor")
  map("R", actions.all, "replace every occurrence")
  map("e", actions.edit, "type a replacement")
  map("s", actions.skip, "skip")
  map("<Space>", actions.skip, "skip")
  map("S", actions.ignore, "ignore word this session")
  map("a", actions.add, "add word to spellfile")
  map("u", actions.undo, "undo last action")
  map("q", actions.quit, "stop")
  map("<Esc>", actions.quit, "stop")
end

--- Start (or resume) the audit of the current window's buffer.
function M.start()
  local win = api.nvim_get_current_win()
  if S and S.float and api.nvim_win_is_valid(S.float) then return api.nvim_set_current_win(S.float) end
  if S and S.paused and api.nvim_buf_is_valid(S.buf) and S.buf == api.nvim_win_get_buf(win) then
    S.paused, S.win = false, win
    return step()
  end
  if vim.bo.buftype ~= "" then return notify("Not a file buffer", vim.log.levels.WARN) end
  set_hl()
  S = {
    buf = api.nvim_get_current_buf(), win = win,
    pos = { 1, 0 }, history = {},
    count = { fixed = 0, skipped = 0, ignored = 0, added = 0 },
    spell_was = vim.wo[win].spell,
  }
  vim.wo[win].spell = true
  local list = issues(win)
  S.total = #list
  step()
end

function M.setup()
  api.nvim_create_user_command("SpellAudit", M.start, { desc = "Walk every spelling issue in the buffer" })
  vim.keymap.set("n", "<leader>sa", M.start, { desc = "Spell audit (walk every issue)" })
  api.nvim_create_autocmd("ColorScheme", {
    group = api.nvim_create_augroup("spellaudit_hl", { clear = true }),
    callback = function() if S then set_hl() end end,
  })
end

return M
