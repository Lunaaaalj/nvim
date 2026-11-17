-- Git cues from the reflog: commit / pull / push, whoever ran git (a terminal,
-- lazygit, Claude, upstream.nvim). Watches `<gitdir>/logs` recursively (FSEvents
-- on macOS) and reads only the bytes appended since the last event.
--   logs/HEAD                 "commit…", "pull…", "merge…", "rebase (finish)…"
--   logs/refs/remotes/**      "update by push" (fetches are ignored)
-- Only runs while sounds are enabled.
local M = {}

local uv = vim.uv
local handles = {} -- logs dir -> fs_event handle
local seen = {} -- file path -> bytes already read
local pending = {} -- kind -> true, flushed once per burst
local timer

local function classify(msg)
  if msg:match("^commit %(merge%)") then return "pull" end
  if msg:match("^commit") then return "commit" end
  if msg:match("^pull") or msg:match("^merge") or msg:match("^rebase %(finish%)") then return "pull" end
  if msg:match("update by push") then return "push" end
end

local function flush()
  local kinds = pending
  pending = {}
  -- one cue per burst: a pull may log several lines (and a merge commit)
  for _, kind in ipairs({ "pull", "commit", "push" }) do
    if kinds[kind] then
      vim.schedule(function() require("sounds").play(kind) end)
      return
    end
  end
end

--- Read what `path` gained since the last look and record the kinds found.
local function scan(path)
  local st = uv.fs_stat(path)
  if not st or st.type ~= "file" then return end
  local from = seen[path] or 0
  seen[path] = st.size
  if st.size <= from then return end
  local fd = uv.fs_open(path, "r", 438)
  if not fd then return end
  local data = uv.fs_read(fd, st.size - from, from)
  uv.fs_close(fd)
  for line in (data or ""):gmatch("[^\n]+") do
    local kind = classify(line:match("\t(.*)$") or "")
    if kind then pending[kind] = true end
  end
  if not timer then timer = uv.new_timer() end
  timer:stop()
  timer:start(150, 0, flush)
end

local function prime(logs)
  seen[logs .. "/HEAD"] = (uv.fs_stat(logs .. "/HEAD") or {}).size or 0
  local function walk(d)
    local it = uv.fs_scandir(d)
    while it do
      local name, typ = uv.fs_scandir_next(it)
      if not name then break end
      local p = d .. "/" .. name
      if typ == "directory" then walk(p) else seen[p] = (uv.fs_stat(p) or {}).size or 0 end
    end
  end
  walk(logs .. "/refs/remotes")
end

local function watch(logs)
  if handles[logs] or not uv.fs_stat(logs) then return end
  prime(logs)
  local h = uv.new_fs_event()
  local ok = h:start(logs, { recursive = true }, function(err, name)
    if err or not name then return end
    if name == "HEAD" or name:match("^refs/remotes/") then scan(logs .. "/" .. name) end
  end)
  if ok == 0 then handles[logs] = h else h:close() end
end

function M.stop()
  for k, h in pairs(handles) do
    pcall(h.stop, h)
    if not h:is_closing() then h:close() end
    handles[k] = nil
  end
  seen, pending = {}, {}
  if timer then timer:stop() end
end

--- (Re)target the watcher at the repository of the cwd.
function M.start()
  M.stop()
  vim.system(
    { "git", "rev-parse", "--path-format=absolute", "--absolute-git-dir", "--git-common-dir" },
    { cwd = vim.fn.getcwd(), text = true },
    vim.schedule_wrap(function(res)
      if res.code ~= 0 or not require("sounds").enabled then return end
      local gitdir, common = res.stdout:match("^(.-)\n(.-)\n?$")
      if not gitdir then return end
      M.stop() -- a restart that raced this callback
      watch(common .. "/logs") -- HEAD of the main worktree + every remote
      if gitdir ~= common then watch(gitdir .. "/logs") end -- a linked worktree's own HEAD
    end)
  )
end

return M
