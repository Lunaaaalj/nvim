-- One backend per language. Each has:
--   name          shown in titles and the language prompt
--   available()   whether its tool is installed
--   topic(ctx)    the topic under the cursor (ctx = { buf, row, col, line, cword })
--   cmd(topic, width, ctx) -> argv, opts   a vim.system() call printing plain text,
--                 exiting non-zero when there's no page
--   list(cb)      every topic, for the Telescope search (cached by init.lua)
--   child(page, word)   topics to try for `K` on a word inside one of its pages
-- All output is plain text shown as filetype `man` (headings, `foo(3)` refs, gO).

local M = {}

local function sh(script, ...) return { "sh", "-c", script, "sh", ... } end

local function lines_of(out)
  return vim.split(vim.trim(out or ""), "\n", { trimempty = true })
end

-- The run of `pat` characters around the cursor, cut at the end of the
-- identifier under it (cursor on `linalg` in `np.linalg.norm` -> `np.linalg`).
local function chain(ctx, pat)
  local line, col = ctx.line, ctx.col + 1
  if not line:sub(col, col):match(pat) then return nil end
  local s, e = col, col
  while s > 1 and line:sub(s - 1, s - 1):match(pat) do s = s - 1 end
  while e < #line and line:sub(e + 1, e + 1):match("[%w_]") do e = e + 1 end
  return (line:sub(s, e):gsub("^[.:]+", ""))
end

-- C: man pages, library sections first (`printf` is printf(3), not the shell
-- command printf(1), which is what hover.nvim's own man provider shows).
M.c = {
  name = "C",
  available = function() return vim.fn.executable("man") == 1 end,
  topic = function(ctx) return ctx.cword:match("^[%a_][%w_]*$") and ctx.cword end,
  cmd = function(topic, width)
    -- `printf(3)` (a reference inside a page) pins the section.
    local name, sect = topic:match("^([%w_.:-]+)%((%w+)%)$")
    return sh([[
      for s in $2; do
        man -w "$s" "$1" >/dev/null 2>&1 && { MANPAGER=cat MANWIDTH=$3 man "$s" "$1" | col -bx; exit 0; }
      done
      exit 1]], name or topic, sect or "3 2 1 4 5 7", tostring(width))
  end,
  list = function(cb)
    vim.system(sh([[
      IFS=:; for d in $(manpath); do ls "$d"/man2 "$d"/man3 2>/dev/null; done |
        sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)\.\([23]\)[a-z]*\(\.gz\)\{0,1\}$/\1(\2)/p' | sort -u]]),
      { text = true }, function(r) cb(lines_of(r.stdout)) end)
  end,
  child = function(_, word) return { word } end,
}

-- C++: cppreference.com through cppman (pages are cached in ~/.cache/cppman
-- after the first view; `cppman -c` caches everything for offline use).
local function cppman_index()
  local f = vim.fn.glob(vim.fn.expand("~/.cache/cppman/index.db"))
  if f ~= "" then return f end
  return vim.fn.glob(vim.fn.expand("~/.local/pipx/venvs/cppman/lib/python*/site-packages/cppman/lib/index.db"), false, true)[1]
end

-- Type of the expression ending just before `.`/`->` at `col`, from clangd's
-- hover ("Type: `std::vector<int>`"), so `v.push_back` -> std::vector::push_back.
local function receiver_type(buf, row, col)
  local client = vim.lsp.get_clients({ bufnr = buf, name = "clangd" })[1]
  if not client then return nil end
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(buf),
    position = { line = row - 1, character = col },
  }
  local res = client:request_sync("textDocument/hover", params, 600, buf)
  local value = res and res.result and res.result.contents and res.result.contents.value
  local ty = value and value:match("Type: `([^`]+)`")
  if not ty then return nil end
  ty = ty:gsub("^const ", ""):gsub("%s*[&*]+$", ""):gsub("<.*>", "")
  return ty:match("^std::[%w_:]+$")
end

M.cpp = {
  name = "C++",
  available = function() return vim.fn.executable("cppman") == 1 end,
  topic = function(ctx)
    local t = chain(ctx, "[%w_:]")
    if not t or t == "" then return nil end
    -- Member access: qualify with the receiver's type when clangd knows it.
    local start = ctx.line:find(t, math.max(1, ctx.col + 2 - #t), true) or 0
    local before = ctx.line:sub(1, start - 1)
    local op = before:match("%.$") and 1 or before:match("%->$") and 2
    if op and not t:find("::") then
      local ty = receiver_type(ctx.buf, ctx.row, #before - op - 1)
      if ty then return ty .. "::" .. t end
    end
    return t
  end,
  cmd = function(topic, width)
    -- cppman pipes through $PAGER when its pager is "system" (the default
    -- "vim" would take over the terminal), so pass that explicitly.
    return { "cppman", "--force-columns=" .. width, topic }, { env = { PAGER = "cat" }, stdin = "" }
  end,
  list = function(cb)
    local db = cppman_index()
    if not db or vim.fn.executable("sqlite3") == 0 then return cb({}) end
    vim.system({ "sqlite3", db, 'SELECT title FROM "cppreference.com" ORDER BY title' }, { text = true },
      function(r) cb(lines_of(r.stdout)) end)
  end,
  child = function(page, word)
    -- `push_back` in std::vector's page -> std::vector::push_back first.
    local cls = page:match("^(std::[%w_:]+)$")
    return cls and { cls .. "::" .. word, word } or { word }
  end,
}

-- Python: pydoc, run with the file's project interpreter so third-party
-- packages resolve to the versions that project actually has.
local host_bin = vim.g.python3_host_prog and vim.fs.dirname(vim.g.python3_host_prog)

local function system_python()
  for dir in vim.gsplit(vim.env.PATH or "", ":", { plain = true }) do
    local p = dir .. "/python3"
    if dir ~= host_bin and vim.fn.executable(p) == 1 then return p end
  end
  return "python3"
end

function M.python_for(buf)
  local name = vim.api.nvim_buf_get_name(buf or 0)
  local start = name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
  for dir in vim.fs.parents(start .. "/x") do
    for _, v in ipairs({ ".venv", "venv", "env", ".env" }) do
      local p = ("%s/%s/bin/python"):format(dir, v)
      if vim.fn.executable(p) == 1 then return p end
    end
    if dir == vim.env.HOME then break end
  end
  for _, v in ipairs({ vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX }) do
    if v and v .. "/bin" ~= host_bin and vim.fn.executable(v .. "/bin/python") == 1 then return v .. "/bin/python" end
  end
  return system_python()
end

-- `import numpy as np` / `from os import path as p` / `from x import y`
-- -> { np = "numpy", p = "os.path", y = "x.y" }
local function import_aliases(buf)
  local map = {}
  for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local mod, rest = l:match("^%s*from%s+([%w_.]+)%s+import%s+(.+)$")
    if mod then
      for item in rest:gsub("[()\\]", ""):gmatch("[^,]+") do
        local n, a = vim.trim(item):match("^([%w_]+)%s+as%s+([%w_]+)$")
        n = n or vim.trim(item):match("^([%w_]+)$")
        if n then map[a or n] = mod .. "." .. n end
      end
    else
      rest = l:match("^%s*import%s+(.+)$")
      for item in (rest or ""):gmatch("[^,]+") do
        local n, a = vim.trim(item):match("^([%w_.]+)%s+as%s+([%w_]+)$")
        if a then map[a] = n end
      end
    end
  end
  return map
end

M.python = {
  name = "Python",
  available = function() return true end,
  topic = function(ctx)
    local t = chain(ctx, "[%w_.]")
    if not t or t == "" then return nil end
    local head, tail = t:match("^([%w_]+)(.*)$")
    local full = head and import_aliases(ctx.buf)[head]
    return full and full .. tail or t
  end,
  cmd = function(topic, width, ctx)
    return { M.python_for(ctx and ctx.buf), "-m", "pydoc", topic },
      { env = { COLUMNS = tostring(width), PAGER = "cat" }, cwd = ctx and ctx.dir }
  end,
  list = function(cb, ctx)
    local code = "import pkgutil,sys,keyword\n"
      .. "names = set(sys.builtin_module_names) | {m.name for m in pkgutil.iter_modules()} | set(keyword.kwlist)\n"
      .. "names |= {n for n in dir(__builtins__) if not n.startswith('_')}\n"
      .. "print('\\n'.join(sorted(names)))"
    vim.system({ M.python_for(ctx and ctx.buf), "-c", code }, { text = true }, function(r) cb(lines_of(r.stdout)) end)
  end,
  child = function(page, word)
    if word:find("%.") then return { word } end
    return { page .. "." .. word, word }
  end,
}

-- R: the installed help pages as text (Rd2txt), so CRAN packages are covered
-- at their installed version. Runs in the file's dir so renv's .Rprofile applies.
local R_PAGE = [[
a <- commandArgs(TRUE); topic <- a[1]; pkg <- if (nzchar(a[2])) a[2]
h <- function(...) as.character(suppressWarnings(do.call(utils::help, list(topic, ..., help_type = "text"))))
f <- h(package = pkg)
if (!length(f) && is.null(pkg)) {
  for (p in .packages(all.available = TRUE)) {
    f <- tryCatch(h(package = p), error = function(e) character())
    if (length(f)) break
  }
}
if (!length(f)) quit(status = 1)
cat(sprintf("%s {%s}\n\n", topic, basename(dirname(dirname(f[1])))))
tools::Rd2txt(utils:::.getHelpFile(f[1]), options = list(underline_titles = FALSE, width = as.integer(a[3])))
]]

local R_LIST = [[
for (p in .packages(all.available = TRUE)) {
  f <- file.path(find.package(p), "help", "aliases.rds")
  if (file.exists(f)) cat(paste0(p, "::", names(readRDS(f))), sep = "\n")
}
]]

M.r = {
  name = "R",
  available = function() return vim.fn.executable("Rscript") == 1 end,
  topic = function(ctx) return chain(ctx, "[%w_.:]") end,
  cmd = function(topic, width, ctx)
    local pkg, name = topic:match("^([%w.]+):::?(.+)$")
    -- help() takes its topic unevaluated, hence do.call() in the script.
    return { "Rscript", "--no-save", "-e", R_PAGE, name or topic, pkg or "", tostring(width) },
      { cwd = ctx and ctx.dir }
  end,
  list = function(cb)
    vim.system({ "Rscript", "--no-save", "-e", R_LIST }, { text = true }, function(r) cb(lines_of(r.stdout)) end)
  end,
  child = function(_, word) return { word } end,
}

-- filetype -> backend
M.by_ft = { c = "c", cpp = "cpp", objc = "c", cuda = "cpp", python = "python", r = "r", rmd = "r" }

return M
