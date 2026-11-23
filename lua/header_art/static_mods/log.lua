-- The last editor events (writes, LSP attach, cd, terminals, scheme changes):
-- hud_data's ring, real events only, newest first.
local U = require("header_art.static_util")

return {
  id = "log",
  title = "LOG",
  on = { "BufWritePost", "BufReadPost", "LspAttach", "LspDetach", "DirChanged", "TermOpen", "ColorScheme" },
  render = function(w)
    local ev = require("header_art.hud_data").events
    local out = {}
    for i = #ev, math.max(1, #ev - 4), -1 do
      local e = ev[i]
      local verb, rest = e.text:match("^(%S+)%s*(.*)$")
      out[#out + 1] = U.row({
        { os.date("%H:%M", math.floor(e.time)) .. " ", "dim" }, { (verb or ""):sub(1, 7):gsub("$", string.rep(" ", math.max(0, 7 - #(verb or "")))) .. " ", "mid" }, { rest or "", i == #ev and "" or "mid" },
      }, {}, w)
    end
    -- fixed height: a growing log would relayout (and re-render the dashboard) on each of the first events
    while #out < 5 do out[#out + 1] = U.line({}) end
    return out
  end,
}
