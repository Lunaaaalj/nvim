-- One viewer per PDF buffer: a preview split (LaTeX "tex", Markdown "md") or
-- a .pdf file opened like any other buffer ("file").
--
-- The viewport lives in PDF points (vx, vy = its top-left on the "view": one
-- page, or two side by side in a spread), so zooming keeps whatever was centred
-- and nothing depends on pixel sizes until render time. Each render composes a
-- window-sized PNG from cached page images (lua/pdfview/render.lua) plus the
-- SyncTeX and search highlights, and snacks.image draws it with kitty's
-- Unicode placeholders.

local R = require("pdfview.render")
local C = require("defaults.colors")

local V = {}
V.__index = V

local GAP = 10 -- points between the pages of a spread
local viewers = {} ---@type table<integer, table>

local function cfg() return require("pdfview").config end
local function clamp(v, lo, hi) return math.max(lo, math.min(v, hi)) end
local function esc(s) return (s:gsub("%%", "%%%%")) end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.WARN, { title = "PDF" })
end
V.notify = notify

local function hl(name, attr)
  return vim.api.nvim_get_hl(0, { name = name, link = false })[attr]
end

local function rgba(n, a)
  return ("rgba(%d,%d,%d,%.2f)"):format(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256, a)
end

function V.get(buf) return viewers[buf] end
function V.list() return vim.tbl_values(viewers) end

-- opts: fields set before the per-PDF state is restored, e.g. `integration`
-- (the source-side module: tex/markdown, providing live follow), `inverse`
-- (click -> source; defaults to SyncTeX), `title`, `store_key`.
---@param kind "tex"|"md"|"file"
function V.new(buf, pdf, kind, opts)
  local self = setmetatable({
    buf = buf, pdf = pdf, kind = kind,
    page = 1, fit = "page", zoom = 1, vx = 0, vy = 0, -- fit: "page"|"width"|"manual"
    spread = false, colors = cfg().colors,
    history = {}, gen = 0,
    timer = assert(vim.uv.new_timer()),
  }, V)
  for k, val in pairs(opts or {}) do self[k] = val end
  if not V.did_setup then V.setup() end
  require("pdfview.store").restore(self)
  viewers[buf] = self
  vim.b[buf].pdfview = true
  self:keymaps()
  local group = vim.api.nvim_create_augroup("pdfview." .. buf, { clear = true })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      viewers[buf] = nil
      self.timer:close()
      if self.png then os.remove(self.png) end
      require("pdfview.store").save(self)
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    buffer = buf,
    callback = function() vim.schedule(function() self:render() end) end,
  })
  -- the winbar is window-local: don't leave ours on the next buffer shown here
  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    buffer = buf,
    callback = function()
      if vim.api.nvim_get_current_buf() == buf then vim.wo.winbar = "" end
    end,
  })
  return self
end

-- Point an existing viewer at another PDF (a preview switching projects).
function V:set_pdf(pdf, title, store_key)
  self.title, self.store_key = title, store_key
  self.pdf, self.mt, self.info, self.layout = pdf, nil, nil, nil
  self.page, self.vx, self.vy, self.sync_marks, self.search, self.history = 1, 0, 0, nil, nil, {}
  require("pdfview.store").restore(self)
  pcall(vim.api.nvim_buf_set_name, self.buf, "pdfview://" .. (title or vim.fs.basename(pdf)))
end

function V:win()
  local w = vim.fn.bufwinid(self.buf)
  return w ~= -1 and w or nil
end

function V:setup_win(win)
  local wo = vim.wo[win]
  wo.number, wo.relativenumber, wo.cursorline = false, false, false
  wo.spell, wo.wrap, wo.list = false, false, false
  wo.signcolumn, wo.foldcolumn, wo.statuscolumn = "no", "0", ""
  wo.winfixwidth = not self.float
end

-- The LaTeX preview's home: a full-height split at the far right, sized to
-- the page on its first render.
function V:open_split(frac)
  local win = vim.api.nvim_open_win(self.buf, false, {
    split = "right",
    win = -1,
    width = math.floor(vim.o.columns * (frac or 0.45)),
  })
  -- LaTeX pages have a fixed shape, so the split adapts to them; Markdown
  -- pages are shaped to the split instead (lua/pdfview/markdown.lua)
  self.float, self.autosize = false, self.kind == "tex"
  self:setup_win(win)
  self:winbar()
  return win
end

-- Reading mode: move the preview into a large float and back.
function V:toggle_float()
  local old = self:win()
  if not old or self.kind == "file" then return end
  local new
  if self.float then
    new = self:open_split()
    vim.api.nvim_set_current_win(new)
  else
    local w, h = math.floor(vim.o.columns * 0.9), math.floor((vim.o.lines - 2) * 0.94)
    new = vim.api.nvim_open_win(self.buf, true, {
      relative = "editor",
      row = math.floor((vim.o.lines - 2 - h) / 2),
      col = math.floor((vim.o.columns - w) / 2),
      width = w,
      height = h,
      border = "none",
      zindex = 45,
    })
    self.float = true
    self:setup_win(new)
  end
  vim.api.nvim_win_close(old, true) -- the buffer lives on in `new`
  self:winbar()
  self:render()
end

function V:close()
  local win = self:win()
  if not win then return end
  if self.kind == "file" then
    local ok, bc = pcall(require, "defaults.bufclose")
    if ok and bc.close_buffer then return bc.close_buffer() end
    return vim.cmd.bdelete()
  end
  vim.api.nvim_win_close(win, true)
end

function V:look()
  local fg = C.fg("Normal") or (vim.o.background == "dark" and 0xd8d8d8 or 0x202020)
  return { colors = self.colors, fg = ("#%06x"):format(fg) }
end

function V:step()
  return self.spread and 2 or 1
end

-- Pages on screen: one, or the (odd, even) pair holding `page` in a spread.
function V:view_pages()
  if not self.spread then return { self.page } end
  local first = self.page - (self.page - 1) % 2
  local n = self.info and self.info.pages or first
  return first + 1 <= n and { first, first + 1 } or { first }
end

-- Left offsets of `pages` on the view, and the view's size, in points.
function V:view_box(pages)
  local ox, x, h = {}, 0, 0
  for i, q in ipairs(pages) do
    local sz = R.size(self.info, q)
    ox[i] = x
    x = x + sz[1] + (i < #pages and GAP or 0)
    h = math.max(h, sz[2])
  end
  return ox, x, h
end

-- Split width (columns) at which the view exactly fills the window's height.
function V:fit_cols(win)
  local px = Snacks.image.terminal.size()
  local _, w, h = self:view_box(self:view_pages())
  local cols = math.ceil(vim.fn.winheight(win) * px.cell_height * w / h / px.cell_width) + 1
  local c = cfg()
  return clamp(cols, math.floor(vim.o.columns * c.min_width), math.floor(vim.o.columns * c.max_width))
end

-- Where the viewport lands in `win`. Pixel sizes use `winheight()`, which
-- (unlike nvim_win_get_height) leaves out the winbar.
function V:geometry(win)
  local px = Snacks.image.terminal.size()
  local cw, ch = px.cell_width, px.cell_height
  local vw = math.floor(vim.api.nvim_win_get_width(win) * cw) - 1
  local vh = math.floor(vim.fn.winheight(win) * ch) - 1
  local pages = self:view_pages()
  local ox, Wpt, Hpt = self:view_box(pages)
  local fit = math.min(vw / Wpt, vh / Hpt) -- px per point at "fit page"
  if self.fit == "page" then
    self.zoom = 1
  elseif self.fit == "width" then
    self.zoom = (vw / Wpt) / fit
  end
  self.zoom = clamp(self.zoom, 0.25, 12)
  local s = fit * self.zoom
  local W, H = math.min(vw, math.floor(Wpt * s)), math.min(vh, math.floor(Hpt * s))
  local view_w, view_h = W / s, H / s
  if self.anchor then
    self.vx, self.vy = self.anchor[1] - view_w / 2, self.anchor[2] - view_h / 2
    self.anchor = nil
  end
  self.vx = clamp(self.vx, 0, Wpt - view_w)
  self.vy = clamp(self.vy, 0, Hpt - view_h)
  return {
    s = s, cw = cw, ch = ch, vw = vw, W = W, H = H,
    X = math.floor(self.vx * s), Y = math.floor(self.vy * s),
    padx = math.floor((vw - W) / 2), -- the view is centred horizontally
    view_w = view_w, view_h = view_h, max_vx = Wpt - view_w, max_vy = Hpt - view_h,
    pages = pages, ox = ox,
  }
end

-- SyncTeX + search highlights on the visible pages, in viewport pixels.
function V:mark_rects(g)
  local out = {}
  local function add(boxes, page, color)
    for i, q in ipairs(g.pages) do
      if q == page then
        for _, b in ipairs(boxes) do
          out[#out + 1] = {
            math.floor(g.padx + (g.ox[i] + b[1]) * g.s - g.X), math.floor(b[2] * g.s - g.Y),
            math.ceil(g.padx + (g.ox[i] + b[3]) * g.s - g.X), math.ceil(b[4] * g.s - g.Y), color,
          }
        end
      end
    end
  end
  local accent = C.accent() or 0xe0a040
  if self.sync_marks then add(self.sync_marks.boxes, self.sync_marks.page, rgba(accent, 0.28)) end
  if self.search then
    local all = rgba(hl("Search", "bg") or accent, 0.35)
    local cur = rgba(hl("CurSearch", "bg") or hl("IncSearch", "bg") or accent, 0.65)
    for i, m in ipairs(self.search.matches) do
      add(m.boxes, m.page, i == self.search.idx and cur or all)
    end
  end
  return out
end

function V:winbar()
  local win = self:win()
  if not win then return end
  local left = "%#Comment# " .. esc(self.title or vim.fs.basename(self.pdf))
  -- status = { kind = "error"|"busy", text = ... }, set by the integration
  if self.status then
    local err = self.status.kind == "error"
    left = ("%s  %%#%s#%s %s"):format(left, err and "DiagnosticError" or "DiagnosticWarn", err and "✗" or "⟳",
      esc(self.status.text))
  end
  local right = {}
  if self.search then
    right[#right + 1] = ("/%s %d/%d"):format(esc(self.search.query), self.search.idx or 0, #self.search.matches)
  end
  if self.integration and self.integration.live then right[#right + 1] = "live" end
  if self.colors == "paper" then right[#right + 1] = "paper" end
  right[#right + 1] = self.fit == "page" and "fit" or self.fit == "width" and "width"
    or ("%d%%%%"):format(math.floor(self.zoom * 100 + 0.5))
  local pages, n = self:view_pages(), self.info and self.info.pages or "?"
  right[#right + 1] = #pages > 1 and ("pages %d–%d / %s"):format(pages[1], pages[2], n)
    or ("page %d / %s"):format(pages[1], n)
  vim.wo[win].winbar = left .. "%=%#Comment#" .. table.concat(right, " · ") .. " "
end

function V:show(png)
  if not vim.api.nvim_buf_is_valid(self.buf) then
    os.remove(png)
    return
  end
  local old = self.png
  self.png = png
  Snacks.image.buf.attach(self.buf, { src = png })
  -- kitty may still be reading the old file when the new one is placed
  if old then vim.defer_fn(function() os.remove(old) end, 5000) end
  self:winbar()
  require("pdfview.store").save(self)
end

-- Warm the page cache for the neighbouring view so turning the page is instant.
function V:prefetch(g)
  if not cfg().prefetch then return end
  local first = g.pages[1]
  local cands = self.spread and { first + 2, first + 3, first - 2, first - 1 } or { first + 1, first - 1 }
  local look = self:look()
  for _, q in ipairs(cands) do
    if q >= 1 and q <= self.info.pages then
      local sz = R.size(self.info, q)
      if sz[1] * g.s * sz[2] * g.s <= R.max_pixels then R.page(self.pdf, self.mt, q, g.s, look) end
    end
  end
end

function V:render()
  local win = self:win()
  if not win then return end
  if self.busy then
    self.again = true
    return
  end
  self.busy = true
  local function done()
    self.busy = false
    if self.again then
      self.again = false
      self:render()
    end
  end

  local mt = R.mtime(self.pdf)
  if not mt then
    -- a preview's window can open before its first PDF is written
    if self.kind == "file" then notify("Missing " .. self.pdf) end
    return done()
  end
  R.info(self.pdf, mt, function(info)
    win = self:win()
    if not (info and win) then
      if not info then notify("Can't read " .. self.pdf) end
      return done()
    end
    local changed = self.mt ~= nil and self.mt ~= mt
    self.info, self.mt = info, mt
    self.page = clamp(self.page, 1, info.pages)
    if changed and self.search then self:find(self.search.query, true) end
    if self.autosize then
      self.autosize = false
      if self.kind == "tex" and not self.float then vim.api.nvim_win_set_width(win, self:fit_cols(win)) end
    end

    local g = self:geometry(win)
    local look = self:look()
    local tasks = {}
    for i, q in ipairs(g.pages) do
      local sz = R.size(info, q)
      local qx = math.floor(g.ox[i] * g.s) -- page's left edge on the view, px
      local pw, ph = math.floor(sz[1] * g.s), math.floor(sz[2] * g.s)
      local x0, y0 = math.max(g.X, qx), math.max(g.Y, 0)
      local x1, y1 = math.min(g.X + g.W, qx + pw), math.min(g.Y + g.H, ph)
      if x1 > x0 and y1 > y0 then
        tasks[#tasks + 1] = {
          page = q,
          big = pw * ph > R.max_pixels,
          rect = { x0 - qx, y0, x1 - x0, y1 - y0 }, -- in page px
          at = { g.padx + x0 - g.X, y0 - g.Y }, -- in viewport px
        }
      end
    end

    local parts, temps, pending = {}, {}, #tasks
    local function compose()
      self.gen = self.gen + 1
      local out = ("%s/view-%d-%d.png"):format(R.dir, self.buf, self.gen)
      vim.fn.mkdir(R.dir, "p")
      local list = {}
      for i = 1, #tasks do
        if parts[i] then list[#list + 1] = parts[i] end
      end
      R.compose(list, self:mark_rects(g), g.vw, g.H, out, function(ok, err)
        for _, t in ipairs(temps) do os.remove(t) end
        if ok then
          self.layout = g
          self:show(out)
          self:prefetch(g)
        else
          notify("Render failed: " .. vim.trim(err or ""))
        end
        done()
      end)
    end
    if pending == 0 then return compose() end
    for i, t in ipairs(tasks) do
      local function got(src, temp)
        if src then
          parts[i] = { src = src, crop = temp and { 0, 0, t.rect[3], t.rect[4] } or t.rect, at = t.at }
          if temp then temps[#temps + 1] = src end
        end
        pending = pending - 1
        if pending == 0 then compose() end
      end
      -- (a crop is no faster to make than a full page -- poppler rasterises the
      -- whole page either way -- so only pages too big to cache use one)
      if t.big then
        R.crop(self.pdf, mt, t.page, g.s, t.rect, look, function(src) got(src, true) end)
      else
        R.page(self.pdf, mt, t.page, g.s, look, got)
      end
    end
  end)
end

-- Re-render once a burst of resizes settles.
function V:later()
  self.timer:start(120, 0, vim.schedule_wrap(function() self:render() end))
end

function V:go(page, vy)
  page = clamp(page, 1, self.info and self.info.pages or page)
  if page == self.page and vy == nil then return end
  self.page = page
  if vy then self.vy = vy end
  self:winbar()
  self:render()
end

-- Move the viewport by dy/dx points. Past the top/bottom edge of the view this
-- turns the page, so j/k read straight through the document.
function V:scroll(dy, dx)
  local L = self.layout
  if not L then return end
  if dx then
    if L.max_vx <= 0 then return self:go(self.page + (dx > 0 and 1 or -1) * self:step(), 0) end
    self.vx = clamp(self.vx + dx, 0, L.max_vx)
  elseif dy > 0 and self.vy >= L.max_vy - 0.5 then
    return self:go(self.page + self:step(), 0)
  elseif dy < 0 and self.vy <= 0.5 then
    if self.page - self:step() >= 1 then self:go(self.page - self:step(), math.huge) end
    return
  else
    self.vy = clamp(self.vy + dy, 0, L.max_vy)
  end
  self:render()
end

function V:set_zoom(z, fit)
  local L = self.layout
  if L then self.anchor = { self.vx + L.view_w / 2, self.vy + L.view_h / 2 } end
  self.fit = fit or "manual"
  if z then self.zoom = clamp(z, 0.25, 12) end
  self:winbar()
  self:render()
end

-- Make page y-range top..bottom (points) visible, turning to `page` if needed.
function V:reveal(page, top, bottom)
  self.page = page
  local L = self.layout
  if L and (top < self.vy or bottom > self.vy + L.view_h) then self.vy = top - L.view_h * 0.3 end
end

function V:push()
  table.insert(self.history, { self.page, self.vy })
  if #self.history > 50 then table.remove(self.history, 1) end
end

function V:back()
  local h = table.remove(self.history)
  if not h then return end
  self.page, self.vy = h[1], h[2]
  self:winbar()
  self:render()
end

-- The page point under a getmousepos() result: page, x, y (points).
function V:point_at(pos)
  local L, win = self.layout, self:win()
  if not (L and win) then return end
  -- winrow counts the winbar row; the image starts below it
  local row = pos.winrow - (vim.wo[win].winbar ~= "" and 1 or 0)
  local px = (pos.wincol - 0.5) * L.cw - L.padx
  local py = (row - 0.5) * L.ch
  if px < 0 or px > L.W or py < 0 or py > L.H then return end
  local x, y = (L.X + px) / L.s, (L.Y + py) / L.s
  for i, q in ipairs(L.pages) do
    local sz = R.size(self.info, q)
    if x >= L.ox[i] and x <= L.ox[i] + sz[1] and y <= sz[2] then return q, x - L.ox[i], y end
  end
end

-- A click on the page: follow a link if there is one, else inverse SyncTeX.
function V:click(pos)
  local page, x, y = self:point_at(pos)
  if not page then return end
  R.meta(self.pdf, self.mt, page, function(m)
    for _, l in ipairs(m and m.links or {}) do
      local b = l[1]
      if x >= b[1] - 1 and x <= b[3] + 1 and y >= b[2] - 1 and y <= b[4] + 1 then
        if l.page then
          self:push()
          self:go(l.page, 0)
        else
          vim.ui.open(l.url)
        end
        return
      end
    end
    ;(self.inverse or require("pdfview.tex").inverse)(self, page, x, y)
  end)
end

-- Search the text layer. Smartcase; matches across word boundaries; a hit
-- highlights the whole words it touches. `silent` (after a recompile) keeps
-- the position instead of jumping to the first hit.
function V:find(q, silent)
  if not q or q == "" then return end
  R.text(self.pdf, self.mt or R.mtime(self.pdf), function(pages)
    if not pages then return notify("This PDF has no text layer") end
    local case = q:find("%u") ~= nil
    local needle = case and q or vim.fn.tolower(q)
    local matches = {}
    for p, words in ipairs(pages) do
      local strs, starts, pos = {}, {}, 1
      for i, w in ipairs(words) do
        starts[i], strs[i] = pos, w[5]
        pos = pos + #w[5] + 1
      end
      local hay = table.concat(strs, " ")
      if not case then hay = vim.fn.tolower(hay) end
      local init = 1
      while true do
        local s, e = hay:find(needle, init, true)
        if not s then break end
        local boxes = {}
        for i, w in ipairs(words) do
          local ws, we = starts[i], starts[i] + #w[5] - 1
          if ws > e then break end
          if we >= s then
            local last = boxes[#boxes]
            if last and math.abs(last[2] - w[2]) < 2 then -- same line: extend
              last[3], last[4] = math.max(last[3], w[3]), math.max(last[4], w[4])
            else
              boxes[#boxes + 1] = { w[1], w[2], w[3], w[4] }
            end
          end
        end
        if #boxes > 0 then matches[#matches + 1] = { page = p, boxes = boxes } end
        init = e + 1
      end
    end
    self.search = { query = q, matches = matches, idx = 0 }
    if #matches == 0 then
      if not silent then notify("Not found: " .. q, vim.log.levels.INFO) end
    else
      local idx = 1
      for i, m in ipairs(matches) do
        if m.page >= self.page then
          idx = i
          break
        end
      end
      if not silent then
        self:push()
        return self:goto_match(idx)
      end
      self.search.idx = idx
    end
    self:winbar()
    self:render()
  end)
end

function V:goto_match(i)
  local s = self.search
  if not s or #s.matches == 0 then return end
  s.idx = (i - 1) % #s.matches + 1
  local m = s.matches[s.idx]
  self:reveal(m.page, m.boxes[1][2], m.boxes[#m.boxes][4])
  self:winbar()
  self:render()
end

function V:clear()
  self.sync_marks, self.search = nil, nil
  self:winbar()
  self:render()
end

function V:keymaps()
  local buf = self.buf
  local function sz(f) return (self.layout and self.layout[f] or 100) * cfg().scroll * vim.v.count1 end
  local function mouse(fn)
    return function()
      local pos = vim.fn.getmousepos()
      if pos.winid == self:win() then return fn(pos) end
      if pos.winid ~= 0 then -- aimed at another window: behave like a plain click
        vim.api.nvim_set_current_win(pos.winid)
        pcall(vim.api.nvim_win_set_cursor, pos.winid, { math.max(pos.line, 1), math.max(pos.column - 1, 0) })
      end
    end
  end
  local help = {
    { { "j", "<Down>", "<ScrollWheelDown>" }, function() self:scroll(sz("view_h")) end, "scroll down (flows to the next page)" },
    { { "k", "<Up>", "<ScrollWheelUp>" }, function() self:scroll(-sz("view_h")) end, "scroll up (flows to the previous page)" },
    { { "l", "<Right>" }, function() self:scroll(0, sz("view_w")) end, "pan right / next page" },
    { { "h", "<Left>" }, function() self:scroll(0, -sz("view_w")) end, "pan left / previous page" },
    { "<C-d>", function() self:scroll((self.layout and self.layout.view_h or 100) / 2) end, "half a screen down" },
    { "<C-u>", function() self:scroll(-(self.layout and self.layout.view_h or 100) / 2) end, "half a screen up" },
    -- not <Space>: it's the leader, and a buffer-local nowait map would swallow every <leader> key here
    { { "J", "<PageDown>", "<C-f>" }, function() self:go(self.page + self:step() * vim.v.count1, 0) end, "next page" },
    { { "K", "<BS>", "<PageUp>", "<C-b>" }, function() self:go(self.page - self:step() * vim.v.count1, 0) end, "previous page" },
    { "gg", function() self:go(vim.v.count > 0 and vim.v.count or 1, 0) end, "first page / page N" },
    { "G", function() self:go(vim.v.count > 0 and vim.v.count or self.info.pages, 0) end, "last page / page N" },
    { { "+", "=" }, function() self:set_zoom(self.zoom * cfg().zoom_step ^ vim.v.count1) end, "zoom in" },
    { "-", function() self:set_zoom(self.zoom / cfg().zoom_step ^ vim.v.count1) end, "zoom out" },
    { "0", function() self:set_zoom(1, "page") end, "fit page" },
    { "w", function() self:set_zoom(nil, "width") end, "fit width" },
    { "s", function()
      self.spread, self.anchor, self.vx = not self.spread, nil, 0
      self.autosize = self.kind == "tex" and not self.float
      self:winbar()
      self:render()
    end, "toggle two-page spread" },
    { "/", function()
      vim.ui.input({ prompt = "Search PDF: ", default = self.search and self.search.query }, function(q) self:find(q) end)
    end, "search the text" },
    { "n", function() if self.search then self:goto_match(self.search.idx + vim.v.count1) end end, "next match" },
    { "N", function() if self.search then self:goto_match(self.search.idx - vim.v.count1) end end, "previous match" },
    { { "<CR>", "<LeftMouse>", "<2-LeftMouse>" }, mouse(function(pos) self:click(pos) end), "follow link / jump to source (SyncTeX)" },
    { "<C-o>", function() self:back() end, "back (before a link or search jump)" },
    { "c", function()
      self.colors = self.colors == "theme" and "paper" or "theme"
      self:winbar()
      self:render()
    end, "toggle colorscheme / paper colours" },
    { { "x", "<Esc>" }, function() self:clear() end, "clear highlights and search" },
    { "r", function() self:render() end, "re-render" },
    { "q", function() self:close() end, "close" },
    { "?", function() self:show_help() end, "this help" },
  }
  if self.integration then -- the previews (LaTeX, Markdown)
    table.insert(help, { "z", function() self:toggle_float() end, "toggle reading mode (float)" })
    table.insert(help, { "f", function() self.integration.toggle_live() end, "toggle live follow of the cursor" })
  end
  self.help = help
  for _, m in ipairs(help) do
    for _, lhs in ipairs(type(m[1]) == "table" and m[1] or { m[1] }) do
      vim.keymap.set("n", lhs, m[2], { buffer = buf, nowait = true, silent = true, desc = "PDF: " .. m[3] })
    end
  end
end

function V:show_help()
  local lines = {}
  for _, m in ipairs(self.help) do
    local keys = type(m[1]) == "table" and table.concat(m[1], " ", 1, math.min(#m[1], 2)) or m[1]
    lines[#lines + 1] = ("%-18s %s"):format(keys, m[3])
  end
  vim.lsp.util.open_floating_preview(lines, "", { border = "rounded", title = " PDF viewer ", focus = false })
end

-- Global autocmds shared by every viewer (installed once).
function V.setup()
  V.did_setup = true
  local group = vim.api.nvim_create_augroup("pdfview", { clear = true })
  vim.api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      for _, v in pairs(viewers) do
        local win = v:win()
        if win and vim.tbl_contains(vim.v.event.windows, win) then v:later() end
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      for _, v in pairs(viewers) do
        if v:win() then
          v.autosize = v.kind == "tex" and not v.float
          v:later()
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      for _, v in pairs(viewers) do
        if v:win() and v.colors == "theme" then v:later() end
      end
    end,
  })
end

return V
