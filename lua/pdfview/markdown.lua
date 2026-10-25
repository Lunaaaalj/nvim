-- Markdown side of lua/pdfview: buffer -> pandoc -> typst -> PDF, previewed in
-- the same split viewer as LaTeX.
--
--   * renders from the buffer's text (stdin), so the preview follows edits as
--     you type (debounced), not only on save; pandoc runs in the file's
--     directory so relative images resolve. The PDF is written to a temp file
--     and renamed into place, so the viewer never reads a half-written one.
--   * no SyncTeX here: both directions match text. Forward strips the markup
--     from the cursor line and finds its words in pdftotext's word list;
--     inverse takes the clicked word and its neighbours and finds them in the
--     buffer. Repeated text is settled by relative position in the document.

local V = require("pdfview.viewer")
local R = require("pdfview.render")

local M = {}

M.viewer = nil ---@type table? the preview split's viewer
M.src = nil ---@type integer? the Markdown buffer it shows
M.live = false -- forward-sync on CursorHold
local last ---@type string? "buf:line" last synced
local jobs = {} ---@type table<integer, {busy: boolean, again: boolean}>

local function cfg() return require("pdfview").config end

-- GitHub-isms typst can't take (raw HTML, remote images, dead #anchors), and
-- the template that styles the result like github.com
local HERE = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
local FILTER = HERE .. "/pandoc_filter.lua"
local TEMPLATE = HERE .. "/github_template.typ"

-- The useful part of pandoc/typst stderr: the first few error lines.
local function summary(err)
  local out = {}
  for line in vim.trim(err or ""):gmatch("[^\n]+") do
    if line:lower():find("error") then out[#out + 1] = vim.trim(line) end
    if #out == 3 then break end
  end
  return #out > 0 and table.concat(out, "\n") or (vim.trim(err or ""):match("^[^\n]*") or "failed")
end

local function viewer()
  local v = M.viewer
  if v and vim.api.nvim_buf_is_valid(v.buf) then return v end
end

-- Page size (points) shaped like the preview window, so "fit page" fills it.
-- Before the split exists, estimate it from the configured width.
local function page_size()
  local c = cfg().markdown
  local v = viewer()
  local win = v and v:win()
  local cols = win and vim.api.nvim_win_get_width(win) or math.floor(vim.o.columns * c.width)
  local rows = win and vim.fn.winheight(win) or (vim.o.lines - 4)
  local ok, px = pcall(function() return Snacks.image.terminal.size() end)
  local ratio = ok and (rows * px.cell_height) / (cols * px.cell_width) or 1.3
  local width = math.max(320, math.min(cols * c.column_pt, 1000)) -- tables need some room
  return width, math.floor(width * ratio * 10) / 10
end
M.aspect = nil -- page height/width of the last render

local function pdf_path(src)
  local name = vim.api.nvim_buf_get_name(src)
  return ("%s/md-%s.pdf"):format(R.dir, vim.fn.sha256(name ~= "" and name or tostring(src)):sub(1, 12))
end

local function title(src)
  local name = vim.api.nvim_buf_get_name(src)
  return name ~= "" and vim.fs.basename(name) or "[No Name]"
end

-- Words for matching: lowercase, punctuation stripped (UTF-8 letters kept).
local function norm(w)
  return vim.fn.tolower((w:gsub("[%p]", "")))
end

-- The visible words of one Markdown source line.
local function plain_words(line)
  line = line:gsub("!?%[([^%]]*)%]%b()", "%1") -- links/images -> their text
    :gsub("<[^>]+>", " ") -- inline HTML
    :gsub("^%s*[-+*]%s+%[[ xX]%]", " ") -- task boxes
    :gsub("^%s*[-+*]%s+", " ") -- bullets
    :gsub("^%s*%d+[.)]%s+", " ") -- numbered items
  local out = {}
  for w in line:gmatch("%S+") do
    local n = norm(w)
    if n ~= "" then out[#out + 1] = n end
  end
  return out
end

-- Every occurrence of `query` (normalized words) in `words`, longest prefix
-- of the query that occurs at all (5 words, then fewer). -> list of indices.
local function occurrences(words, query, key)
  for k = math.min(#query, 5), 1, -1 do
    if k == 1 and #query[1] < 4 then break end -- a lone short word matches anywhere
    local hits = {}
    for i = 1, #words - k + 1 do
      local ok = true
      for j = 1, k do
        if key(words[i + j - 1]) ~= query[j] then
          ok = false
          break
        end
      end
      if ok then hits[#hits + 1] = i end
    end
    if #hits > 0 then return hits, k end
  end
  return {}, 0
end

-- The hit whose relative position is closest to `rel` (0..1).
local function nearest(hits, total, rel)
  local best, dist = nil, math.huge
  for _, i in ipairs(hits) do
    local d = math.abs(i / total - rel)
    if d < dist then best, dist = i, d end
  end
  return best
end

-- pdftotext pages -> one flat list of { page, x0, y0, x1, y1, word }. Words
-- that normalize to nothing ("%", "—") are dropped, as on the source side, so
-- the two word streams line up.
local function flatten(pages)
  local flat = {}
  for p, words in ipairs(pages) do
    for _, w in ipairs(words) do
      local n = norm(w[5])
      if n ~= "" then flat[#flat + 1] = { p, w[1], w[2], w[3], w[4], n } end
    end
  end
  return flat
end

-- Forward search: highlight source line l1 (or l1..l2) of `win` on the page.
function M.sync(v, win, l1, l2)
  local buf = vim.api.nvim_win_get_buf(win)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  l1 = l1 or vim.api.nvim_win_get_cursor(win)[1]
  l2 = l2 or l1
  last = buf .. ":" .. l1
  -- the words of the range; blank/markup-only lines borrow from the next ones
  local query, l = {}, l1
  while #query < 5 and l <= math.max(l2, l1 + 6) and l <= #lines do
    if l <= l2 or #query == 0 then vim.list_extend(query, plain_words(lines[l])) end
    l = l + 1
  end
  local nwords = 0
  for i = l1, l2 do nwords = nwords + #plain_words(lines[i] or "") end
  if #query == 0 then return end
  R.text(v.pdf, R.mtime(v.pdf) or "", function(pages)
    if not pages then return end
    local flat = flatten(pages)
    local hits = occurrences(flat, query, function(w) return w[6] end)
    local i = nearest(hits, #flat, (l1 - 1) / math.max(#lines, 1))
    if not i then return end
    local page, boxes = flat[i][1], {}
    for j = i, math.min(#flat, i + math.max(nwords, 1) - 1) do
      local w = flat[j]
      if w[1] ~= page then break end
      local b = boxes[#boxes]
      if b and math.abs(b[2] - w[3]) < 2 then -- same line: extend
        b[3], b[4] = math.max(b[3], w[4]), math.max(b[4], w[5])
      else
        boxes[#boxes + 1] = { w[2], w[3], w[4], w[5] }
      end
    end
    v.sync_marks = { page = page, boxes = boxes }
    v:reveal(page, boxes[1][2], boxes[#boxes][4])
    v:winbar()
    v:render()
  end)
end

-- Inverse search: the words around page point (x, y) -> source line.
function M.inverse(v, page, x, y)
  R.text(v.pdf, R.mtime(v.pdf) or "", function(pages)
    local words = pages and pages[page]
    if not words or #words == 0 then return end
    -- the word under the point, else the closest one
    local hit, dist = nil, math.huge
    for i, w in ipairs(words) do
      local dx = x < w[1] and w[1] - x or x > w[3] and x - w[3] or 0
      local dy = y < w[2] and w[2] - y or y > w[4] and y - w[4] or 0
      local d = dx * dx + dy * dy * 4 -- prefer the same line
      if d < dist then hit, dist = i, d end
    end
    local before = 0
    for p = 1, page - 1 do before = before + #pages[p] end
    local total = before
    for p = page, #pages do total = total + #pages[p] end
    local query = {}
    for i = hit, math.min(#words, hit + 4) do
      local n = norm(words[i][5])
      if n ~= "" then query[#query + 1] = n end
    end
    -- the source as one word stream, remembering each word's line
    local src = M.src
    if not (src and vim.api.nvim_buf_is_valid(src)) then return end
    local stream = {}
    for lnum, line in ipairs(vim.api.nvim_buf_get_lines(src, 0, -1, false)) do
      for _, w in ipairs(plain_words(line)) do stream[#stream + 1] = { w, lnum } end
    end
    local hits = occurrences(stream, query, function(s) return s[1] end)
    local i = nearest(hits, #stream, (before + hit) / math.max(total, 1))
    if not i then return V.notify("Couldn't place that text in the source", vim.log.levels.INFO) end
    M.jump(v, src, stream[i][2])
  end)
end

function M.jump(v, src, line)
  if v.float then v:toggle_float() end
  local win = v.src_win
  if not (win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == src) then
    win = vim.fn.bufwinid(src)
    if win == -1 then
      vim.api.nvim_set_current_win(v:win())
      vim.cmd("leftabove vsplit")
      win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(win, src)
    end
  end
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_cursor(win, { math.min(line, vim.api.nvim_buf_line_count(src)), 0 })
  vim.cmd("normal! zz")
  vim.hl.range(src, vim.api.nvim_create_namespace("pdfview"), "IncSearch", { line - 1, 0 }, { line - 1, -1 }, { timeout = 600 })
  v.src_win = win
  M.sync(v, win)
end

-- Render `src` to its PDF; cb(ok, stderr). Coalesces while a run is going.
function M.compile(src, cb)
  local job = jobs[src] or {}
  jobs[src] = job
  if job.busy then
    job.again = true
    return
  end
  job.busy = true
  local name = vim.api.nvim_buf_get_name(src)
  local dir = name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
  local out = pdf_path(src)
  local tmp = out:gsub("%.pdf$", ".tmp.pdf")
  local images = R.dir .. "/img" -- downloaded remote images, per session
  vim.fn.mkdir(images, "p")
  local pw, ph = page_size()
  M.aspect, M.page_width = ph / pw, pw
  local cmd = {
    "pandoc", "-f", cfg().markdown.from, "--pdf-engine=typst", "--lua-filter=" .. FILTER,
    "--template=" .. TEMPLATE, "-V", ("pagewidth=%spt"):format(pw), "-V", ("pageheight=%spt"):format(ph),
    "--resource-path=" .. dir, "-o", tmp,
  }
  vim.list_extend(cmd, cfg().markdown.args)
  vim.system(cmd, {
    stdin = table.concat(vim.api.nvim_buf_get_lines(src, 0, -1, false), "\n"),
    cwd = dir,
    env = { PDFVIEW_IMG_CACHE = images },
    text = true,
  }, vim.schedule_wrap(function(res)
    if res.code == 0 then os.rename(tmp, out) end
    job.busy = false
    cb(res.code == 0, res.stderr or "")
    if job.again then
      job.again = false
      M.compile(src, cb)
    end
  end))
end

-- Recompile `src` and refresh the preview, if it is the one being shown.
local function refresh(src)
  local v = viewer()
  if not (v and M.src == src) then return end
  v.status = { kind = "busy", text = "rendering" }
  v:winbar()
  M.compile(src, function(ok, err)
    if not (viewer() and M.src == src) then return end
    if ok then
      v.status = nil
      local w = v.src_win
      if cfg().follow and w and vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_buf(w) == src then
        M.sync(v, w)
      else
        v:winbar()
        v:render()
      end
    else
      v.status = { kind = "error", text = summary(err):match("^[^\n]*"):sub(1, 80) }
      v:winbar()
    end
  end)
end

local function watch(src)
  if vim.b[src].pdfview_md then return end
  vim.b[src].pdfview_md = true
  local timer = assert(vim.uv.new_timer())
  local group = vim.api.nvim_create_augroup("pdfview.md." .. src, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
    group = group,
    buffer = src,
    callback = function()
      timer:start(cfg().markdown.delay, 0, vim.schedule_wrap(function() refresh(src) end))
    end,
  })
  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    buffer = src,
    callback = function()
      local v = viewer()
      if not (M.live and v and M.src == src and v:win()) then return end
      local win = vim.api.nvim_get_current_win()
      if last ~= src .. ":" .. vim.api.nvim_win_get_cursor(win)[1] then
        v.src_win = win
        M.sync(v, win)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = src,
    once = true,
    callback = function()
      timer:close()
      jobs[src] = nil
      os.remove(pdf_path(src))
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
end

-- A resized split needs pages of the new shape (typst is fast enough to just
-- re-render).
local resize_timer = assert(vim.uv.new_timer())
vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
  group = vim.api.nvim_create_augroup("pdfview.md", { clear = true }),
  callback = function()
    local v = viewer()
    if not (v and v:win() and M.src and M.aspect) then return end
    resize_timer:start(250, 0, vim.schedule_wrap(function()
      if not (viewer() and v:win() and M.src and vim.api.nvim_buf_is_valid(M.src)) then return end
      local pw, ph = page_size()
      if pw ~= M.page_width or math.abs(ph / pw - M.aspect) / M.aspect > 0.01 then refresh(M.src) end
    end))
  end,
})

function M.supported()
  return require("pdfview").supported() and vim.fn.executable("pandoc") == 1 and vim.fn.executable("typst") == 1
end

-- Open (or refresh) the preview of the current Markdown buffer and sync it to
-- the cursor (or, from visual mode, the selected lines).
function M.view()
  local l1, l2
  if vim.fn.mode():find("^[vV\22]") then
    l1, l2 = vim.fn.line("v"), vim.fn.line(".")
    if l1 > l2 then l1, l2 = l2, l1 end
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  end
  local src, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  if not M.supported() then
    if vim.fn.executable("pandoc") == 0 or vim.fn.executable("typst") == 0 then
      return V.notify("Markdown preview needs pandoc and typst (brew install pandoc typst)")
    end
    -- no graphics terminal: render and hand the PDF to the system viewer
    return M.compile(src, function(ok, err)
      if ok then vim.ui.open(pdf_path(src)) else V.notify("Markdown preview failed:\n" .. summary(err)) end
    end)
  end
  watch(src)
  local pdf = pdf_path(src)
  local name = vim.api.nvim_buf_get_name(src)
  local key = name ~= "" and name or nil
  local v = viewer()
  if v then
    if v.pdf ~= pdf or M.src ~= src then v:set_pdf(pdf, title(src), key) end
  else
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    pcall(vim.api.nvim_buf_set_name, buf, "pdfview://" .. title(src))
    v = V.new(buf, pdf, "md", { integration = M, inverse = M.inverse, title = title(src), store_key = key })
    M.viewer = v
  end
  M.src, v.src_win = src, win
  -- open the split first: the page is shaped to it
  if not v:win() then v:open_split(cfg().markdown.width) end
  v.status = { kind = "busy", text = "rendering" }
  v:winbar()
  M.compile(src, function(ok, err)
    if not (viewer() == v and M.src == src) then return end
    if not ok then
      v.status = { kind = "error", text = summary(err):match("^[^\n]*"):sub(1, 80) }
      v:winbar()
      return V.notify("Markdown preview failed:\n" .. summary(err))
    end
    v.status = nil
    v:render()
    M.sync(v, win, l1, l2)
  end)
end

function M.toggle_live()
  M.live = not M.live
  last = nil
  local v = viewer()
  if v then v:winbar() end
  V.notify("Live follow " .. (M.live and "on" or "off"), vim.log.levels.INFO)
end

return M
