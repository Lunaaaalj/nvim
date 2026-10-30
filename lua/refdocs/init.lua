-- Language references in Neovim: C (man), C++ (cppman / cppreference),
-- Python (pydoc, with the file's project venv) and R (installed help pages).
--
--   * `K` (hover.nvim): the "Ref" provider sits right after LSP; <C-n>/<C-p>
--     switch between them (lua/refdocs/hover.lua).
--   * `<leader>K` / `:Ref [topic]`: the full page in a reusable split. Inside a
--     page, `K` / `<C-]>` follow the word under the cursor (relative to the
--     page: `push_back` in std::vector's page is std::vector::push_back) and
--     <C-o> goes back, since pages stay loaded as hidden buffers.
--   * `<leader>fd` / `:RefSearch [lang]`: Telescope over every topic, with the
--     page as the preview; <C-e> looks up the typed text verbatim.
--
-- The language comes from the filetype, or from the enclosing code chunk in
-- Quarto / R Markdown / Markdown. Backends live in lua/refdocs/backends.lua.

local B = require("refdocs.backends")

local M = {}

local cache = {} -- "lang\0topic\0width" -> lines
local lists = {} -- lang (or "python\0<interpreter>") -> topics
local bufs = {} -- "ref://lang/topic" -> page buffer

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Reference" })
end

local CHUNK_FT = { quarto = true, markdown = true, rmd = true }

-- Language of the fenced chunk around `row` (```{r}, ```python, ```{python echo=F}).
local function chunk_lang(buf, row)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, row, false)
  for i = #lines, 1, -1 do
    local l = lines[i]
    if l:match("^%s*```") then
      local lang = l:match("^%s*```+%s*{?%s*([%w_+]+)")
      return lang and lang:lower() or nil -- a bare ``` here closes a chunk
    end
  end
end

local ALIAS = { c = "c", cpp = "cpp", ["c++"] = "cpp", python = "python", py = "python", r = "r" }

function M.lang_at(buf, row)
  buf = buf or 0
  local page = vim.b[buf].refdocs
  if page then return page.lang end
  local ft = vim.bo[buf].filetype
  if CHUNK_FT[ft] then
    local l = chunk_lang(buf, row or vim.api.nvim_win_get_cursor(0)[1])
    return l and ALIAS[l]
  end
  return B.by_ft[ft]
end

local function context(buf, win)
  buf, win = buf or vim.api.nvim_get_current_buf(), win or vim.api.nvim_get_current_win()
  local pos = vim.api.nvim_win_get_cursor(win)
  local line = vim.api.nvim_buf_get_lines(buf, pos[1] - 1, pos[1], false)[1] or ""
  local col = pos[2] + 1
  -- An identifier, or a `name(3)` man reference when the cursor is on one.
  local s, e = col, col
  while s > 1 and line:sub(s - 1, s - 1):match("[%w_]") do s = s - 1 end
  while e <= #line and line:sub(e, e):match("[%w_]") do e = e + 1 end
  local cword = line:sub(s, e - 1)
  local sect = line:sub(e):match("^%(%d%w*%)")
  if sect and vim.b[buf].refdocs then cword = cword .. sect end
  local name = vim.api.nvim_buf_get_name(buf)
  return {
    buf = buf, row = pos[1], col = pos[2], line = line, cword = cword,
    dir = vim.b[buf].refdocs and vim.b[buf].refdocs.dir or (name ~= "" and vim.fs.dirname(name)) or vim.fn.getcwd(),
  }
end
M.context = context

-- lang, { topics to try in order }, ctx for the cursor in `buf`.
function M.topics_at(buf, win)
  local ctx = context(buf, win)
  local lang = M.lang_at(ctx.buf, ctx.row)
  local be = lang and B[lang]
  if not be then return nil, nil, ctx end
  local page = vim.b[ctx.buf].refdocs
  -- Inside a page, read the word the plain way (no clangd, no imports).
  local t = page and (lang == "c" and ctx.cword or nil) or be.topic(ctx)
  if page and not t then
    local pat = ({ cpp = "[%w_:]", python = "[%w_.]", r = "[%w_.:]" })[lang] or "[%w_]"
    local line, col = ctx.line, ctx.col + 1
    local s, e = col, col
    while s > 1 and line:sub(s - 1, s - 1):match(pat) do s = s - 1 end
    while e < #line and line:sub(e + 1, e + 1):match("[%w_]") do e = e + 1 end
    t = line:sub(s, e):gsub("^[.:]+", ""):gsub("[.:]+$", "")
  end
  if not t or t == "" then return lang, nil, ctx end
  return lang, page and be.child(page.topic, t) or { t }, ctx
end

-- cb(lines) or cb(nil, err), on the main loop.
function M.fetch(lang, topic, width, ctx, cb)
  local be = B[lang]
  if not be.available() then
    return cb(nil, ("%s references need %s"):format(be.name, ({ cpp = "cppman (pipx install cppman)", r = "Rscript" })[lang] or "man"))
  end
  local key = table.concat({ lang, topic, width, lang == "python" and B.python_for(ctx and ctx.buf) or "" }, "\0")
  if cache[key] then return cb(cache[key]) end
  local argv, opts = be.cmd(topic, width, ctx)
  opts = vim.tbl_extend("force", { text = true, timeout = 15000 }, opts or {})
  vim.system(argv, opts, vim.schedule_wrap(function(r)
    local out = vim.split((r.stdout or ""):gsub("%s+$", ""), "\n")
    if r.code ~= 0 or #out == 0 or out[1] == "" and #out == 1 then
      return cb(nil, ("No %s reference for %s"):format(be.name, topic))
    end
    while out[1] == "" do table.remove(out, 1) end
    cache[key] = out
    cb(out)
  end))
end

-- First of `topics` that has a page.
function M.fetch_first(lang, topics, width, ctx, cb, i)
  i = i or 1
  M.fetch(lang, topics[i], width, ctx, function(lines, err)
    if lines or i == #topics then return cb(lines, err, topics[i]) end
    M.fetch_first(lang, topics, width, ctx, cb, i + 1)
  end)
end

-- The window showing a reference page, else a new split for one.
local function page_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.b[vim.api.nvim_win_get_buf(w)].refdocs then return w end
  end
  -- A right column; lua/layout stacks it under any panel already there.
  local cur = vim.api.nvim_get_current_win()
  vim.cmd("botright vertical " .. require("layout").panel_width() .. "split")
  local w = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(cur)
  return w
end

local function show(lang, topic, lines, dir)
  local name = ("ref://%s/%s"):format(lang, topic)
  local buf = bufs[name]
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, name)
    bufs[name] = buf
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "hide"
  vim.b[buf].refdocs = { lang = lang, topic = topic, dir = dir }
  vim.bo[buf].filetype = "man"
  for _, lhs in ipairs({ "K", "<C-]>" }) do
    vim.keymap.set("n", lhs, M.lookup, { buffer = buf, desc = "Reference: follow word under cursor" })
  end

  local win = page_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  vim.api.nvim_set_current_win(win)
end

-- Full page for `topic` (or the cursor's topic) in the reference split.
function M.open(topic, lang)
  local ctx = context()
  local topics
  if topic then
    topics = { topic }
  else
    local l, t, c = M.topics_at()
    if l then
      lang, topics, ctx = l, t, c
    elseif lang and ctx.cword ~= "" then
      topics = { ctx.cword } -- non-code buffer, language picked by hand
    end
  end
  lang = lang or M.lang_at(ctx.buf, ctx.row)
  if not lang then return M.pick_lang(function(l) M.open(topic, l) end) end
  if not topics then return notify("No identifier under the cursor", vim.log.levels.WARN) end
  M.fetch_first(lang, topics, require("layout").panel_width() - 4, ctx, function(lines, err, found)
    if not lines then return notify(err, vim.log.levels.WARN) end
    show(lang, found, lines, ctx.dir)
  end)
end

function M.lookup() M.open() end

function M.pick_lang(cb)
  local langs = { "c", "cpp", "python", "r" }
  vim.ui.select(langs, {
    prompt = "Reference language",
    format_item = function(l) return B[l].name end,
  }, function(l) if l then cb(l) end end)
end

-- Telescope over every topic of `lang`.
function M.search(lang)
  lang = ALIAS[(lang or ""):lower()] or (not lang or lang == "") and M.lang_at() or nil
  if not lang then return M.pick_lang(M.search) end
  local ctx = context()
  local key = lang == "python" and "python\0" .. B.python_for(ctx.buf) or lang
  if not lists[key] then
    notify(("Indexing %s topics…"):format(B[lang].name))
    return B[lang].list(vim.schedule_wrap(function(items)
      if #items == 0 then return notify(("No %s topics found"):format(B[lang].name), vim.log.levels.WARN) end
      lists[key] = items
      M.search(lang)
    end), ctx)
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local previewers = require("telescope.previewers")
  local actions = require("telescope.actions")
  local state = require("telescope.actions.state")
  local conf = require("telescope.config").values

  local function choose(text)
    return function(bufnr)
      local e = state.get_selected_entry()
      local t = text and state.get_current_line() or e and e.value
      actions.close(bufnr)
      if t and t ~= "" then vim.schedule(function() M.open(t, lang) end) end
    end
  end

  pickers
    .new({}, {
      prompt_title = B[lang].name .. " reference",
      finder = finders.new_table({ results = lists[key] }),
      sorter = conf.generic_sorter({}),
      previewer = previewers.new_buffer_previewer({
        title = "Reference",
        define_preview = function(self, entry)
          local buf, win = self.state.bufnr, self.state.winid
          local width = math.max(40, vim.api.nvim_win_get_width(win) - 2)
          M.fetch(lang, entry.value, width, ctx, function(lines, err)
            if not vim.api.nvim_buf_is_valid(buf) then return end
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or { err })
            vim.bo[buf].filetype = "man"
          end)
        end,
      }),
      attach_mappings = function(_, map)
        actions.select_default:replace(choose(false))
        map({ "i", "n" }, "<C-e>", choose(true))
        return true
      end,
    })
    :find()
end

function M.setup()
  vim.api.nvim_create_user_command("Ref", function(o)
    M.open(o.args ~= "" and o.args or nil)
  end, { nargs = "?", desc = "Reference page for a topic (default: under cursor)" })
  vim.api.nvim_create_user_command("RefSearch", function(o)
    M.search(o.args ~= "" and o.args or nil)
  end, {
    nargs = "?",
    complete = function() return { "c", "cpp", "python", "r" } end,
    desc = "Search reference topics (Telescope)",
  })
  vim.keymap.set("n", "<leader>K", M.lookup, { desc = "Reference page for word under cursor" })
  vim.keymap.set("n", "<leader>fd", function() M.search() end, { desc = "Find in language reference docs" })
end

return M
