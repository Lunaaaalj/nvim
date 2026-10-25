-- Neo-tree source: a "Terminals" tab listing live shells and the pinned REPLs.
--
--   + New shell
--   ▾ Shells
--        1 nvim             ~/.config/nvim
--        2 pytest     pytest -x  12s
--        3 api               exit 1
--   ▾ REPLs
--        python
--        node              (not started)
--
-- Data and actions come from lua/terminals; this file only builds nodes.

local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local events = require("neo-tree.events")
local utils = require("neo-tree.utils")
local terms = require("terminals")

---@class neotree.sources.Terminals : neotree.Source
-- No display_name: the tab label lives in lua/neotree_tabs.lua.
local M = {
  name = "terminals",
}

local function term_node(id, name, extra)
  return {
    id = "term:" .. id,
    name = name,
    type = "terminal",
    path = "term://" .. id, -- components key off `path`; keep it unique
    extra = vim.tbl_extend("force", { term_id = id }, extra or {}),
  }
end

local function group(id, name, children)
  return { id = id, name = name, type = "directory", path = "terms#" .. id, loaded = true, children = children }
end

---@param state neotree.State
M.navigate = function(state, path, path_to_reveal, callback)
  state.dirty = false
  state.path = path or state.path or vim.fn.getcwd()

  local live, shells = {}, {}
  for _, t in ipairs(terms.list()) do
    live[t.id] = true
    if terms.info(t.id).kind == "shell" then
      shells[#shells + 1] = term_node(t.id, terms.label(t.id), { live = true })
    end
  end

  local repls = {}
  for _, r in ipairs(terms.repls) do
    repls[#repls + 1] = term_node(r.id, r.key, { live = live[r.id], repl = r.key })
  end

  local items = { { id = "new_shell", name = "New shell", type = "new_shell", path = "terms#new" } }
  if #shells > 0 then
    items[#items + 1] = group("shells", "Shells", shells)
  else
    items[#items + 1] = { id = "empty", name = "No shells open", type = "message", path = "terms#empty" }
  end
  items[#items + 1] = group("repls", "REPLs", repls)

  state.default_expanded_nodes = { "shells", "repls" }
  if path_to_reveal then
    renderer.position.set(state, path_to_reveal)
  end
  renderer.show_nodes(items, state)
  if type(callback) == "function" then
    vim.schedule(callback)
  end
end

M.setup = function(config, global_config)
  local refresh = function()
    utils.debounce("terminals_refresh", function()
      manager.refresh(M.name)
    end, 150, utils.debounce_strategy.CALL_LAST_ONLY)
  end
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("NeoTreeTerminals", { clear = true }),
    pattern = "TermsChanged",
    callback = refresh,
  })
  manager.subscribe(M.name, { event = events.VIM_BUFFER_DELETED, handler = refresh })
end

M.default_config = {
  renderers = {
    new_shell = {
      { "indent" },
      { "term_icon" },
      { "name", highlight = "Special" },
    },
    directory = {
      { "indent" },
      { "icon" },
      { "name" },
    },
    terminal = {
      { "indent" },
      { "term_icon" },
      {
        "container",
        content = {
          { "term_name", zindex = 10 },
          { "term_detail", zindex = 20, align = "right" },
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
      ["a"] = "new_shell",
      ["n"] = "new_shell",
      ["d"] = "kill",
      ["r"] = "rename",
      ["f"] = "open_float",
      ["x"] = "quickfix",
      ["."] = "repeat_last",
      ["R"] = "refresh",
    },
  },
}

return M
