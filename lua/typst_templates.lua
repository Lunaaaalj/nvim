-- Start a Typst document from a template: a Telescope picker over Typst
-- Universe templates (plus local `@local` template packages), then
-- `typst init <spec> <dir>`, open the entry file and start the live preview.
--
--   * Universe's package index (packages.typst.org/preview/index.json) lists
--     every version of every package; templates are the ones with a
--     `template` table (entry file, thumbnail). It is cached for a day under
--     stdpath("cache")/typst and refreshed in the background.
--   * your own templates: make them local packages, i.e. a folder
--     <data>/typst/packages/local/<name>/<version>/ with a typst.toml that has
--     a [template] section (path, entrypoint); they are listed too.
--   * `favourites` are shown first, marked ★.
--
-- Picker keys: <CR> create (asks for the directory), <C-o> open the template's
-- Universe page in the browser.

local M = {}

M.favourites = { "elsevier-cas-unofficial", "elspub", "charged-ieee" }
M.preview = true -- open the live preview (<leader>lv) after creating

local CACHE = vim.fn.stdpath("cache") .. "/typst/index.json"
local URL = "https://packages.typst.org/preview/index.json"
local TTL = 24 * 3600

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.WARN, { title = "Typst template" })
end

-- "0.12.1" -> { 0, 12, 1 }; compares numerically, not as strings.
local function ver(s)
  local t = {}
  for n in tostring(s or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
  return t
end

local function newer(a, b)
  a, b = ver(a), ver(b)
  for i = 1, math.max(#a, #b) do
    if (a[i] or 0) ~= (b[i] or 0) then return (a[i] or 0) > (b[i] or 0) end
  end
  return false
end

local typst_version
local function installed_typst()
  if typst_version == nil then
    local out = vim.fn.system({ "typst", "--version" })
    typst_version = vim.v.shell_error == 0 and out:match("(%d+%.%d+%.%d+)") or false
  end
  return typst_version
end

-- index.json -> one entry (the latest version) per template package.
local function templates_of(index)
  local latest = {}
  for _, p in ipairs(index) do
    if type(p.template) == "table" and (not latest[p.name] or newer(p.version, latest[p.name].version)) then
      latest[p.name] = p
    end
  end
  return vim.tbl_values(latest)
end

local cached ---@type table[]? decoded templates, for this session

local function read_cache()
  local ok, lines = pcall(vim.fn.readfile, CACHE)
  if not ok then return nil end
  local ok2, index = pcall(vim.json.decode, table.concat(lines, "\n"))
  return ok2 and type(index) == "table" and templates_of(index) or nil
end

local fetching = false
-- Download the index into the cache; cb(templates?) when done.
local function fetch(cb)
  if fetching then return end
  fetching = true
  vim.fn.mkdir(vim.fs.dirname(CACHE), "p")
  local tmp = CACHE .. ".tmp"
  vim.system({ "curl", "-fsSL", "--max-time", "30", "-o", tmp, URL }, {}, vim.schedule_wrap(function(res)
    fetching = false
    if res.code ~= 0 then
      os.remove(tmp)
      return cb(nil)
    end
    os.rename(tmp, CACHE)
    cached = read_cache()
    cb(cached)
  end))
end

-- The Universe templates: from memory, else the cache (refreshed in the
-- background when stale), else a download.
local function universe(cb)
  local st = vim.uv.fs_stat(CACHE)
  local stale = not st or os.time() - st.mtime.sec > TTL
  cached = cached or (st and read_cache())
  if cached then
    if stale then fetch(function() end) end
    return cb(cached)
  end
  notify("Fetching the Typst Universe index…", vim.log.levels.INFO)
  fetch(function(t)
    if not t then notify("Couldn't download the Typst Universe index (" .. URL .. ")") end
    cb(t or {})
  end)
end

-- Typst's data dir: local packages live in <data>/typst/packages/local.
local function local_root()
  local data = vim.fn.has("mac") == 1 and (vim.env.HOME .. "/Library/Application Support")
    or (vim.env.XDG_DATA_HOME or (vim.env.HOME .. "/.local/share"))
  return data .. "/typst/packages/local"
end

-- Local template packages, read from their typst.toml.
local function locals()
  local out, root = {}, local_root()
  for _, toml in ipairs(vim.fn.glob(root .. "/*/*/typst.toml", false, true)) do
    local text = table.concat(vim.fn.readfile(toml), "\n")
    local tpl = text:match("%[template%](.-)\n%[") or text:match("%[template%](.*)$")
    if tpl then
      out[#out + 1] = {
        name = text:match('\nname%s*=%s*"([^"]+)"') or vim.fs.basename(vim.fs.dirname(vim.fs.dirname(toml))),
        version = text:match('\nversion%s*=%s*"([^"]+)"') or vim.fs.basename(vim.fs.dirname(toml)),
        description = text:match('\ndescription%s*=%s*"([^"]+)"') or "",
        template = { entrypoint = tpl:match('entrypoint%s*=%s*"([^"]+)"') or "main.typ" },
        namespace = "local",
      }
    end
  end
  return out
end

local function spec(t)
  return ("@%s/%s:%s"):format(t.namespace or "preview", t.name, t.version)
end

-- Can the installed typst compile it? (Universe records the minimum version.)
local function compatible(t)
  local have = installed_typst()
  return not (have and t.compiler and newer(t.compiler, have))
end

-- `typst init` the template into a directory (asked for), open its entry file
-- and start the live preview.
function M.create(t)
  local default = vim.fn.getcwd() .. "/" .. t.name
  vim.ui.input({ prompt = "New project directory: ", default = default, completion = "dir" }, function(dir)
    if not dir or vim.trim(dir) == "" then return end
    dir = vim.fn.fnamemodify(vim.fn.expand(vim.trim(dir)), ":p"):gsub("/$", "")
    if vim.fn.isdirectory(dir) == 1 and #vim.fn.readdir(dir) > 0 then
      return notify(dir .. " already exists and isn't empty")
    end
    vim.fn.mkdir(vim.fs.dirname(dir), "p") -- typst init won't create parents
    notify(("typst init %s …"):format(spec(t)), vim.log.levels.INFO)
    vim.system({ "typst", "init", spec(t), dir }, { text = true }, vim.schedule_wrap(function(res)
      if res.code ~= 0 then
        local err = vim.trim(res.stderr or ""):match("error:[^\n]*") or vim.trim(res.stderr or "")
        return notify("typst init failed: " .. err, vim.log.levels.ERROR)
      end
      local entry = dir .. "/" .. (t.template.entrypoint or "main.typ")
      if vim.fn.filereadable(entry) == 0 then -- fall back to any .typ at the top
        entry = vim.fn.glob(dir .. "/*.typ", false, true)[1] or entry
      end
      vim.cmd.edit(vim.fn.fnameescape(entry))
      if M.preview then
        -- after the FileType autocmds (tinymist, keymaps) have run
        vim.schedule(function()
          if vim.bo.filetype == "typst" then require("pdfview.typst").view() end
        end)
      end
    end))
  end)
end

local function preview_lines(t)
  local l = {
    ("# %s %s"):format(t.name, t.version),
    "",
    t.description or "",
    "",
  }
  local function field(k, v)
    if v and v ~= "" then l[#l + 1] = ("- **%s:** %s"):format(k, v) end
  end
  field("spec", "`" .. spec(t) .. "`")
  field("authors", t.authors and table.concat(t.authors, ", "))
  field("categories", t.categories and table.concat(t.categories, ", "))
  field("keywords", t.keywords and table.concat(t.keywords, ", "))
  field("license", t.license)
  field("needs typst", t.compiler and (t.compiler .. (compatible(t) and "" or ("  ✗ you have " .. installed_typst()))))
  field("entry file", t.template.entrypoint)
  field("repository", t.repository or t.homepage)
  if t.updatedAt then field("updated", os.date("%Y-%m-%d", t.updatedAt)) end
  return l
end

-- The picker. `opts` is passed to Telescope.
function M.pick(opts)
  universe(function(remote)
    local fav = {}
    for i, name in ipairs(M.favourites) do fav[name] = i end
    local list = vim.list_extend(locals(), remote)
    table.sort(list, function(a, b)
      local fa, fb = fav[a.name] or math.huge, fav[b.name] or math.huge
      if fa ~= fb then return fa < fb end
      if (a.namespace == "local") ~= (b.namespace == "local") then return a.namespace == "local" end
      return a.name < b.name
    end)

    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local previewers = require("telescope.previewers")
    local actions = require("telescope.actions")
    local state = require("telescope.actions.state")
    local conf = require("telescope.config").values

    local function selected(fn)
      return function(bufnr)
        local e = state.get_selected_entry()
        if e then fn(e.value, bufnr) end
      end
    end

    pickers
      .new(opts or {}, {
        prompt_title = "New Typst document from a template",
        finder = finders.new_table({
          results = list,
          entry_maker = function(t)
            local mark = fav[t.name] and "★" or t.namespace == "local" and "◆" or " "
            local warn = compatible(t) and "" or "✗ "
            local display = ("%s %s%-28s %s"):format(mark, warn, t.name, t.description or "")
            local ordinal = table.concat({
              t.name, t.description or "", table.concat(t.keywords or {}, " "), table.concat(t.categories or {}, " "),
            }, " ")
            return { value = t, display = display, ordinal = ordinal }
          end,
        }),
        sorter = conf.generic_sorter({}),
        previewer = previewers.new_buffer_previewer({
          title = "Template",
          define_preview = function(self, entry)
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview_lines(entry.value))
            vim.bo[self.state.bufnr].filetype = "markdown"
            vim.wo[self.state.winid].wrap = true
          end,
        }),
        attach_mappings = function(bufnr, map)
          actions.select_default:replace(selected(function(t)
            actions.close(bufnr)
            if not compatible(t) then
              notify(("%s needs typst %s (you have %s); init may fail"):format(t.name, t.compiler, installed_typst()))
            end
            M.create(t)
          end))
          map({ "i", "n" }, "<C-o>", selected(function(t)
            if t.namespace == "local" then return notify("Local package: no Universe page") end
            vim.ui.open("https://typst.app/universe/package/" .. t.name)
          end))
          return true
        end,
      })
      :find()
  end)
end

-- :TypstNew [name]: straight to `create` when the name is a known template.
function M.new(name)
  if not name then return M.pick() end
  universe(function(remote)
    for _, t in ipairs(vim.list_extend(locals(), remote)) do
      if t.name == name then return M.create(t) end
    end
    M.pick({ default_text = name })
  end)
end

-- Template names for :TypstNew completion (from the cache only: never blocks).
function M.complete(lead)
  cached = cached or read_cache()
  local names = {}
  for _, t in ipairs(vim.list_extend(locals(), cached or {})) do
    if t.name:find(lead, 1, true) == 1 then names[#names + 1] = t.name end
  end
  table.sort(names)
  return names
end

return M
