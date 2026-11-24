-- Editor state from hud_data's 1 s sample: LSP clients, diagnostics, buffers
-- and startup. Updates every 5 s and on LSP attach.
local U = require("header_art.static_util")

return {
  id = "editor",
  title = "EDITOR",
  badge = "6",
  every = 5,
  on = { "LspAttach", "LspDetach", "BufAdd", "BufDelete" },
  render = function(w)
    local D = require("header_art.hud_data").sample()
    local function kv(k, segs) return U.line(vim.list_extend({ { k, "dim" } }, segs)) end
    local names = {}
    for _, c in ipairs(D.clients or {}) do names[#names + 1] = c.name end
    local modified = 0
    for _, b in ipairs(D.buflist or {}) do if b.modified then modified = modified + 1 end end
    return {
      kv("lsp    ", { { #names > 0 and table.concat(names, "  ") or "none", #names > 0 and "" or "dim" } }),
      kv("bufs   ", { { (D.bufs or 0) .. " listed" }, { modified > 0 and (" · " .. modified .. " modified") or "", "warn" } }),
      kv("start  ", { { D.startup and (math.floor(D.startup + 0.5) .. " ms · " .. (D.plugins or 0) .. " plugins") or "?" } }),
      kv("memory ", { { (D.mem and math.floor(D.mem) or 0) .. " MiB" } }),
    }
  end,
}
