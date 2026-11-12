-- Markdown side of lua/pdfview: buffer -> pandoc -> typst -> PDF, previewed
-- live in the same split viewer as LaTeX (the shared machinery -- compile on
-- edit, text-matched sync -- is lua/pdfview/live.lua).
--
--   * pandoc runs in the file's directory so relative images resolve.
--   * pages are shaped to the split (width from its columns, height from its
--     pixel aspect), so text reflows on resize like a browser.
--   * the look is a pandoc typst template from md_styles/: per file, else the
--     saved default, else config.markdown.style (picker: lua/pdfview/md_picker.lua).

local R = require("pdfview.render")
local live = require("pdfview.live")

local function cfg() return require("pdfview").config end

-- GitHub-isms typst can't take (raw HTML, remote images, dead #anchors)
local HERE = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
local FILTER = HERE .. "/pandoc_filter.lua"
local STYLES_DIR = HERE .. "/md_styles"
local store = require("pdfview.store")
local DEFAULT_KEY = "_markdown" -- store entry holding the default style

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

-- Page styles, one md_styles/<name>.typ each, in picker order. All of them
-- are light-theme (the viewer recolours), so they differ by type, weight,
-- rules and spacing, not by colour.
local STYLES = {
  { name = "github", desc = "GitHub's README look: SF, h1/h2 rules, rounded code panels, zebra tables" },
  { name = "book", desc = "Printed page: Iowan Old Style, justified + hyphenated, indents, small caps" },
  { name = "article", desc = "LaTeX article: Libertinus, numbered sections, booktabs tables" },
  { name = "swiss", desc = "Avenir Next, big tight title, sections under heavy rules, flat code" },
  { name = "editorial", desc = "New York headings over SF body, airy, large italic quotes" },
  { name = "terminal", desc = "Iosevka Term Slab throughout, # marks and backticks kept" },
}

local trial = {} ---@type table<integer, string> style being previewed in the picker, per buffer

local function known(name)
  return name and vim.uv.fs_stat(STYLES_DIR .. "/" .. name .. ".typ") ~= nil
end

local function file_key(src)
  local name = vim.api.nvim_buf_get_name(src)
  return name ~= "" and name or nil
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
  command = function(P, src, dir, tmp)
    local images = R.dir .. "/img" -- downloaded remote images, per session
    vim.fn.mkdir(images, "p")
    local pw, ph = page_size()
    P.aspect, P.page_width = ph / pw, pw
    local cmd = {
      "pandoc", "-f", cfg().markdown.from, "--pdf-engine=typst", "--lua-filter=" .. FILTER,
      "--template=" .. STYLES_DIR .. "/" .. M.style(src) .. ".typ", "-V", ("pagewidth=%spt"):format(pw), "-V", ("pageheight=%spt"):format(ph),
      "--resource-path=" .. dir, "-o", tmp,
    }
    vim.list_extend(cmd, cfg().markdown.args)
    return cmd, { env = { PDFVIEW_IMG_CACHE = images } }
  end,
})
M.aspect = nil -- page height/width of the last render
M.styles = STYLES

-- The style `src` renders with, and where it comes from ("trial" | "file" |
-- "default" | "config").
function M.style(src)
  if trial[src] then return trial[src], "trial" end
  local key = file_key(src)
  local s = key and store.get(key, "style")
  if known(s) then return s, "file" end
  s = store.get(DEFAULT_KEY, "style")
  if known(s) then return s, "default" end
  s = cfg().markdown.style
  return known(s) and s or "github", "config"
end

local function rerender(src)
  if M.current() and M.src == src then M.refresh(src) end
end

-- Render `src` with `name` without saving it (nil ends the trial).
function M.try_style(src, name)
  local before = M.style(src)
  trial[src] = name
  if M.style(src) ~= before then rerender(src) end
end

-- Save `name` for `src`'s file (scope "file", the default) or as the default
-- for every Markdown file ("default", which also drops this file's own pick,
-- so it follows the default). name = nil clears the per-file pick.
function M.set_style(src, name, scope)
  if name and not known(name) then
    return vim.notify("Markdown style not found: " .. name, vim.log.levels.ERROR)
  end
  local before = M.style(src)
  trial[src] = nil
  local key = file_key(src)
  if scope == "default" then
    store.set(DEFAULT_KEY, "style", name)
    if key then store.set(key, "style", nil) end
  elseif key then
    store.set(key, "style", name)
  else
    trial[src] = name -- unnamed buffer: nothing to key it on, keep it for the session
  end
  if M.style(src) ~= before then rerender(src) end
end

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
