-- Terminal sessions on top of toggleterm.
--
-- toggleterm draws the windows; this module owns everything else:
--   * ids: shells live in 1..99, REPLs in 100+ (they used to share toggleterm's
--     lowest-free-id pool, so opening the Python REPL first made it "shell #1")
--   * names: custom (rename) > running command > cwd basename
--   * live state from zsh's prompt hooks (shell/zsh/.zshenv) via TermRequest:
--     running command, exit status, cwd, output range of the last command
--   * unseen output, finish notifications, send / repeat / quickfix
--   * session save/restore of every terminal (persistence.nvim)
--
-- State changes fire `User TermsChanged` (debounced); the neo-tree "Terminals"
-- source and the winbar listen to it.

local M = {}

M.config = {
  notify_after = 5000, -- ms a command must run before its finish is announced
}

local SHELL_MAX = 99

-- Pinned REPLs: fixed ids above the shell range. `paste` picks how multi-line
-- text is sent: "python" checks the version (3.13+ has bracketed paste and
-- auto-indents; older REPLs need line-by-line), node and R take plain lines.
M.repls = {
  { key = "python", cmd = "python3", id = 100, paste = "python" },
  { key = "node", cmd = "node", id = 101 },
  { key = "R", cmd = "R", id = 102 },
}

local meta = {} ---@type table<integer, table>
local last_id ---@type integer?

local function tt()
  return require("toggleterm.terminal")
end

local function repl_by(field, value)
  for _, r in ipairs(M.repls) do
    if r[field] == value then return r end
  end
end

--- Per-terminal state, created lazily so terminals opened through toggleterm's
--- own commands (:ToggleTerm, :TermExec) are tracked too.
function M.info(id)
  meta[id] = meta[id] or { kind = repl_by("id", id) and "repl" or "shell" }
  return meta[id]
end

local pending = false
local function changed()
  if pending then return end
  pending = true
  vim.defer_fn(function()
    pending = false
    vim.cmd("redrawstatus!") -- winbar labels
    vim.api.nvim_exec_autocmds("User", { pattern = "TermsChanged", modeline = false })
  end, 80)
end

-- ---------------------------------------------------------------------------
-- Lookup

---@return Terminal?
function M.get(id)
  local t = id and tt().get(id, true)
  if t and t.bufnr and vim.api.nvim_buf_is_valid(t.bufnr) then return t end
end

--- Live terminals sorted by id.
---@return Terminal[]
function M.list()
  return vim.tbl_filter(function(t)
    return t.bufnr and vim.api.nvim_buf_is_valid(t.bufnr)
  end, tt().get_all(true))
end

local function visible(buf)
  return #vim.fn.win_findbuf(buf) > 0
end

--- The terminal an action without explicit target applies to: the one in the
--- current window, else the last one used, else the lowest live shell.
---@return Terminal?
function M.current()
  local here = vim.b.toggle_number
  if here and M.get(here) then return M.get(here) end
  if M.get(last_id) then return M.get(last_id) end
  for _, t in ipairs(M.list()) do
    if t.id <= SHELL_MAX then return t end
  end
end

function M.label(id)
  local m, t = M.info(id), M.get(id)
  if m.name then return m.name end
  local r = repl_by("id", id)
  if r then return r.key end
  if m.cmd then return vim.fs.basename(m.cmd:match("^%S+") or m.cmd) end
  local cwd = m.cwd or (t and t.dir)
  return cwd and vim.fn.fnamemodify(cwd, ":~:t") or "shell"
end

--- "running" | "failed" | "unseen" | "idle"
function M.state(id)
  local m = M.info(id)
  if m.cmd then return "running" end
  if m.exit and m.exit ~= 0 then return "failed" end
  if m.unseen then return "unseen" end
  return "idle"
end

-- Plain FontAwesome (BMP) glyphs: nf-md renders as tofu in this font.
M.glyphs = {
  running = "\u{f110}", -- spinner
  failed = "\u{f00d}", -- times
  unseen = "\u{f111}", -- circle
  idle = "\u{f120}", -- terminal
}

local function fmt_ms(ms)
  local s = math.floor(ms / 1000)
  if s < 60 then return s .. "s" end
  if s < 3600 then return ("%dm%02ds"):format(s / 60, s % 60) end
  return ("%dh%02dm"):format(s / 3600, s % 3600 / 60)
end

--- Short status text: the running command's name + elapsed, a failed exit,
--- or, for a renamed shell, its cwd's basename (unnamed ones already show it).
function M.detail(id)
  local m, t = M.info(id), M.get(id)
  if m.cmd then
    return ("%s %s"):format(vim.fs.basename(m.cmd:match("^%S+") or m.cmd), fmt_ms(vim.uv.now() - m.started))
  end
  if m.exit and m.exit ~= 0 then return "exit " .. m.exit end
  local cwd = m.cwd or (t and t.dir)
  if m.name and m.kind == "shell" and cwd then return vim.fn.fnamemodify(cwd, ":~:t") end
  return ""
end

-- ---------------------------------------------------------------------------
-- Creation

local function shell_env()
  if vim.fs.basename(vim.o.shell) ~= "zsh" then return nil end
  return {
    ZDOTDIR = vim.fn.stdpath("config") .. "/shell/zsh",
    NVIM_TERM_ZDOTDIR = vim.env.ZDOTDIR or "",
  }
end

local function free_shell_id()
  for id = 1, SHELL_MAX do
    if not tt().get(id, true) then return id end
  end
end

---@param id integer
---@param opts? { dir?: string, name?: string, direction?: string }
---@return Terminal
local function make(id, opts)
  opts = opts or {}
  local existing = tt().get(id, true)
  if existing then return existing end
  local r = repl_by("id", id)
  meta[id] = { kind = r and "repl" or "shell", name = opts.name, cwd = opts.dir }
  return tt().Terminal:new({
    id = id,
    cmd = r and r.cmd or nil,
    dir = opts.dir,
    direction = opts.direction,
    env = not r and shell_env() or nil,
  })
end

--- Open (or focus) a terminal, optionally in another direction.
function M.open(id, direction)
  local t = M.get(id) or make(id)
  if t:is_open() and (not direction or direction == t.direction) then
    t:focus()
    vim.cmd("startinsert")
  else
    if t:is_open() then t:close() end
    t:open(nil, direction)
  end
end

--- <C-\> / <leader>tt: with a count, toggle shell N; otherwise close the
--- terminal under the cursor, or toggle the last used one.
function M.toggle(count)
  if count and count > 0 then return make(count):toggle() end
  local here = vim.b.toggle_number
  if here and M.get(here) then return M.get(here):close() end
  local t = M.current() or make(1)
  t:toggle()
end

--- Toggle the current terminal in `direction` (float / horizontal / vertical).
function M.toggle_direction(direction)
  local t = M.current() or make(1)
  if t:is_open() and t.direction == direction then return t:close() end
  M.open(t.id, direction)
end

--- New shell in the first free id.
---@param opts? { dir?: string, name?: string, direction?: string }
function M.new(opts)
  local id = free_shell_id()
  if not id then return vim.notify("No free terminal ids (1-" .. SHELL_MAX .. ")", vim.log.levels.WARN) end
  make(id, opts):open(nil, opts and opts.direction)
  return id
end

--- New shell in the current file's directory, or its project (git) root.
function M.new_here(root)
  local file = vim.api.nvim_buf_get_name(0)
  local dir = file ~= "" and vim.fs.dirname(file) or vim.fn.getcwd()
  if root then dir = vim.fs.root(dir, ".git") or dir end
  if vim.fn.isdirectory(dir) == 0 then dir = vim.fn.getcwd() end
  M.new({ dir = dir })
end

function M.repl(key)
  local r = repl_by("key", key)
  make(r.id):toggle()
end

function M.rename(id, name)
  id = id or (M.current() or {}).id
  if not id then return end
  local function apply(n)
    if n == nil then return end
    M.info(id).name = n ~= "" and n or nil
    changed()
  end
  if name then return apply(name) end
  vim.ui.input({ prompt = "Terminal name (empty = automatic): ", default = M.info(id).name or "" }, apply)
end

function M.kill(id)
  local t = id and M.get(id) or M.current()
  if not t then return end
  local m = M.info(t.id)
  if m.cmd and vim.fn.confirm(("Kill %s (running %s)?"):format(M.label(t.id), m.cmd), "&Yes\n&No", 2) ~= 1 then
    return
  end
  t:shutdown()
  meta[t.id] = nil
  changed()
end

-- ---------------------------------------------------------------------------
-- Sending

local function ensure_job(t)
  if not (t.job_id and vim.fn.jobwait({ t.job_id }, 0)[1] == -1) then t:spawn() end
end

-- Does `python3` (as the REPL will resolve it) have the 3.13+ REPL?
local modern_python
local function python_pastes()
  if modern_python == nil then
    local v = vim.system({ "python3", "-c", "import sys; print(sys.version_info >= (3, 13))" }):wait()
    modern_python = vim.trim(v.stdout or "") == "True"
  end
  return modern_python
end

local function dedent(lines)
  local min
  for _, l in ipairs(lines) do
    if l:find("%S") then
      local w = #l:match("^%s*")
      min = math.min(min or w, w)
    end
  end
  if not min or min == 0 then return lines end
  return vim.tbl_map(function(l) return l:sub(min + 1) end, lines)
end

--- Send lines to a terminal (default: the current one; a new shell if none).
---@param lines string[]
---@param id? integer
function M.send(lines, id)
  local t = (id and M.get(id)) or M.current()
  if not t then
    -- Nothing to send to yet: open a shell beside the code and stay in it.
    local new = M.new()
    if not new then return end
    t = M.get(new)
    vim.cmd("stopinsert | wincmd p")
  end
  ensure_job(t)
  lines = dedent(lines)
  local r = repl_by("id", t.id)
  local text
  if #lines == 1 then
    text = lines[1] .. "\r"
  elseif r and r.paste == "python" and python_pastes() then
    -- One paste, then the blank line that closes a multi-statement input.
    -- That second Enter must arrive separately: pyrepl reads a fast burst of
    -- keys as more paste and would just add another `...` line.
    text = "\27[200~" .. table.concat(lines, "\n") .. "\27[201~\r"
    local job = t.job_id
    vim.defer_fn(function() pcall(vim.fn.chansend, job, "\r") end, 200)
  elseif r and r.paste == "python" then
    -- The pre-3.13 REPL ends a block on any blank line: drop them, and close
    -- a trailing indented block with one.
    lines = vim.tbl_filter(function(l) return l:find("%S") ~= nil end, lines)
    if (lines[#lines] or ""):match("^%s") then lines[#lines + 1] = "" end
    text = table.concat(lines, "\r") .. "\r"
  elseif r then
    text = table.concat(lines, "\r") .. "\r"
  else
    -- zsh: bracketed paste, so the block lands as one edit and runs once.
    text = "\27[200~" .. table.concat(lines, "\n") .. "\27[201~\r"
  end
  vim.fn.chansend(t.job_id, text)
  t:scroll_bottom()
  last_id = t.id
end

function M.send_line()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local n = math.max(vim.v.count, 1)
  M.send(vim.api.nvim_buf_get_lines(0, row - 1, row - 1 + n, false))
end

function M.send_selection()
  local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  M.send(lines)
end

--- Re-run the last command of the current shell without leaving the buffer.
function M.repeat_last(id)
  local t = (id and M.get(id)) or M.current()
  if not t then return vim.notify("No terminal to repeat in", vim.log.levels.INFO) end
  if repl_by("id", t.id) then return vim.notify("Repeat works in shells, not REPLs", vim.log.levels.INFO) end
  local m = M.info(t.id)
  if m.cmd then return vim.notify(("%s is still running %s"):format(M.label(t.id), m.cmd), vim.log.levels.WARN) end
  -- ^U clears anything half-typed at the prompt. Without the zsh hooks we
  -- don't know the command, so fall back to history (Up).
  vim.fn.chansend(t.job_id, "\21" .. (m.last_cmd and (m.last_cmd .. "\r") or "\27[A\r"))
  t:scroll_bottom()
end

-- ---------------------------------------------------------------------------
-- Output → quickfix

-- Prepended to 'errorformat': Python tracebacks and tsc. The rest (gcc/clang,
-- `file:line:col: msg`, …) comes from the default.
local EXTRA_EFM = table.concat({
  [[%\s%#File "%f"\, line %l\, in %m]],
  [[%\s%#File "%f"\, line %l]],
  [[%f(%l\,%c): %m]],
}, ",")
local DIR_MARK = "nvim-terminal-dir: "

--- Parse the last command's output (whole scrollback without the zsh hooks)
--- into the quickfix list, resolving relative paths against the shell's cwd.
function M.quickfix(id)
  local t = (id and M.get(id)) or M.current()
  if not t then return vim.notify("No terminal", vim.log.levels.INFO) end
  local m = M.info(t.id)
  local first, last = 0, -1
  -- Cursor rows (1-indexed) at 133;C and 133;D are the first output row and
  -- the row after the output; nvim_buf_get_lines wants 0-indexed [first, last).
  if m.out_start and m.out_start > 0 then
    first = m.out_start - 1
    if m.out_end and m.out_end >= m.out_start then last = m.out_end - 1 end
  end
  local lines = vim.api.nvim_buf_get_lines(t.bufnr, first, last, false)
  -- %D pushes a directory, so relative file names resolve against the shell's
  -- cwd instead of Neovim's.
  table.insert(lines, 1, DIR_MARK .. (m.cwd or t.dir or vim.fn.getcwd()))
  vim.fn.setqflist({}, " ", {
    title = "Terminal " .. t.id .. ": " .. (m.last_cmd or M.label(t.id)),
    lines = lines,
    efm = "%D" .. DIR_MARK .. "%f," .. EXTRA_EFM .. "," .. vim.o.errorformat,
  })
  local items = vim.tbl_filter(function(it) return it.valid == 1 end, vim.fn.getqflist())
  if #items == 0 then return vim.notify("No errors found in the terminal output", vim.log.levels.INFO) end
  vim.fn.setqflist({}, "r", { items = items })
  if not pcall(vim.cmd, "Trouble qflist open") then vim.cmd("copen") end
end

-- ---------------------------------------------------------------------------
-- Prompt hooks (TermRequest) and activity

local function on_request(ev)
  local id = vim.b[ev.buf].toggle_number
  if not id then return end
  local seq = type(ev.data) == "table" and ev.data.sequence or ev.data or ""
  local row = type(ev.data) == "table" and ev.data.cursor and ev.data.cursor[1] or nil
  seq = seq:gsub("\27\\$", ""):gsub("\a$", "")
  local m = M.info(id)

  local path = seq:match("^\27%]7;file://[^/]*(/.*)$")
  if path then
    path = vim.uri_decode(path)
    if path ~= m.cwd then
      m.cwd = path
      changed()
    end
    return
  end
  local cmdline = seq:match("^\27%]633;E;(.*)$")
  if cmdline then
    m.pending = cmdline
    return
  end
  if seq == "\27]133;C" then
    m.cmd = m.pending or "…"
    m.last_cmd, m.pending = m.pending or m.last_cmd, nil
    m.started, m.exit = vim.uv.now(), nil
    m.out_start, m.out_end = row, nil
    changed()
    return
  end
  local status = seq:match("^\27%]133;D;?(%d*)")
  if status and m.started then
    local cmd, dur = m.cmd, vim.uv.now() - m.started
    m.cmd, m.exit, m.out_end = nil, tonumber(status) or 0, row
    changed()
    if dur >= M.config.notify_after and vim.fn.bufwinid(ev.buf) == -1 then
      vim.notify(
        ("%s  %s  (%s)"):format(m.exit == 0 and "done" or ("exit " .. m.exit), cmd, fmt_ms(dur)),
        m.exit == 0 and vim.log.levels.INFO or vim.log.levels.ERROR,
        { title = ("Terminal %d · %s"):format(id, M.label(id)) }
      )
    end
  end
end

--- Called from toggleterm's on_create for every terminal.
function M.attach(t)
  local m = M.info(t.id)
  m.cwd = m.cwd or t.dir
  vim.api.nvim_buf_attach(t.bufnr, false, {
    on_lines = function()
      if not m.unseen and not visible(t.bufnr) then
        m.unseen = true
        changed()
      end
    end,
  })
  changed()
end

--- toggleterm's on_open: only deliberate opens make a terminal "last used"
--- (BufEnter also fires while toggleterm shuffles windows on close).
function M.on_open(t)
  last_id = t.id
end

function M.on_exit(t)
  meta[t.id] = nil
  if last_id == t.id then last_id = nil end
  changed()
end

-- ---------------------------------------------------------------------------
-- Winbar (toggleterm's per-terminal name formatter)

function M.winbar_label(t)
  return (" %d %s %s "):format(t.id, M.glyphs[M.state(t.id)], M.label(t.id))
end

local function winbar_highlights()
  local colors = require("defaults.colors")
  vim.api.nvim_set_hl(0, "WinBarActive", { fg = colors.accent(), bold = true, underline = true, sp = colors.accent() })
  vim.api.nvim_set_hl(0, "WinBarInactive", { fg = colors.fg("Comment") })
end

-- ---------------------------------------------------------------------------
-- Sessions (persistence.nvim)

--- JSON-able snapshot of every live terminal.
function M.session_state()
  local out = {}
  for _, t in ipairs(M.list()) do
    local m = M.info(t.id)
    out[#out + 1] = {
      id = t.id,
      name = m.name,
      dir = m.cwd or t.dir,
      direction = t.direction,
      open = t:is_open(),
    }
  end
  return out
end

--- Re-spawn a snapshot: fresh processes in the saved dirs, with their names,
--- reopening the ones that were visible.
function M.session_restore(list)
  for _, s in ipairs(list or {}) do
    if not M.get(s.id) then
      local dir = s.dir and vim.fn.isdirectory(s.dir) == 1 and s.dir or nil
      local t = make(s.id, { dir = dir, name = s.name, direction = s.direction })
      if s.open then t:open(nil, s.direction) else t:spawn() end
    end
  end
  vim.cmd("stopinsert")
end

-- ---------------------------------------------------------------------------

function M.setup()
  local group = vim.api.nvim_create_augroup("Terminals", { clear = true })
  vim.api.nvim_create_autocmd("TermRequest", { group = group, callback = on_request })
  vim.api.nvim_create_autocmd("TermEnter", {
    group = group,
    callback = function(ev) last_id = vim.b[ev.buf].toggle_number or last_id end,
  })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufEnter" }, {
    group = group,
    callback = function(ev)
      local id = vim.b[ev.buf].toggle_number
      if not id then return end
      local m = M.info(id)
      if m.unseen or (m.exit and m.exit ~= 0) then
        m.unseen = false
        if m.exit ~= 0 then m.exit = nil end -- the failure has been seen
        changed()
      end
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function() vim.schedule(winbar_highlights) end,
  })
  winbar_highlights()

  -- Running commands show elapsed time in the tree; tick while one runs.
  local timer = vim.uv.new_timer()
  timer:start(1000, 1000, vim.schedule_wrap(function()
    for _, m in pairs(meta) do
      if m.cmd then return changed() end
    end
  end))

  local cmd = vim.api.nvim_create_user_command
  cmd("TermNew", function(o) M.new({ dir = o.args ~= "" and vim.fn.expand(o.args) or nil }) end,
    { nargs = "?", complete = "dir", desc = "New shell (optionally in DIR)" })
  cmd("TermRename", function(o) M.rename(nil, o.args ~= "" and o.args or nil) end,
    { nargs = "?", desc = "Rename the current terminal" })
  cmd("TermKill", function() M.kill() end, { desc = "Kill the current terminal" })
  cmd("TermRepeat", function() M.repeat_last() end, { desc = "Re-run the last shell command" })
  cmd("TermQuickfix", function() M.quickfix() end, { desc = "Terminal output → quickfix" })
  cmd("TermPick", function() require("terminals.picker").pick() end, { desc = "Pick a terminal" })
end

return M
