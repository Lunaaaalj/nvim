-- Quarto side of lua/pdfview: buffer -> `quarto render --to typst` -> PDF,
-- previewed live in the same kitty split as LaTeX/Typst/Markdown (the shared
-- machinery is lua/pdfview/live.lua). Issue #40, phase 5.
--
--   * quarto can't read stdin, so the buffer is written to a hidden
--     `.<name>.nvim-preview.qmd` beside the file (relative images, includes
--     and _quarto.yml resolve as for the real file) and removed afterwards,
--     with any `_files` dir quarto made for it. The PDF goes to the cache.
--   * nothing is executed: `-M engine:markdown` shows code chunks as code
--     (`--no-execute` alone still ran R chunks through knitr). Results live
--     in Molten's output, not in this layout preview.
--   * quarto's typst output sets its page size, so the split fits the page,
--     as for LaTeX and Typst.

local live = require("pdfview.live")

local function cfg() return require("pdfview").config end

-- The visible words of one Quarto/Markdown source line.
local function plain_words(line)
  if line:match("^%s*```") or line:match("^%s*:::") or line:match("^%s*<!%-%-") then return {} end
  line = line:gsub("^%s*#+%s+", " ") -- headings
    :gsub("%b{}", " ") -- attributes {#sec-x .class}
    :gsub("!?%[([^%]]*)%]%b()", "%1") -- links/images -> their text
    :gsub("@[%w_%-%.:]+", " ") -- cross-references (rendered as "Figure 1")
    :gsub("<[^>]+>", " ")
    :gsub("^%s*[-+*]%s+", " ")
    :gsub("^%s*%d+[.)]%s+", " ")
  local out = {}
  for w in line:gmatch("%S+") do
    local n = live.norm(w)
    if n ~= "" then out[#out + 1] = n end
  end
  return out
end

-- stdin -> temp .qmd -> quarto -> $out; always cleans up the temp files.
local SCRIPT = [[
tmpq="$1"; outdir="$2"; out="$3"; shift 3
trap 'rm -f "$tmpq"; rm -rf "${tmpq%.qmd}_files"' EXIT
cat > "$tmpq"
quarto render "$tmpq" --to typst --no-execute -M engine:markdown --output-dir "$outdir" --quiet "$@" || exit 1
base=$(basename "$tmpq" .qmd)
mv "$outdir/$base.pdf" "$out"
]]

local M
M = live.new({
  kind = "quarto",
  name = "Quarto",
  config = function() return cfg().quarto end,
  words = plain_words,
  missing = function()
    if vim.fn.executable("quarto") == 0 then return "Quarto preview needs the quarto CLI (brew install quarto)" end
  end,
  command = function(_, src, dir, tmp)
    local name = vim.api.nvim_buf_get_name(src)
    local base = name ~= "" and vim.fn.fnamemodify(name, ":t:r") or "untitled"
    local tmpq = ("%s/.%s.nvim-preview.qmd"):format(dir, base)
    local outdir = vim.fs.dirname(tmp) .. "/quarto-out"
    vim.fn.mkdir(outdir, "p")
    local cmd = { "sh", "-c", SCRIPT, "sh", tmpq, outdir, tmp }
    vim.list_extend(cmd, cfg().quarto.args)
    return cmd
  end,
})

function M.stop()
  local v = M.current()
  if v then v:close() end
end

return M
