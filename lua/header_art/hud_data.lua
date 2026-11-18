-- Live values for the `hud` piece: a sample of cheap Neovim/system readings
-- (cached for a second, so a 30 fps frame never pays for them) and a ring of
-- recent editor events fed by autocmds.

local uv = vim.uv or vim.loop

local M = {}

local function wall()
  local s, us = uv.gettimeofday()
  return s + us / 1e6
end
M.wall = wall
M.start_wall = wall()
local START = uv.hrtime()

-- Recent events, oldest first: { time = wall seconds, text = "..." }.
M.events = {}
local MAX_EVENTS = 60

function M.push(text)
  M.events[#M.events + 1] = { time = wall(), text = text }
  if #M.events > MAX_EVENTS then table.remove(M.events, 1) end
end

-- Branch from .git/HEAD (a worktree's .git is a file naming its gitdir), so
-- no git process runs every second.
local function git_branch(cwd)
  local git = vim.fs.find(".git", { upward = true, path = cwd, limit = 1 })[1]
  if not git then return nil end
  local head = git .. "/HEAD"
  if vim.fn.isdirectory(git) == 0 then
    local f = io.open(git)
    local line = f and f:read("*l")
    if f then f:close() end
    local dir = line and line:match("^gitdir:%s*(.-)%s*$")
    if not dir then return nil end
    if dir:sub(1, 1) ~= "/" then dir = vim.fs.dirname(git) .. "/" .. dir end
    head = dir .. "/HEAD"
  end
  local f = io.open(head)
  if not f then return nil end
  local line = f:read("*l") or ""
  f:close()
  return line:match("^ref: refs/heads/(.+)$") or line:sub(1, 7)
end

-- HEAD commit hash: .git/HEAD, then the ref's loose file (in the worktree's
-- gitdir or its commondir), then packed-refs.
local function git_head(cwd)
  local git = vim.fs.find(".git", { upward = true, path = cwd, limit = 1 })[1]
  if not git then return nil end
  local function read(p)
    local f = io.open(p)
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
  end
  local dir = git
  if vim.fn.isdirectory(git) == 0 then
    local d = (read(git) or ""):match("gitdir:%s*(%S+)")
    if not d then return nil end
    dir = d:sub(1, 1) == "/" and d or (vim.fs.dirname(git) .. "/" .. d)
  end
  local head = vim.trim(read(dir .. "/HEAD") or "")
  local ref = head:match("^ref:%s*(.+)$")
  if not ref then return head:match("^%x+$") end
  local common = vim.trim(read(dir .. "/commondir") or "")
  common = common == "" and dir or (common:sub(1, 1) == "/" and common or dir .. "/" .. common)
  for _, d in ipairs({ dir, common }) do
    local h = vim.trim(read(d .. "/" .. ref) or "")
    if h:match("^%x+$") then return h end
  end
  for line in (read(common .. "/packed-refs") or ""):gmatch("[^\n]+") do
    local h, name = line:match("^(%x+)%s+(%S+)$")
    if name == ref then return h end
  end
end

-- Up to HEX_MAX bytes of the most recently used listed file buffer, for the
-- hex dump; re-read only when the buffer or its changedtick changes. Without
-- one, this module's own source.
local HEX_MAX, hex_cache = 4096, nil
local function hex_source()
  local best
  for _, b in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if b.name ~= "" and vim.bo[b.bufnr].buftype == "" and (not best or b.lastused > best.lastused) then best = b end
  end
  if best then
    if hex_cache and hex_cache.buf == best.bufnr and hex_cache.tick == best.changedtick then return hex_cache end
    local lines = vim.api.nvim_buf_get_lines(best.bufnr, 0, 200, false)
    hex_cache = { buf = best.bufnr, tick = best.changedtick, name = vim.fn.fnamemodify(best.name, ":t"),
      bytes = table.concat(lines, "\n"):sub(1, HEX_MAX) }
    return hex_cache
  end
  if hex_cache and hex_cache.buf == -1 then return hex_cache end
  local path = debug.getinfo(1, "S").source:sub(2)
  local f = io.open(path)
  hex_cache = { buf = -1, name = vim.fn.fnamemodify(path, ":t"), bytes = f and f:read(HEX_MAX) or "" }
  if f then f:close() end
  return hex_cache
end

-- One { mem, load } per refreshed sample (about one a second while the HUD
-- is drawn), oldest first, for the telemetry strip.
M.history = {}
local MAX_HISTORY = 240

local cache, cache_at = nil, -math.huge

function M.sample()
  local now = uv.now()
  if cache and now - cache_at < 1000 then return cache end
  local v = vim.version()
  local s = { version = string.format("v%d.%d.%d", v.major, v.minor, v.patch), pid = uv.os_getpid() }
  local ok, st = pcall(function() return require("lazy").stats() end)
  if ok and type(st) == "table" then s.plugins, s.loaded, s.startup = st.count, st.loaded, st.startuptime end
  s.mem = (uv.resident_set_memory() or 0) / 1048576
  s.load = { uv.loadavg() }
  s.uptime = (uv.hrtime() - START) / 1e9
  s.buflist = {}
  for _, b in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    s.buflist[#s.buflist + 1] = { modified = b.changed == 1 }
  end
  s.bufs = #s.buflist
  s.clients = {}
  for _, c in ipairs(vim.lsp.get_clients()) do
    s.clients[#s.clients + 1] = { name = c.name, bufs = vim.tbl_count(c.attached_buffers or {}) }
  end
  table.sort(s.clients, function(p, q) return p.name < q.name end)
  s.lsp = #s.clients
  local ok2, cnt = pcall(vim.diagnostic.count)
  s.diag, s.errors = 0, 0
  if ok2 and type(cnt) == "table" then
    for sev, n in pairs(cnt) do
      s.diag = s.diag + n
      if sev == vim.diagnostic.severity.ERROR then s.errors = n end
    end
  end
  local cwd = vim.fn.getcwd()
  s.cwd = vim.fn.fnamemodify(cwd, ":~")
  s.branch = git_branch(cwd)
  s.head = git_head(cwd)
  s.hex = hex_source()
  M.history[#M.history + 1] = { mem = s.mem, load = s.load[1] or 0 }
  if #M.history > MAX_HISTORY then table.remove(M.history, 1) end
  s.history = M.history
  cache, cache_at = s, now
  return s
end

function M.now()
  return uv.gettimeofday()
end

function M.setup()
  local grp = vim.api.nvim_create_augroup("HeaderArtHud", { clear = true })
  local function au(ev, fn, pattern)
    vim.api.nvim_create_autocmd(ev, { group = grp, pattern = pattern, callback = fn })
  end
  local function file(ev) return vim.fn.fnamemodify(ev.file ~= "" and ev.file or vim.api.nvim_buf_get_name(ev.buf), ":t") end
  au("BufReadPost", function(ev)
    if vim.bo[ev.buf].buftype == "" and ev.file ~= "" then M.push("BufRead " .. file(ev)) end
  end)
  au("BufWritePost", function(ev) M.push("write " .. file(ev)) end)
  au("LspAttach", function(ev)
    local c = ev.data and vim.lsp.get_client_by_id(ev.data.client_id)
    if c then M.push("LspAttach " .. c.name) end
  end)
  au("LspDetach", function(ev)
    local c = ev.data and vim.lsp.get_client_by_id(ev.data.client_id)
    if c then M.push("LspDetach " .. c.name) end
  end)
  au("DirChanged", function() M.push("cd " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":~")) end)
  au("TermOpen", function() M.push("TermOpen shell") end)
  au("ColorScheme", function(ev) M.push("scheme " .. ev.match) end)
  au("VimResized", function() M.push(string.format("resize %dx%d", vim.o.columns, vim.o.lines)) end)
  local v = vim.version()
  M.push(string.format("nvim v%d.%d.%d online", v.major, v.minor, v.patch))
end

return M
