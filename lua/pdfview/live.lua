-- Live previews of a buffer compiled to PDF on every edit, shown in the same
-- split viewer as LaTeX. Shared by the Markdown (pandoc -> typst) and Typst
-- previews; each backend only says how to compile and what text a source line
-- shows (lua/pdfview/markdown.lua, lua/pdfview/typst.lua).
--
--   * compiles from the buffer's text (stdin), so the preview follows edits as
--     you type (debounced), not only on save. The PDF is written to a temp file
--     and renamed into place, so the viewer never reads a half-written one.
--   * no SyncTeX: both directions match text. Forward takes the visible words
--     of the cursor line and finds them in pdftotext's word list; inverse takes
--     the clicked word and its neighbours and finds them in the buffer.
--     Repeated text is settled by relative position in the document.

local V = require("pdfview.viewer")
local R = require("pdfview.render")

local L = {}

-- The useful part of a compiler's stderr: the first few error lines.
function L.summary(err)
  local out = {}
  for line in vim.trim(err or ""):gmatch("[^\n]+") do
    if line:lower():find("error") then out[#out + 1] = vim.trim(line) end
    if #out == 3 then break end
  end
  return #out > 0 and table.concat(out, "\n") or (vim.trim(err or ""):match("^[^\n]*") or "failed")
end

-- Words for matching: lowercase, punctuation stripped (UTF-8 letters kept).
function L.norm(w)
  return vim.fn.tolower((w:gsub("[%p]", "")))
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
      local n = L.norm(w[5])
      if n ~= "" then flat[#flat + 1] = { p, w[1], w[2], w[3], w[4], n } end
    end
  end
  return flat
end

-- A preview for one kind of source. `spec`:
--   kind     viewer kind ("md" | "typst")
--   name     shown in messages ("Markdown")
--   config   fun(): the backend's config table ({ delay, width, ... })
--   words    fun(line): the visible, normalized words of a source line
--   command  fun(P, src, dir, tmp): argv and extra vim.system opts that write
--            the PDF of `src` to `tmp` (stdin and cwd are filled in)
--   missing  fun(): message when a tool is missing, else nil
---@return table P with view/toggle_live/sync/inverse/refresh/compile/pdf_path
function L.new(spec)
  local P = { words = spec.words }
  P.viewer = nil ---@type table? the preview split's viewer
  P.src = nil ---@type integer? the buffer it shows
  P.live = false -- forward-sync on CursorHold
  local last ---@type string? "buf:line" last synced
  local jobs = {} ---@type table<integer, {busy: boolean, again: boolean}>

  local function cfg() return require("pdfview").config end

  function P.current()
    local v = P.viewer
    if v and vim.api.nvim_buf_is_valid(v.buf) then return v end
  end

  function P.pdf_path(src)
    local name = vim.api.nvim_buf_get_name(src)
    return ("%s/%s-%s.pdf"):format(R.dir, spec.kind, vim.fn.sha256(name ~= "" and name or tostring(src)):sub(1, 12))
  end

  local function title(src)
    local name = vim.api.nvim_buf_get_name(src)
    return name ~= "" and vim.fs.basename(name) or "[No Name]"
  end

  local function fail(v, err)
    v.status = { kind = "error", text = L.summary(err):match("^[^\n]*"):sub(1, 80) }
    v:winbar()
  end

  -- Forward search: highlight source line l1 (or l1..l2) of `win` on the page.
  function P.sync(v, win, l1, l2)
    local buf = vim.api.nvim_win_get_buf(win)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    l1 = l1 or vim.api.nvim_win_get_cursor(win)[1]
    l2 = l2 or l1
    last = buf .. ":" .. l1
    -- the words of the range; blank/markup-only lines borrow from the next ones
    local query, l = {}, l1
    while #query < 5 and l <= math.max(l2, l1 + 6) and l <= #lines do
      if l <= l2 or #query == 0 then vim.list_extend(query, spec.words(lines[l])) end
      l = l + 1
    end
    local nwords = 0
    for i = l1, l2 do nwords = nwords + #spec.words(lines[i] or "") end
    -- whatever happens, show the current PDF: after a recompile this is the
    -- only render, so bailing out on an unplaceable line (`#set ...`, half a
    -- word, math) would leave the old page up
    local function unplaced()
      v.sync_marks = nil
      v:winbar()
      v:render()
    end
    if #query == 0 then return unplaced() end
    v:warm() -- rasterise the visible pages while pdftotext runs
    R.text(v.pdf, R.mtime(v.pdf) or "", function(pages)
      if not pages then return unplaced() end
      local flat = flatten(pages)
      local hits = occurrences(flat, query, function(w) return w[6] end)
      local i = nearest(hits, #flat, (l1 - 1) / math.max(#lines, 1))
      if not i then return unplaced() end
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

  function P.jump(v, src, line)
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
    P.sync(v, win)
  end

  -- Inverse search: the words around page point (x, y) -> source line.
  function P.inverse(v, page, x, y)
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
        local n = L.norm(words[i][5])
        if n ~= "" then query[#query + 1] = n end
      end
      -- the source as one word stream, remembering each word's line
      local src = P.src
      if not (src and vim.api.nvim_buf_is_valid(src)) then return end
      local stream = {}
      for lnum, line in ipairs(vim.api.nvim_buf_get_lines(src, 0, -1, false)) do
        for _, w in ipairs(spec.words(line)) do stream[#stream + 1] = { w, lnum } end
      end
      local hits = occurrences(stream, query, function(s) return s[1] end)
      local i = nearest(hits, #stream, (before + hit) / math.max(total, 1))
      if not i then return V.notify("Couldn't place that text in the source", vim.log.levels.INFO) end
      P.jump(v, src, stream[i][2])
    end)
  end

  -- Compile `src` to its PDF; cb(ok, stderr). Coalesces while a run is going.
  function P.compile(src, cb)
    local job = jobs[src] or {}
    jobs[src] = job
    if job.busy then
      job.again = true
      return
    end
    job.busy = true
    local name = vim.api.nvim_buf_get_name(src)
    local dir = name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
    local out = P.pdf_path(src)
    local tmp = out:gsub("%.pdf$", ".tmp.pdf")
    vim.fn.mkdir(R.dir, "p")
    local cmd, opts = spec.command(P, src, dir, tmp)
    opts = vim.tbl_extend("force", {
      stdin = table.concat(vim.api.nvim_buf_get_lines(src, 0, -1, false), "\n"),
      cwd = dir,
      text = true,
    }, opts or {})
    vim.system(cmd, opts, vim.schedule_wrap(function(res)
      if res.code == 0 then os.rename(tmp, out) end
      job.busy = false
      cb(res.code == 0, res.stderr or "")
      if job.again then
        job.again = false
        P.compile(src, cb)
      end
    end))
  end

  -- Recompile `src` and refresh the preview, if it is the one being shown.
  function P.refresh(src)
    local v = P.current()
    if not (v and P.src == src) then return end
    v.status = { kind = "busy", text = "rendering" }
    v:winbar()
    P.compile(src, function(ok, err)
      if not (P.current() and P.src == src) then return end
      if not ok then return fail(v, err) end
      v.status = nil
      local w = v.src_win
      if cfg().follow and w and vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_buf(w) == src then
        P.sync(v, w)
      else
        v:winbar()
        v:render()
      end
    end)
  end

  local function watch(src)
    local flag = "pdfview_" .. spec.kind
    if vim.b[src][flag] then return end
    vim.b[src][flag] = true
    local timer = assert(vim.uv.new_timer())
    local group = vim.api.nvim_create_augroup(("pdfview.%s.%d"):format(spec.kind, src), { clear = true })
    -- A throttle, not a debounce: the first edit schedules a refresh and later
    -- ones ride along (it reads the buffer when it fires), so the preview keeps
    -- up while you type instead of waiting for a pause. Compile and render
    -- each coalesce, so a slow run never queues a backlog.
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
      group = group,
      buffer = src,
      callback = function()
        if timer:is_active() then return end
        timer:start(spec.config().delay, 0, vim.schedule_wrap(function() P.refresh(src) end))
      end,
    })
    vim.api.nvim_create_autocmd("CursorHold", {
      group = group,
      buffer = src,
      callback = function()
        local v = P.current()
        if not (P.live and v and P.src == src and v:win()) then return end
        local win = vim.api.nvim_get_current_win()
        if last ~= src .. ":" .. vim.api.nvim_win_get_cursor(win)[1] then
          v.src_win = win
          P.sync(v, win)
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
        os.remove(P.pdf_path(src))
        pcall(vim.api.nvim_del_augroup_by_id, group)
      end,
    })
  end

  function P.supported()
    return require("pdfview").supported() and spec.missing() == nil
  end

  -- Open (or refresh) the preview of the current buffer and sync it to the
  -- cursor (or, from visual mode, the selected lines).
  function P.view()
    local l1, l2
    if vim.fn.mode():find("^[vV\22]") then
      l1, l2 = vim.fn.line("v"), vim.fn.line(".")
      if l1 > l2 then l1, l2 = l2, l1 end
      vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
    end
    local src, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
    local missing = spec.missing()
    if missing then return V.notify(missing) end
    if not P.supported() then
      -- no graphics terminal: compile and hand the PDF to the system viewer
      return P.compile(src, function(ok, err)
        if ok then vim.ui.open(P.pdf_path(src)) else V.notify(spec.name .. " preview failed:\n" .. L.summary(err)) end
      end)
    end
    watch(src)
    local pdf = P.pdf_path(src)
    local name = vim.api.nvim_buf_get_name(src)
    local key = name ~= "" and name or nil
    local v = P.current()
    if v then
      if v.pdf ~= pdf or P.src ~= src then v:set_pdf(pdf, title(src), key) end
    else
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].bufhidden = "wipe"
      pcall(vim.api.nvim_buf_set_name, buf, "pdfview://" .. title(src))
      v = V.new(buf, pdf, spec.kind, { integration = P, inverse = P.inverse, title = title(src), store_key = key })
      P.viewer = v
    end
    P.src, v.src_win = src, win
    -- open the split first: a Markdown page is shaped to it
    if not v:win() then v:open_split(spec.config().width) end
    v.status = { kind = "busy", text = "rendering" }
    v:winbar()
    P.compile(src, function(ok, err)
      if not (P.current() == v and P.src == src) then return end
      if not ok then
        fail(v, err)
        return V.notify(spec.name .. " preview failed:\n" .. L.summary(err))
      end
      v.status = nil
      v:render()
      P.sync(v, win, l1, l2)
    end)
  end

  function P.toggle_live()
    P.live = not P.live
    last = nil
    local v = P.current()
    if v then v:winbar() end
    V.notify("Live follow " .. (P.live and "on" or "off"), vim.log.levels.INFO)
  end

  return P
end

return L
