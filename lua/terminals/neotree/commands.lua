local cc = require("neo-tree.sources.common.commands")
local manager = require("neo-tree.sources.manager")
local terms = require("terminals")

-- Inherit navigation/selection/help commands. The filesystem-mutating ones are
-- no-ops: terminal nodes carry a fake `term://` path.
local M = vim.tbl_extend("force", {}, cc)

for _, name in ipairs({
  "add_directory", "copy", "move", "trash", "copy_to_clipboard", "cut_to_clipboard",
  "paste_from_clipboard", "toggle_preview", "focus_preview", "set_root", "navigate_up",
}) do
  M[name] = function() end
end

M.refresh = function()
  manager.refresh("terminals")
end

--- Run `fn(id, node)` for the terminal under the cursor; REPLs that aren't
--- running only accept `open` (which starts them).
local function on_term(fn, needs_live)
  return function(state)
    local node = state.tree:get_node()
    if not node then return end
    if node.type == "directory" then return cc.toggle_node(state) end
    if node.type == "new_shell" then return terms.new() end
    if node.type ~= "terminal" then return end
    if needs_live and not node.extra.live then
      return vim.notify("Not running", vim.log.levels.INFO)
    end
    fn(node.extra.term_id, node)
  end
end

M.open = on_term(function(id) terms.open(id) end)
M.open_float = on_term(function(id) terms.open(id, "float") end)
M.open_vsplit = on_term(function(id) terms.open(id, "vertical") end)
M.open_split = on_term(function(id) terms.open(id, "horizontal") end)
M.open_tabnew = on_term(function(id) terms.open(id, "tab") end)
M.open_with_window_picker = M.open

M.new_shell = function()
  terms.new()
end
M.add = M.new_shell

M.kill = on_term(function(id) terms.kill(id) end, true)
M.delete = M.kill
M.rename = on_term(function(id) terms.rename(id) end, true)
M.quickfix = on_term(function(id) terms.quickfix(id) end, true)
M.repeat_last = on_term(function(id) terms.repeat_last(id) end, true)

return M
