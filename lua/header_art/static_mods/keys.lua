-- The dashboard's key hints as keycaps (the keys themselves stay bound by snacks).
local U = require("header_art.static_util")

local DEFAULT = { { "f", "find" }, { "r", "recent" }, { "d", "cd" }, { "R", "repo" }, { "s", "session" }, { "c", "config" }, { "q", "quit" } }

return {
  id = "keys",
  bare = true,
  noflash = true,
  render = function(w)
    local ok, hud = pcall(require, "header_art.hud")
    local keys = vim.deepcopy(ok and hud.config and hud.config.content and hud.config.content.keys or DEFAULT)
    table.insert(keys, #keys, { "1-4", "resume" })
    local segs = {}
    for _, k in ipairs(keys) do
      segs[#segs + 1] = { " " .. k[1] .. " ", "key" }
      segs[#segs + 1] = { " " .. k[2] .. "   ", "dim" }
    end
    return { U.line(segs) }
  end,
}
