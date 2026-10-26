-- Dumps the highlight colours the README's theme specimen is drawn from.
-- Run by build.py (`uv run .github/readme/build.py --schemes`) inside a
-- throwaway XDG_STATE_HOME whose ui.json says solid, so Normal keeps its bg.

local groups = { "Normal", "Comment", "Function", "String", "Keyword", "Statement", "Constant", "CursorLine" }
local function hex(n) return n and string.format("#%06x", n) or nil end

local out = {}
for _, spec in ipairs(vim.split(os.getenv("SCHEMES"), ",")) do
  local name, bg = spec:match("([^:]+):?(%a*)")
  vim.g.colors_name = nil
  vim.o.background = bg ~= "" and bg or "dark"
  if pcall(vim.cmd.colorscheme, name) then
    local t = {}
    for _, g in ipairs(groups) do
      local h = vim.api.nvim_get_hl(0, { name = g, link = false })
      t[g] = { fg = hex(h.fg), bg = hex(h.bg) }
    end
    out[#out + 1] = { spec = spec, hl = t }
  end
end

local f = assert(io.open(os.getenv("OUT"), "w"))
f:write(vim.json.encode(out))
f:close()
vim.cmd("qa!")
