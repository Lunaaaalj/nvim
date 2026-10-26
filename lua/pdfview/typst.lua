-- Typst side of lua/pdfview: buffer -> `typst compile` -> PDF, previewed live
-- in the same split viewer as LaTeX (the shared machinery -- compile on edit,
-- text-matched sync -- is lua/pdfview/live.lua).
--
--   * the buffer goes in on stdin with cwd = the file's directory. typst puts
--     stdin at the project root, which defaults to the cwd, so relative
--     imports/images resolve exactly as with `typst compile file.typ`.
--   * the document sets its own page size, so (like LaTeX, unlike Markdown)
--     the split is sized to the page instead of the page to the split.
--   * no SyncTeX for typst: sync matches text, as for Markdown.

local V = require("pdfview.viewer")
local live = require("pdfview.live")

local function cfg() return require("pdfview").config end

-- Lines that only configure the document (`#set text(...)`, `#show: ...`,
-- `#let`, `#import`) put no text where they stand.
local silent = { set = true, show = true, let = true, import = true, include = true }

-- The visible words of one Typst source line.
local function plain_words(line)
  local kw = line:match("^%s*#(%a+)")
  if kw and silent[kw] then return {} end
  line = line:gsub("^%s*//.*", "") -- comments (not the // of a URL)
    :gsub("%s//.*", "")
    :gsub("%$[^$]*%$", " ") -- inline math: pdftotext garbles it
    :gsub("^%s*=+%s+", " ") -- headings
    :gsub("^%s*[-+]%s+", " ") -- bullets / numbered items
    :gsub("^%s*/%s+([^:]*):", "%1") -- term lists
    :gsub("<[%w_%-%.:]+>", " ") -- labels
    :gsub("@[%w_%-%.:]+", " ") -- references (rendered as "Figure 2" etc.)
    :gsub("#[%a_][%w_%-%.]*%b()", " ") -- #func(args)[body] -> [body]
    :gsub("#[%a_][%w_%-%.]*", " ")
  local out = {}
  for w in line:gmatch("%S+") do
    local n = live.norm(w)
    if n ~= "" then out[#out + 1] = n end
  end
  return out
end

local M
M = live.new({
  kind = "typst",
  name = "Typst",
  config = function() return cfg().typst end,
  words = plain_words,
  missing = function()
    if vim.fn.executable("typst") == 0 then return "Typst preview needs the typst CLI (brew install typst)" end
  end,
  command = function(_, _, _, tmp)
    local cmd = { "typst", "compile", "--diagnostic-format", "short" }
    vim.list_extend(cmd, cfg().typst.args)
    vim.list_extend(cmd, { "-", tmp })
    return cmd
  end,
})

-- The preview renders into the cache; these produce the real foo.pdf next to
-- foo.typ (what tinymist's exportPdf = "onSave" also writes).
local function export(buf, cb)
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then return V.notify("Save the file first") end
  local cmd = { "typst", "compile", "--diagnostic-format", "short" }
  vim.list_extend(cmd, cfg().typst.args)
  table.insert(cmd, file)
  vim.system(cmd, { cwd = vim.fs.dirname(file), text = true }, vim.schedule_wrap(function(res)
    if res.code ~= 0 then return V.notify("typst compile failed:\n" .. live.summary(res.stderr)) end
    cb(file:gsub("%.typ$", "") .. ".pdf")
  end))
end

-- Compile the saved file once to foo.pdf.
function M.compile_file()
  vim.cmd("silent! update")
  export(vim.api.nvim_get_current_buf(), function(pdf)
    V.notify("Wrote " .. vim.fn.fnamemodify(pdf, ":~:."), vim.log.levels.INFO)
  end)
end

-- Compile once and open foo.pdf in the system viewer (Skim reloads it when
-- the file changes, e.g. on every save with tinymist's exportPdf).
function M.open_external()
  vim.cmd("silent! update")
  export(vim.api.nvim_get_current_buf(), vim.ui.open)
end

-- Close the preview split; edits stop recompiling once no viewer shows them.
function M.stop()
  local v = M.current()
  if v then v:close() end
end

return M
