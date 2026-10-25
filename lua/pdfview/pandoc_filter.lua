-- pandoc Lua filter for lua/pdfview/markdown.lua -- run by pandoc, not Neovim
-- (never `require` this). It makes GitHub-style READMEs come out of the typst
-- engine looking the way GitHub shows them, where typst would otherwise drop
-- or refuse things:
--
--   * <div align="center"> ... </div> and <p align="center"> wrap their
--     content in #align(center) (GitHub READMEs centre their whole header)
--   * raw HTML blocks (<table>, <img>, ...) are parsed as HTML, not dropped
--   * inline tag pairs <sub> <sup> <b> <i> <kbd> <a href> become typst markup;
--     <br> and <img> become breaks/images; other inline tags are dropped
--     (their text stays) -- unmatched tags are dropped rather than emitted, so
--     a stray tag can't unbalance the typst brackets
--   * Markdown table header cells are bold
--   * remote images are downloaded with curl into $PDFVIEW_IMG_CACHE (this
--     pandoc has no HTTP support); failures are remembered for the session
--   * missing local images and links to #anchors that don't exist degrade to
--     text -- typst aborts the whole document on either

local cache = os.getenv("PDFVIEW_IMG_CACHE")

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() end
  return f ~= nil
end

local function unpercent(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- Local path for an image source, downloading remote ones; nil if unusable.
local function fetch(src)
  if not src:match("^https?://") then
    src = unpercent(src)
    return exists(src) and src or nil
  end
  if not cache then return nil end
  local base = cache .. "/" .. pandoc.utils.sha1(src)
  if exists(base .. ".fail") then return nil end
  for _, ext in ipairs({ ".svg", ".png", ".jpg", ".gif" }) do
    if exists(base .. ext) then return base .. ext end
  end
  local part = base .. ".part"
  local ok = os.execute(("curl -fsSL --max-time 4 -o '%s' '%s'"):format(part, src:gsub("'", "%%27")))
  local ext
  if ok then
    local f = io.open(part, "rb")
    local head = f and f:read(512) or ""
    if f then f:close() end
    ext = head:find("<svg", 1, true) and ".svg" or head:sub(2, 4) == "PNG" and ".png"
      or head:sub(1, 3) == "\255\216\255" and ".jpg" or head:sub(1, 3) == "GIF" and ".gif" or nil
  end
  if not ext then
    os.remove(part)
    local marker = io.open(base .. ".fail", "w")
    if marker then marker:close() end
    return nil
  end
  os.rename(part, base .. ext)
  return base .. ext
end

local function image(img)
  local src = fetch(img.src)
  if not src then return pandoc.Span(img.caption) end -- keep the alt text
  img.src = src
  return img
end

local function typst(s) return pandoc.RawInline("typst", s) end

local function quote(s) return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"' end

-- typst opening markup for an inline HTML tag, or nil if we don't map it.
local function opener(name, tag)
  if name == "sub" or name == "small" then return "#text(size: 0.85em)[" end
  if name == "sup" then return "#super[" end
  if name == "b" or name == "strong" then return "#strong[" end
  if name == "i" or name == "em" then return "#emph[" end
  if name == "kbd" then
    return '#box(stroke: 0.5pt + rgb("#d1d9e0"), inset: (x: 3pt), outset: (y: 2pt), radius: 3pt)[#set text(size: 0.85em);'
  end
  if name == "a" then
    local href = tag:match('href="([^"]+)"')
    if href and href:match("^https?://") then return "#link(" .. quote(href) .. ")[" end
  end
end

local function html_image(text)
  local ok, doc = pcall(pandoc.read, text, "html")
  local found
  if ok then doc:walk({ Image = function(i) found = found or i end }) end
  return found and image(found) or nil
end

-- Inline HTML in one inline list: pair up open/close tags, map the pairs.
local function inlines(list)
  local tags, stack, pair = {}, {}, {}
  for i, el in ipairs(list) do
    if el.t == "RawInline" and el.format == "html" then
      local close, name = el.text:match("^<(/?)(%w+)")
      if name then
        name = name:lower()
        tags[i] = { close = close == "/", name = name }
        if close == "/" then
          for s = #stack, 1, -1 do
            if stack[s].name == name then
              pair[stack[s].i], pair[i] = i, stack[s].i
              for _ = s, #stack do table.remove(stack) end
              break
            end
          end
        elseif opener(name, el.text) then
          table.insert(stack, { name = name, i = i })
        end
      end
    end
  end
  local out = pandoc.Inlines({})
  for i, el in ipairs(list) do
    local t = tags[i]
    if not t then
      out:insert(el)
    elseif pair[i] then
      out:insert(typst(t.close and "]" or opener(t.name, el.text)))
    elseif el.text:match("^<br%s*/?>$") then
      out:insert(pandoc.LineBreak())
    elseif t.name == "img" then
      local img = html_image(el.text)
      if img then out:insert(img) end
    end -- anything else: drop the tag, keep the text around it
  end
  return out
end

local inline = { Image = image, Inlines = inlines }

local function parse_html(text)
  local ok, doc = pcall(pandoc.read, text, "html")
  if not ok then return pandoc.Blocks({}) end
  return doc.blocks:walk(inline)
end

local function centered(blocks)
  local out = pandoc.Blocks({ pandoc.RawBlock("typst", "#align(center)[") })
  out:extend(blocks)
  out:insert(pandoc.RawBlock("typst", "]"))
  return out
end

local function is_html(b) return b.t == "RawBlock" and b.format == "html" end
local CENTER = 'align%s*=%s*"?center"?'

-- Top-level blocks: centre <div|p align="center"> regions (an open tag on its
-- own, up to its matching close) and parse other raw HTML blocks.
local function blocks_pass(blocks)
  local out, i = pandoc.Blocks({}), 1
  while i <= #blocks do
    local b = blocks[i]
    local tag = is_html(b) and b.text:match("^%s*<(%w+)[^>]-" .. CENTER .. "[^>]*>%s*$")
    if tag then
      -- collect to the matching </tag>, counting nested opens of the same tag
      local depth, j, inner = 1, i + 1, pandoc.Blocks({})
      while j <= #blocks do
        local c = blocks[j]
        if is_html(c) then
          local _, opens = c.text:gsub("<" .. tag .. "[%s>]", "")
          local _, closes = c.text:gsub("</" .. tag .. "%s*>", "")
          depth = depth + opens - closes
          if depth <= 0 then break end
        end
        inner:insert(c)
        j = j + 1
      end
      out:extend(centered(blocks_pass(inner)))
      i = j + 1
    elseif is_html(b) then
      local parsed = parse_html(b.text)
      if b.text:match("^%s*<%w+[^>]-" .. CENTER) then parsed = centered(parsed) end
      out:extend(parsed)
      i = i + 1
    else
      out:insert(b)
      i = i + 1
    end
  end
  return out
end

local function bold_header(tbl)
  for _, row in ipairs(tbl.head.rows) do
    for _, cell in ipairs(row.cells) do
      cell.contents = cell.contents:walk({
        Plain = function(p) return pandoc.Plain({ pandoc.Strong(p.content) }) end,
        Para = function(p) return pandoc.Para({ pandoc.Strong(p.content) }) end,
      })
    end
  end
  return tbl
end

function Pandoc(doc)
  doc = doc:walk({ Table = bold_header }) -- before HTML tables join in
  doc = doc:walk(inline)
  doc.blocks = blocks_pass(doc.blocks)
  local ids = {}
  local function record(el) if el.identifier and el.identifier ~= "" then ids[el.identifier] = true end end
  doc:walk({ Header = record, Div = record, Span = record, Table = record, Figure = record })
  return doc:walk({
    Link = function(link)
      local id = link.target:match("^#(.+)$")
      if id and not ids[unpercent(id)] then return link.content end
    end,
  })
end
