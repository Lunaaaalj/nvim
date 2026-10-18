local cc = require("neo-tree.sources.common.commands")
local manager = require("neo-tree.sources.manager")
local utils = require("neo-tree.utils")
local chats = require("claude_chats")

-- Inherit navigation/selection/help commands. The filesystem-mutating ones are
-- overridden below: chat nodes carry the session .jsonl as `path`, and e.g.
-- the stock `delete` would happily remove the log file.
local M = vim.tbl_extend("force", {}, cc)

local function noop(msg)
  return function()
    if msg then
      vim.notify(msg, vim.log.levels.INFO)
    end
  end
end

for _, name in ipairs({
  "add_directory", "copy", "move", "trash", "copy_to_clipboard", "cut_to_clipboard",
  "paste_from_clipboard", "toggle_preview", "focus_preview", "set_root", "navigate_up",
}) do
  M[name] = noop()
end
M.rename = noop("Rename a chat with /rename inside it")

M.refresh = function()
  manager.refresh("claude")
end

-- Window to open a chat in: the last normal window, or a new split if the
-- tree is the only one.
local function target_window(state)
  local win, is_tree = utils.get_appropriate_window(state)
  if is_tree then
    vim.api.nvim_win_call(win, function()
      vim.cmd(state.current_position == "right" and "topleft vsplit" or "botright vsplit")
      win = vim.api.nvim_get_current_win()
    end)
  end
  return win
end

local function open_in(state, make_win)
  local node = state.tree:get_node()
  if not node then
    return
  end
  if node.type == "directory" then
    return cc.toggle_node(state)
  elseif node.type == "message" then
    return
  end
  local win = make_win(state)
  if not win then
    return
  end
  if node.type == "new_chat" then
    chats.open({ win = win })
  else
    chats.open({ session_id = node.extra.session_id, title = node.name, win = win })
  end
end

local function split(cmd)
  return function(state)
    local win = target_window(state)
    vim.api.nvim_win_call(win, function()
      vim.cmd(cmd)
      win = vim.api.nvim_get_current_win()
    end)
    return win
  end
end

M.open = function(state)
  open_in(state, target_window)
end
M.open_vsplit = function(state)
  open_in(state, split("vsplit"))
end
M.open_split = function(state)
  open_in(state, split("split"))
end
M.open_tabnew = function(state)
  open_in(state, function()
    vim.cmd("tabnew")
    return vim.api.nvim_get_current_win()
  end)
end
M.open_with_window_picker = function(state)
  open_in(state, function(s)
    local ok, picker = pcall(require, "window-picker")
    return ok and picker.pick_window() or target_window(s)
  end)
end

M.new_chat = function(state)
  chats.open({ win = target_window(state) })
end
M.add = M.new_chat

--- Stop the chat under the cursor (session stays resumable under Recent).
M.stop_chat = function(state)
  local node = state.tree:get_node()
  if node and node.type == "chat" and node.extra.running then
    chats.stop(node.extra.session_id)
  else
    vim.notify("Not a running chat", vim.log.levels.INFO)
  end
end
M.delete = M.stop_chat

return M
