-- Markdown side of lua/pdfview: buffer -> pandoc -> typst -> PDF, previewed
-- live in the same split viewer as LaTeX (the shared machinery -- compile on
-- edit, text-matched sync -- is lua/pdfview/live.lua).
--
--   * pandoc runs in the file's directory so relative images resolve.
--   * pages are shaped to the split (width from its columns, height from its
--     pixel aspect), so text reflows on resize like a browser.

local R = require("pdfview.render")
local live = require("pdfview.live")

local function cfg() return require("pdfview").config end

-- GitHub-isms typst can't take (raw HTML, remote images, dead #anchors), and
-- the template that styles the result like github.com
local HERE = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
local FILTER = HERE .. "/pandoc_filter.lua"
local TEMPLATE = HERE .. "/github_template.typ"

-- The visible words of one Markdown source line.
local function plain_words(line)
  line = line:gsub("!?%[([^%]]*)%]%b()", "%1") -- links/images -> their text
    :gsub("<[^>]+>", " ") -- inline HTML
    :gsub("^%s*[-+*]%s+%[[ xX]%]", " ") -- task boxes
    :gsub("^%s*[-+*]%s+", " ") -- bullets
    :gsub("^%s*%d+[.)]%s+", " ") -- numbered items
  local out = {}
  for w in line:gmatch("%S+") do
    local n = live.norm(w)
    if n ~= "" then out[#out + 1] = n end
  end
  return out
end

local M

-- Page size (points) shaped like the preview window, so "fit page" fills it.
-- Before the split exists, estimate it from the configured width.
local function page_size()
  local c = cfg().markdown
  local v = M.current()
  local win = v and v:win()
  local cols = win and vim.api.nvim_win_get_width(win) or math.floor(vim.o.columns * c.width)
  local rows = win and vim.fn.winheight(win) or (vim.o.lines - 4)
  local ok, px = pcall(function() return Snacks.image.terminal.size() end)
  local ratio = ok and (rows * px.cell_height) / (cols * px.cell_width) or 1.3
  local width = math.max(320, math.min(cols * c.column_pt, 1000)) -- tables need some room
  return width, math.floor(width * ratio * 10) / 10
end

M = live.new({
  kind = "md",
  name = "Markdown",
  config = function() return cfg().markdown end,
  words = plain_words,
  missing = function()
    if vim.fn.executable("pandoc") == 0 or vim.fn.executable("typst") == 0 then
      return "Markdown preview needs pandoc and typst (brew install pandoc typst)"
    end
  end,
  command = function(P, _, dir, tmp)
    local images = R.dir .. "/img" -- downloaded remote images, per session
    vim.fn.mkdir(images, "p")
    local pw, ph = page_size()
    P.aspect, P.page_width = ph / pw, pw
    local cmd = {
      "pandoc", "-f", cfg().markdown.from, "--pdf-engine=typst", "--lua-filter=" .. FILTER,
      "--template=" .. TEMPLATE, "-V", ("pagewidth=%spt"):format(pw), "-V", ("pageheight=%spt"):format(ph),
      "--resource-path=" .. dir, "-o", tmp,
    }
    vim.list_extend(cmd, cfg().markdown.args)
    return cmd, { env = { PDFVIEW_IMG_CACHE = images } }
  end,
})
M.aspect = nil -- page height/width of the last render

-- A resized split needs pages of the new shape (typst is fast enough to just
-- re-render).
local resize_timer = assert(vim.uv.new_timer())
vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
  group = vim.api.nvim_create_augroup("pdfview.md", { clear = true }),
  callback = function()
    local v = M.current()
    if not (v and v:win() and M.src and M.aspect) then return end
    resize_timer:start(250, 0, vim.schedule_wrap(function()
      if not (M.current() and v:win() and M.src and vim.api.nvim_buf_is_valid(M.src)) then return end
      local pw, ph = page_size()
      if pw ~= M.page_width or math.abs(ph / pw - M.aspect) / M.aspect > 0.01 then M.refresh(M.src) end
    end))
  end,
})

return M
