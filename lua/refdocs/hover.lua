-- hover.nvim provider: the reference page for the symbol under the cursor,
-- right after LSP (priority 1000) so K shows LSP and <C-n> the reference.
local R = require("refdocs")

--- @type Hover.Provider
return {
  name = "Ref",
  priority = 999,
  enabled = function(bufnr)
    local lang = R.lang_at(bufnr)
    return lang ~= nil and require("refdocs.backends")[lang].available()
  end,
  execute = function(params, done)
    local lang, topics, ctx = R.topics_at(params.bufnr)
    if not topics then return done() end
    local width = math.max(40, math.min(84, vim.o.columns - 12))
    R.fetch_first(lang, topics, width, ctx, function(lines)
      done(lines and { lines = lines, filetype = "man" })
    end)
  end,
}
