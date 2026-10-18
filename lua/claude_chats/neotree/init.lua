-- Neo-tree source: a "Claude" tab next to Files / Bufs / Git listing the
-- chats running in buffers plus recent sessions for the cwd.
--
--   ＋ New chat
--   ▾ Running
--       ● Fix vimtex init          2m
--   ▾ Recent
--        Lazygit AI commit msgs   3d
--
-- Data comes from claude_chats (session logs + tagged terminal buffers);
-- this file only turns it into tree nodes.

local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local events = require("neo-tree.events")
local utils = require("neo-tree.utils")
local chats = require("claude_chats")

---@class neotree.sources.Claude : neotree.Source
local M = {
  name = "claude",
  display_name = " \u{f086} Claude ",
}

local function chat_node(id, title, mtime, extra)
  return {
    id = id,
    name = title,
    type = "chat",
    path = extra.path or id, -- components key off `path`; keep it unique
    extra = vim.tbl_extend("force", { session_id = id, mtime = mtime }, extra),
  }
end

local function group(id, name, children, path)
  return { id = id, name = name, type = "directory", path = path .. "#" .. id, loaded = true, children = children }
end

---@param state neotree.State
M.navigate = function(state, path, path_to_reveal, callback)
  state.dirty = false
  state.path = path or state.path or vim.fn.getcwd()

  local sessions = chats.sessions(state.path)
  local running = chats.running(sessions)
  local by_id = {}
  for _, s in ipairs(sessions) do
    by_id[s.id] = s
  end

  local running_nodes, running_ids = {}, {}
  for _, r in ipairs(running) do
    running_ids[r.id] = true
    local s = by_id[r.id]
    running_nodes[#running_nodes + 1] =
      chat_node(r.id, r.title, s and s.mtime, { bufnr = r.bufnr, running = true, path = s and s.path })
  end

  local recent_nodes = {}
  for _, s in ipairs(sessions) do
    if not running_ids[s.id] then
      recent_nodes[#recent_nodes + 1] = chat_node(s.id, s.title, s.mtime, { path = s.path })
    end
  end

  local items = { { id = "new_chat", name = "New chat", type = "new_chat", path = state.path .. "#new" } }
  if #running_nodes > 0 then
    items[#items + 1] = group("running", "Running", running_nodes, state.path)
  end
  if #recent_nodes > 0 then
    items[#items + 1] = group("recent", "Recent", recent_nodes, state.path)
  else
    items[#items + 1] = { id = "empty", name = "No past chats in this dir", type = "message", path = state.path .. "#empty" }
  end

  state.default_expanded_nodes = { "running", "recent" }
  if path_to_reveal then
    renderer.position.set(state, path_to_reveal)
  end
  renderer.show_nodes(items, state)
  if type(callback) == "function" then
    vim.schedule(callback)
  end
end

M.setup = function(config, global_config)
  -- Titles/ages change as chats progress and buffers come and go; re-scan
  -- (cheap: titles are cached by mtime) when the tree might be stale.
  local refresh = function()
    utils.debounce("claude_chats_refresh", function()
      manager.refresh(M.name)
    end, 300, utils.debounce_strategy.CALL_LAST_ONLY)
  end
  for _, e in ipairs({ events.VIM_BUFFER_ADDED, events.VIM_BUFFER_DELETED, events.VIM_BUFFER_ENTER }) do
    manager.subscribe(M.name, { event = e, handler = refresh })
  end
  manager.subscribe(M.name, {
    event = events.VIM_DIR_CHANGED,
    handler = function()
      manager.navigate(M.name, vim.fn.getcwd())
    end,
  })
end

M.default_config = {
  renderers = {
    new_chat = {
      { "indent" },
      { "chat_icon" },
      { "name", highlight = "Special" },
    },
    directory = {
      { "indent" },
      { "icon" },
      { "name" },
    },
    chat = {
      { "indent" },
      { "chat_icon" },
      {
        "container",
        content = {
          { "name", zindex = 10 },
          { "chat_age", zindex = 20, align = "right" },
        },
      },
    },
    message = {
      { "indent", with_markers = false },
      { "name", highlight = "NeoTreeMessage" },
    },
  },
  window = {
    mappings = {
      ["<cr>"] = "open",
      ["a"] = "new_chat",
      ["n"] = "new_chat",
      ["d"] = "stop_chat",
      ["R"] = "refresh",
    },
  },
}

return M
