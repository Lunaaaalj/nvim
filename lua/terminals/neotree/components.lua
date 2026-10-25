local common = require("neo-tree.sources.common.components")
local terms = require("terminals")

local M = vim.tbl_extend("force", {}, common)

local state_hl = {
  running = "DiagnosticWarn",
  failed = "DiagnosticError",
  unseen = "Function", -- the scheme's accent
  idle = "Comment",
}

M.term_icon = function(_, node)
  if node.type == "new_shell" then
    return { text = "+ ", highlight = "Special" }
  end
  local id = node.extra.term_id
  if not node.extra.live then
    return { text = terms.glyphs.idle .. " ", highlight = "NonText" }
  end
  local st = terms.state(id)
  return { text = terms.glyphs[st] .. " ", highlight = state_hl[st] }
end

M.term_name = function(_, node)
  local id = node.extra.term_id
  if node.extra.repl then
    return { text = node.name, highlight = node.extra.live and "NeoTreeFileName" or "NonText" }
  end
  return {
    { text = id .. " ", highlight = "Comment" },
    { text = node.name, highlight = terms.state(id) == "unseen" and "Function" or "NeoTreeFileName" },
  }
end

M.term_detail = function(_, node)
  if not node.extra.live then
    return node.extra.repl and { text = " not started ", highlight = "NonText" } or {}
  end
  local id = node.extra.term_id
  local hl = terms.state(id) == "failed" and "DiagnosticError" or "Comment"
  return { text = " " .. terms.detail(id) .. " ", highlight = hl }
end

return M
