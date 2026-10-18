local common = require("neo-tree.sources.common.components")
local chats = require("claude_chats")

local M = vim.tbl_extend("force", {}, common)

-- Plain FontAwesome-range glyphs on purpose: nf-md glyphs render as tofu in
-- this terminal's font (see the git_status note in plugins/neo-tree.lua).
M.chat_icon = function(_, node)
  if node.type == "new_chat" then
    return { text = "+ ", highlight = "Special" }
  elseif node.extra and node.extra.running then
    return { text = "● ", highlight = "DiagnosticOk" }
  end
  return { text = "\u{f0e5} ", highlight = "Comment" }
end

M.chat_age = function(_, node)
  local t = node.extra and node.extra.mtime
  if not t then
    return {}
  end
  return { text = " " .. chats.age(t) .. " ", highlight = "Comment" }
end

return M
