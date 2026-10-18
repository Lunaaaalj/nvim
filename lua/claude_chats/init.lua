-- Claude Code chats as ordinary buffers.
--
-- claudecode.nvim manages ONE terminal in a split. This module runs any number
-- of `claude` processes in regular terminal buffers (one per chat) in whatever
-- window you choose, while still connecting each one to claudecode.nvim's IDE
-- WebSocket server — so selections, @-mentions and diffs keep working.
--
-- It also reads Claude's on-disk session logs (~/.claude/projects/<cwd>/*.jsonl)
-- so past chats can be listed and resumed. The neo-tree "Claude" tab
-- (claude_chats.neotree) is a thin view over `M.running()` / `M.sessions()`.

local M = {}

local MAX_SESSIONS = 40
local TAIL_BYTES = 64 * 1024

---------------------------------------------------------------------------
-- Session logs
---------------------------------------------------------------------------

-- Claude names a project's log dir after its cwd with every non-alphanumeric
-- char replaced by "-" (/Users/me/.config/nvim -> -Users-me--config-nvim).
local function project_dir(cwd)
  return vim.fn.expand("~/.claude/projects/") .. cwd:gsub("[^%w]", "-")
end

local function read_chunk(path, from_end)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local size = f:seek("end")
  if from_end then
    f:seek("set", math.max(0, size - TAIL_BYTES))
  else
    f:seek("set", 0)
  end
  local data = f:read(TAIL_BYTES)
  f:close()
  return data
end

-- Title priority: /rename (custom-title) > Claude's auto title (ai-title) >
-- the last prompt typed. These metadata lines are re-appended throughout a
-- session, so the file's tail almost always has them; the head is a fallback
-- for chats that never got that far.
local function extract_title(chunk)
  local found = {}
  for line in chunk:gmatch("[^\n]+") do
    local kind = line:match('^{"type":"([%w%-]+)"')
    if kind == "custom-title" or kind == "ai-title" or kind == "last-prompt" then
      local ok, d = pcall(vim.json.decode, line)
      if ok and type(d) == "table" then
        found[kind] = d.customTitle or d.aiTitle or d.lastPrompt or found[kind]
      end
    end
  end
  return found["custom-title"] or found["ai-title"] or found["last-prompt"]
end

local title_cache = {} -- path -> { mtime, size, title }

local function session_title(path, stat)
  local c = title_cache[path]
  if c and c.mtime == stat.mtime.sec and c.size == stat.size then
    return c.title
  end
  local title
  local tail = read_chunk(path, true)
  title = tail and extract_title(tail)
  if not title and stat.size > TAIL_BYTES then
    local head = read_chunk(path, false)
    title = head and extract_title(head)
  end
  title_cache[path] = { mtime = stat.mtime.sec, size = stat.size, title = title }
  return title
end

---@class ClaudeSession
---@field id string
---@field title string
---@field mtime integer
---@field path string

--- Past sessions for `cwd`, newest first. Logs with no prompt in them yet
--- (e.g. a chat opened and immediately closed) are skipped.
---@param cwd string?
---@return ClaudeSession[]
function M.sessions(cwd)
  local dir = project_dir(cwd or vim.fn.getcwd())
  local out = {}
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return out
  end
  while true do
    local name, typ = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    local id = name:match("^(.+)%.jsonl$")
    if id and typ == "file" then
      local path = dir .. "/" .. name
      local stat = vim.uv.fs_stat(path)
      local title = stat and session_title(path, stat)
      if title then
        out[#out + 1] = { id = id, title = vim.trim(title:gsub("%s+", " ")), mtime = stat.mtime.sec, path = path }
      end
    end
  end
  table.sort(out, function(a, b)
    return a.mtime > b.mtime
  end)
  for i = MAX_SESSIONS + 1, #out do
    out[i] = nil
  end
  return out
end

---------------------------------------------------------------------------
-- Running chats (terminal buffers tagged with b:claude_chat)
---------------------------------------------------------------------------

local function buf_name(title, id)
  -- "/" would make bufferline show only the part after it.
  return ("claude://%s [%s]"):format((title or "New chat"):gsub("/", "-"), id:sub(1, 8))
end

local function find_buf(session_id)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local tag = vim.b[buf].claude_chat
    if tag and tag.session_id == session_id and vim.api.nvim_buf_is_valid(buf) then
      return buf
    end
  end
end

---@class ClaudeRunningChat
---@field id string session id
---@field bufnr integer
---@field title string

--- Chats currently running in a buffer. Also re-syncs each buffer's name with
--- its session title, since Claude only generates a title after the first turn.
---@param sessions ClaudeSession[]? already-loaded session list to take titles from
---@return ClaudeRunningChat[]
function M.running(sessions)
  local titles = {}
  for _, s in ipairs(sessions or M.sessions()) do
    titles[s.id] = s.title
  end
  local out = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local tag = vim.b[buf].claude_chat
    if tag and vim.api.nvim_buf_is_valid(buf) then
      local title = titles[tag.session_id] or tag.title or "New chat"
      if title ~= tag.title then
        tag.title = title
        vim.b[buf].claude_chat = tag
        pcall(vim.api.nvim_buf_set_name, buf, buf_name(title, tag.session_id))
      end
      out[#out + 1] = { id = tag.session_id, bufnr = buf, title = title }
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------

local function uuid4()
  local b = { vim.uv.random(16):byte(1, 16) }
  b[7] = bit.bor(bit.band(b[7], 0x0f), 0x40) -- version 4
  b[9] = bit.bor(bit.band(b[9], 0x3f), 0x80) -- RFC 4122 variant
  return ("%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x"):format(unpack(b))
end

-- The same env claudecode.nvim gives its own terminal: it's what makes the CLI
-- connect back to Neovim (IDE integration) instead of running standalone.
local function claude_env()
  -- claudecode.nvim is lazy-loaded on its keys; make sure its server is up
  -- (e.g. when a chat is opened from the neo-tree tab first).
  pcall(function()
    require("lazy").load({ plugins = { "claudecode.nvim" } })
  end)
  local env = { ENABLE_IDE_INTEGRATION = "true", FORCE_CODE_TERMINAL = "true" }
  local ok, server = pcall(require, "claudecode.server.init")
  if ok and server.state and server.state.port then
    env.CLAUDE_CODE_SSE_PORT = tostring(server.state.port)
  end
  -- Never route the loopback IDE WebSocket through a proxy (claudecode #70).
  local no_proxy = table.concat(
    vim.tbl_filter(function(v)
      return v and v ~= ""
    end, { os.getenv("no_proxy") or os.getenv("NO_PROXY"), "localhost,127.0.0.1,::1" }),
    ","
  )
  env.no_proxy, env.NO_PROXY = no_proxy, no_proxy
  return env
end

local function refresh_tree()
  vim.schedule(function()
    pcall(function()
      require("neo-tree.sources.manager").refresh("claude")
    end)
  end)
end

local function focus(win, buf)
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_set_current_win(win)
  vim.cmd.startinsert()
end

--- Open a chat in a window: focuses it if it's already running, otherwise
--- starts `claude` (resuming `session_id` if given, else a fresh chat).
---@param opts { session_id?: string, title?: string, win?: integer }?
---@return integer bufnr
function M.open(opts)
  opts = opts or {}
  local win = opts.win or vim.api.nvim_get_current_win()

  local existing = opts.session_id and find_buf(opts.session_id)
  if existing then
    focus(win, existing)
    return existing
  end

  -- Pre-assign the id for new chats so the buffer can be matched to its
  -- session log (and listed under "Running") before Claude writes anything.
  local id = opts.session_id or uuid4()
  local cmd = opts.session_id and { "claude", "--resume", id } or { "claude", "--session-id", id }

  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_call(win, function()
    vim.fn.jobstart(cmd, {
      term = true,
      env = claude_env(),
      on_exit = function()
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
          end
          refresh_tree()
        end)
      end,
    })
  end)
  vim.b[buf].claude_chat = { session_id = id, title = opts.title }
  pcall(vim.api.nvim_buf_set_name, buf, buf_name(opts.title, id))
  -- Land in insert mode whenever you switch back to a chat, like a REPL.
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    callback = function()
      vim.cmd.startinsert()
    end,
  })

  vim.api.nvim_set_current_win(win)
  vim.cmd.startinsert()
  refresh_tree()
  return buf
end

--- New chat in the current window.
function M.new()
  return M.open()
end

--- Pick a past session (vim.ui.select → Telescope) and resume it in the
--- current window.
function M.pick()
  local sessions = M.sessions()
  if #sessions == 0 then
    vim.notify("No Claude sessions for " .. vim.fn.getcwd(), vim.log.levels.INFO)
    return
  end
  vim.ui.select(sessions, {
    prompt = "Resume Claude chat",
    format_item = function(s)
      return ("%-6s %s"):format(M.age(s.mtime), s.title)
    end,
  }, function(choice)
    if choice then
      M.open({ session_id = choice.id, title = choice.title })
    end
  end)
end

--- Stop a running chat (kills the process; the session stays resumable).
---@param session_id string
function M.stop(session_id)
  local buf = find_buf(session_id)
  if buf then
    vim.api.nvim_buf_delete(buf, { force = true })
    refresh_tree()
  end
end

--- Compact relative age: "now", "12m", "5h", "3d", "Mar 4".
---@param t integer epoch seconds
function M.age(t)
  local d = os.time() - t
  if d < 60 then
    return "now"
  elseif d < 3600 then
    return math.floor(d / 60) .. "m"
  elseif d < 86400 then
    return math.floor(d / 3600) .. "h"
  elseif d < 7 * 86400 then
    return math.floor(d / 86400) .. "d"
  end
  return os.date("%b %-d", t)
end

return M
