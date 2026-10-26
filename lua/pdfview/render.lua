-- Rasterising for lua/pdfview: page info (pdfinfo), page images (pdftoppm +
-- ImageMagick), per-page figures and links (pdftohtml) and the text layer
-- (pdftotext). Everything is keyed by the PDF's mtime, so a recompile
-- invalidates it all for free.
--
-- Page images are full pages at one scale, stored as ImageMagick's
-- memory-mapped .mpc so a viewport crop reads only the region it needs: a
-- scroll step is ~0.1 s instead of re-rasterising from the PDF (~0.6 s at
-- retina sizes). Pages too big to cache (high zoom) are rendered as viewport
-- crops straight from the PDF instead.

local M = {}

-- per process: several Neovims may be viewing PDFs at once
M.dir = vim.fn.stdpath("cache") .. "/pdfview/" .. vim.fn.getpid()
M.max_pixels = 24e6 -- full-page rasters above this go through `crop()` instead
local LRU_SIZE = 16 -- cached page images kept on disk

local function run(cmd, cb)
  for i, a in ipairs(cmd) do cmd[i] = tostring(a) end
  vim.system(cmd, { text = true }, vim.schedule_wrap(cb))
end
M.run = run

function M.mtime(pdf)
  local st = vim.uv.fs_stat(pdf)
  return st and ("%d.%d"):format(st.mtime.sec, st.mtime.nsec) or nil
end

local function key(...)
  return vim.fn.sha256(table.concat({ ... }, "|")):sub(1, 16)
end

-- One async computation per key; concurrent callers share it. A nil result is
-- not cached, so the next caller retries (e.g. the PDF was mid-write).
local function memo(cache, k, start, cb)
  local e = cache[k]
  if e and e.done then
    if cb then cb(e.value) end
    return
  end
  if e then
    if cb then table.insert(e.cbs, cb) end
    return
  end
  e = { cbs = { cb } }
  cache[k] = e
  start(function(value)
    if value == nil then
      cache[k] = nil
    else
      e.done, e.value = true, value
    end
    local cbs = e.cbs
    e.cbs = {}
    for _, f in ipairs(cbs) do f(value) end
  end)
end

local entities = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }
local function unescape(s)
  return (s:gsub("&(#?)(%w+);", function(num, name)
    if num == "#" then return vim.fn.nr2char(tonumber(name)) end
    return entities[name]
  end))
end

local infos = {}
-- { pages = n, sizes = { [page] = { w, h } } } in PDF points.
function M.info(pdf, mt, cb)
  memo(infos, pdf .. mt, function(done)
    run({ "pdfinfo", "-f", 1, "-l", 100000, pdf }, function(res)
      local out = res.stdout or ""
      local n = tonumber(out:match("Pages:%s+(%d+)"))
      if not n then return done(nil) end
      local sizes = {}
      for p, w, h in out:gmatch("Page%s+(%d+) size:%s+([%d.]+) x ([%d.]+)") do
        sizes[tonumber(p)] = { tonumber(w), tonumber(h) }
      end
      done({ pages = n, sizes = sizes })
    end)
  end, cb)
end

function M.size(info, page)
  return info.sizes[page] or info.sizes[1] or { 612, 792 }
end

local function attrs(s)
  local t = {}
  for k, v in s:gmatch('(%w+)="([^"]*)"') do t[k] = v end
  return t
end

local function box(t)
  local l, top = tonumber(t.left), tonumber(t.top)
  return { l, top, l + tonumber(t.width), top + tonumber(t.height) }
end

local metas = {}
-- { images = { box... }, links = { { box, page = n } | { box, url = s } } } for
-- one page, in points. pdftohtml has the only link geometry poppler exposes;
-- a link's box is its whole text run, which is close enough to click.
function M.meta(pdf, mt, page, cb)
  memo(metas, table.concat({ pdf, mt, page }, "|"), function(done)
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    run({ "pdftohtml", "-xml", "-q", "-zoom", 1, "-f", page, "-l", page, pdf, tmp .. "/p" }, function()
      local ok, lines = pcall(vim.fn.readfile, tmp .. "/p.xml")
      vim.fn.delete(tmp, "rf")
      local m = { images = {}, links = {} }
      local xml = ok and table.concat(lines, "\n") or ""
      for a in xml:gmatch("<image (.-)/>") do
        m.images[#m.images + 1] = box(attrs(a))
      end
      for a, inner in xml:gmatch("<text (.-)>(.-)</text>") do
        local href = inner:match('<a href="([^"]*)"')
        if href then
          href = unescape(href)
          local link = { box(attrs(a)) }
          local target = href:match("%.html#(%d+)$")
          if target then link.page = tonumber(target) else link.url = href end
          m.links[#m.links + 1] = link
        end
      end
      done(m)
    end)
  end, cb)
end

local texts = {}
-- { [page] = { { x0, y0, x1, y1, word }... } } for the whole document.
function M.text(pdf, mt, cb)
  memo(texts, pdf .. mt, function(done)
    run({ "pdftotext", "-bbox", pdf, "-" }, function(res)
      if res.code ~= 0 then return done(nil) end
      local pages, cur = {}, nil
      for line in (res.stdout or ""):gmatch("[^\n]+") do
        if line:find("<page ", 1, true) then
          cur = {}
          pages[#pages + 1] = cur
        elseif cur then
          local x0, y0, x1, y1, w =
            line:match('<word xMin="([%d.]+)" yMin="([%d.]+)" xMax="([%d.]+)" yMax="([%d.]+)">(.-)</word>')
          if x0 then cur[#cur + 1] = { tonumber(x0), tonumber(y0), tonumber(x1), tonumber(y1), unescape(w) } end
        end
      end
      done(pages)
    end)
  end, cb)
end

-- ImageMagick arguments (after the input) recolouring `src` for "theme": ink to
-- `fg`, paper to alpha (ink = 1 - min(R,G,B), so antialiasing blends onto any
-- background). `keep` rects (figures, in src pixels) keep their own colours.
-- 1 - min(R,G,B) is max() of the negated channels, i.e. HSB brightness: same
-- pixels as `-separate -evaluate-sequence min -negate`, at half the cost.
function M.recolor(src, fg, keep)
  local a = {
    "-channel", "RGB", "+level-colors", fg .. ",white", "+channel",
    "(", src, "-negate", "-grayscale", "Brightness", ")",
    "-alpha", "off", "-compose", "CopyOpacity", "-composite", "-compose", "Over",
  }
  for _, r in ipairs(keep or {}) do
    local x, y = math.max(0, r[1]), math.max(0, r[2])
    local w, h = r[3] - x, r[4] - y
    if w > 0 and h > 0 then
      vim.list_extend(a, {
        "(", src, "-crop", ("%dx%d+%d+%d"):format(w, h, x, y), "+repage", ")",
        "-geometry", ("+%d+%d"):format(x, y), "-composite",
      })
    end
  end
  return a
end

-- Figure rects of `m` at scale `s`, shifted by (ox, oy) pixels.
local function figures(m, s, ox, oy)
  local keep = {}
  for _, b in ipairs(m and m.images or {}) do
    keep[#keep + 1] = {
      math.floor(b[1] * s) - ox, math.floor(b[2] * s) - oy,
      math.ceil(b[3] * s) - ox, math.ceil(b[4] * s) - oy,
    }
  end
  return keep
end

local pages, lru = {}, {}

local function touch(k, base)
  for i, e in ipairs(lru) do
    if e.k == k then
      table.remove(lru, i)
      break
    end
  end
  table.insert(lru, 1, { k = k, base = base })
  while #lru > LRU_SIZE do
    local e = table.remove(lru)
    pages[e.k] = nil
    os.remove(e.base .. ".mpc")
    os.remove(e.base .. ".cache")
  end
end

local function page_key(pdf, mt, page, s, look)
  return key(pdf, mt, page, ("%.4f"):format(s), look.colors, look.colors == "theme" and look.fg or "")
end

-- Path of a cached full-page image (.mpc) of `page` at `s` px/pt, built on
-- first use. look = { colors = "theme"|"paper", fg = "#rrggbb" }.
function M.page(pdf, mt, page, s, look, cb)
  local theme = look.colors == "theme"
  local k = page_key(pdf, mt, page, s, look)
  local base = M.dir .. "/" .. k
  if pages[k] and pages[k].done then touch(k, base) end
  memo(pages, k, function(done)
    vim.fn.mkdir(M.dir, "p")
    local raw, m -- nil = pending; false = failed / none
    local function finish()
      if raw == nil or (theme and m == nil) then return end
      if not raw then return done(nil) end
      local args = { "magick", base .. "-raw.ppm" }
      if theme then vim.list_extend(args, M.recolor(base .. "-raw.ppm", look.fg, figures(m, s, 0, 0))) end
      table.insert(args, base .. ".mpc")
      run(args, function(res)
        os.remove(base .. "-raw.ppm")
        if res.code ~= 0 then return done(nil) end
        touch(k, base)
        done(base .. ".mpc")
      end)
    end
    -- PPM, not PNG: it is read once by magick, and PNG's compression made
    -- pdftoppm ~5x slower (~250 ms vs ~45 ms for a retina A4 page)
    run({ "pdftoppm", "-singlefile", "-f", page, "-l", page, "-r", ("%.4f"):format(s * 72), pdf, base .. "-raw" },
      function(res)
        raw = res.code == 0
        finish()
      end)
    if theme then
      M.meta(pdf, mt, page, function(v)
        m = v or false
        finish()
      end)
    end
  end, cb)
end

-- A one-off crop rect = { x, y, w, h } (page pixels at `s`) rendered straight
-- from the PDF. The caller deletes the file.
function M.crop(pdf, mt, page, s, rect, look, cb)
  local base = ("%s/crop-%s"):format(M.dir, key(pdf, mt, page, s, table.concat(rect, ","), vim.uv.hrtime()))
  vim.fn.mkdir(M.dir, "p")
  run({
    "pdftoppm", "-singlefile", "-f", page, "-l", page, "-r", ("%.4f"):format(s * 72),
    "-x", rect[1], "-y", rect[2], "-W", rect[3], "-H", rect[4], pdf, base,
  }, function(res)
    if res.code ~= 0 then return cb(nil) end
    if look.colors ~= "theme" then return cb(base .. ".ppm") end
    M.meta(pdf, mt, page, function(m)
      local args = { "magick", base .. ".ppm" }
      vim.list_extend(args, M.recolor(base .. ".ppm", look.fg, figures(m, s, rect[1], rect[2])))
      table.insert(args, base .. "-c.png")
      run(args, function(r2)
        os.remove(base .. ".ppm")
        cb(r2.code == 0 and base .. "-c.png" or nil)
      end)
    end)
  end)
end

-- The final viewport image: a w x h transparent canvas with `parts`
-- ({ src, crop = {x,y,w,h}, at = {x,y} }) composited on and `marks`
-- ({ x0, y0, x1, y1, color }) drawn over. The tiny density makes snacks (which
-- sizes images by DPI and never enlarges) always shrink it to the window -- a
-- no-op for a window-sized image, keeping its pixels 1:1 with cells.
function M.compose(parts, marks, w, h, out, cb)
  local function read(p)
    local c = p.crop
    return ("%s[%dx%d+%d+%d]"):format(p.src, c[3], c[4], c[1], c[2])
  end
  local args
  if #parts == 1 then
    -- one page: pad it into place with -extent (a negative offset shifts it
    -- right/down); ~0.1 s cheaper than compositing onto a blank canvas
    local p = parts[1]
    args = {
      "magick", read(p), "+repage", "-background", "none",
      "-extent", ("%dx%d-%d-%d"):format(w, h, p.at[1], p.at[2]),
    }
  else
    args = { "magick", "-size", ("%dx%d"):format(w, h), "xc:none" }
    for _, p in ipairs(parts) do
      vim.list_extend(args, { read(p), "+repage", "-geometry", ("+%d+%d"):format(p.at[1], p.at[2]), "-composite" })
    end
  end
  for _, mk in ipairs(marks) do
    vim.list_extend(args, { "-fill", mk[5], "-draw", ("rectangle %d,%d %d,%d"):format(mk[1], mk[2], mk[3], mk[4]) })
  end
  vim.list_extend(args, {
    "-density", 1, "-units", "PixelsPerInch",
    "-define", "png:compression-level=1", "-define", "png:compression-filter=0", out,
  })
  run(args, function(res) cb(res.code == 0, res.stderr) end)
end

function M.clear()
  vim.fn.delete(M.dir, "rf")
  pages, lru = {}, {}
end

return M
