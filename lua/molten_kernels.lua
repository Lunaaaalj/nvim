-- Molten kernels straight from Python interpreters, the way VS Code does it:
-- pick a venv / conda env / interpreter and it runs, no `jkernel add` first.
--
--   * Molten only starts *kernelspecs* (it looks them up through
--     jupyter_client). So for the chosen interpreter we write one ourselves,
--     into a private dir that `setup()` puts on $JUPYTER_PATH. That has to
--     happen before the Python host starts, because the host reads the
--     variable from its own environment. The specs never touch
--     ~/Library/Jupyter, so `jupyter kernelspec list`, VS Code and JupyterLab
--     don't see them.
--   * A spec is per (interpreter, notebook dir). Its argv chdirs into the dir
--     before starting ipykernel, because Molten starts kernels in the Python
--     host's cwd (wherever Neovim was launched), so `open("data.csv")` would
--     resolve elsewhere. Its env puts the env's bin first on PATH (and sets
--     VIRTUAL_ENV / CONDA_PREFIX), so `!pip` and subprocesses use that env.
--   * Missing ipykernel is installed on confirmation (uv if present, else
--     pip). Interpreters that refuse installs (Homebrew, uv-managed: PEP 668)
--     offer to create a project .venv from them instead.
--   * The choice is remembered per file, and per project root as the default
--     for new notebooks. `ensure()` (what the run-cell keys call) uses it, or
--     the project's only venv, and only opens the picker when it can't tell.
--   * Registered kernels (IRkernel for R, `jkernel` ones) are listed too.
--
-- Discovery only stats files (no process per interpreter), so the picker is
-- instant. The interpreter is run once, on selection, to check ipykernel.

local M = {}

M.host = vim.fn.expand("~/.virtualenvs/neovim") -- Neovim's Python host venv: never a kernel
M.dir = vim.fn.stdpath("data") .. "/molten" -- on $JUPYTER_PATH; specs live in <dir>/kernels/<name>
M.state_file = vim.fn.stdpath("state") .. "/molten_kernels.json"
M.prefix = "nvim-" -- generated kernel names; anything else is a registered kernel
M.markers = { "pyproject.toml", "uv.lock", "poetry.lock", "Pipfile", "requirements.txt", "setup.py", ".venv", ".git" }
M.max_age = 30 * 24 * 3600 -- generated specs unused for this long are pruned

local uv = vim.uv
local home = vim.fn.expand("~")

-- 0 / nil -> the current buffer's number, so async callbacks keep the notebook
local function bufnr(buf)
  return (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Kernel" })
end

local function exists(p) return p ~= nil and uv.fs_stat(p) ~= nil end
local function tilde(p) return (p:gsub("^" .. vim.pesc(home), "~")) end
local function norm(p) return vim.fs.normalize(p) end

local function read_json(path)
  local f = io.open(path)
  if not f then return end
  local s = f:read("*a")
  f:close()
  local ok, v = pcall(vim.json.decode, s)
  return ok and type(v) == "table" and v or nil
end

-- ── interpreters ─────────────────────────────────────────────────────────

local function env_python(prefix)
  for _, rel in ipairs({ "bin/python", "bin/python3" }) do
    if vim.fn.executable(prefix .. "/" .. rel) == 1 then return prefix .. "/" .. rel end
  end
end

-- Version without running Python: pyvenv.cfg, conda-meta, or a versioned name.
local function static_version(prefix, python)
  local f = io.open(prefix .. "/pyvenv.cfg")
  if f then
    for line in f:lines() do
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k == "version" or k == "version_info" then
        f:close()
        return v:match("^%d+%.%d+%.?%d*")
      end
    end
    f:close()
  end
  for name in vim.fs.dir(prefix .. "/conda-meta") or function() end do
    local v = name:match("^python%-(%d+%.%d+%.%d+)")
    if v then return v end
  end
  return vim.fs.basename(prefix):match("(%d+%.%d+%.?%d*)")
    or vim.fs.basename(uv.fs_realpath(python) or python):match("python(%d+%.%d+)")
end

-- An interpreter record from a python path:
-- { python, prefix, kind = venv|conda|pyenv|uv|system, version, project, active }
function M.describe(python)
  python = norm(python)
  local prefix = vim.fs.dirname(vim.fs.dirname(python))
  local kind = exists(prefix .. "/pyvenv.cfg") and "venv"
    or exists(prefix .. "/conda-meta") and "conda"
    or prefix:find("/%.pyenv/versions/") and "pyenv"
    or prefix:find("/uv/python/") and "uv"
    or "system"
  return { python = python, prefix = prefix, kind = kind, version = static_version(prefix, python) }
end

function M.root(buf)
  local name = vim.api.nvim_buf_get_name(buf or 0)
  local dir = name ~= "" and vim.fs.dirname(name) or uv.cwd()
  return norm(vim.fs.root(dir, { M.markers }) or dir), norm(dir)
end

-- Every interpreter worth offering for `buf`, best first: the active env, the
-- project's envs (any dir with a pyvenv.cfg from the file's dir up to the
-- root, plus poetry/pipenv envs named after the project), then global envs
-- (~/.virtualenvs, conda, pyenv, uv), then system Pythons.
function M.interpreters(buf)
  local root, dir = M.root(buf)
  local list, seen = {}, { [norm(M.host)] = true }
  local function add(prefix, extra)
    if not prefix then return end
    prefix = norm(prefix)
    local python = not seen[prefix] and env_python(prefix)
    if not python then return end
    seen[prefix] = true
    list[#list + 1] = vim.tbl_extend("force", M.describe(python), extra or {})
  end
  local function each_dir(parent, fn)
    if not exists(parent) then return end
    for name, type in vim.fs.dir(parent) do
      if type == "directory" or type == "link" then fn(parent .. "/" .. name, name) end
    end
  end

  add(vim.env.VIRTUAL_ENV, { active = true })
  add(vim.env.CONDA_PREFIX, { active = true })

  local d = dir
  while d do
    each_dir(d, function(p)
      if exists(p .. "/pyvenv.cfg") then add(p, { project = true }) end
    end)
    if d == root or d == vim.fs.dirname(d) or not vim.startswith(d, root) then break end
    d = vim.fs.dirname(d)
  end
  -- poetry / pipenv keep the env out of the project, named "<project>-<hash>"
  local proj = vim.fs.basename(root):lower():gsub("[^%w]", "[-_]?")
  for _, parent in ipairs({
    home .. "/Library/Caches/pypoetry/virtualenvs",
    home .. "/.cache/pypoetry/virtualenvs",
    home .. "/.local/share/virtualenvs",
  }) do
    each_dir(parent, function(p, name)
      add(p, { project = name:lower():match("^" .. proj .. "%-") ~= nil })
    end)
  end

  local function add_dir(p) add(p) end
  each_dir(home .. "/.virtualenvs", add_dir)
  local conda = {}
  local f = io.open(home .. "/.conda/environments.txt")
  if f then
    for line in f:lines() do conda[#conda + 1] = vim.trim(line) end
    f:close()
  end
  for _, base in ipairs({ "miniforge3", "miniconda3", "anaconda3", "mambaforge" }) do
    conda[#conda + 1] = home .. "/" .. base
    each_dir(home .. "/" .. base .. "/envs", function(p) conda[#conda + 1] = p end)
  end
  for _, p in ipairs(conda) do
    if p ~= "" then add(p) end
  end
  each_dir((vim.env.PYENV_ROOT or home .. "/.pyenv") .. "/versions", add_dir)
  each_dir(vim.env.UV_PYTHON_INSTALL_DIR or home .. "/.local/share/uv/python", add_dir)

  -- system Pythons, deduplicated by what they resolve to
  local real = {}
  for _, it in ipairs(list) do real[uv.fs_realpath(it.python) or it.python] = it.kind ~= "venv" or nil end
  for _, python in ipairs({ "/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3" }) do
    local r = vim.fn.executable(python) == 1 and uv.fs_realpath(python)
    if r and not real[r] then
      real[r] = true
      seen[python] = true
      list[#list + 1] = { python = python, prefix = vim.fs.dirname(vim.fs.dirname(python)), kind = "system",
        version = static_version("", r) }
    end
  end

  local rank = function(it) return it.active and 0 or it.project and 1 or it.kind == "system" and 3 or 2 end
  table.sort(list, function(a, b)
    if rank(a) ~= rank(b) then return rank(a) < rank(b) end
    return a.python < b.python
  end)
  return list, root
end

-- ── registered kernelspecs ───────────────────────────────────────────────

-- jupyter_core's search path (macOS + Linux user dirs, the host venv, system).
local function spec_dirs()
  local dirs = { M.dir }
  for p in (vim.env.JUPYTER_PATH or ""):gmatch("[^:]+") do dirs[#dirs + 1] = p end
  vim.list_extend(dirs, {
    home .. "/Library/Jupyter", home .. "/.local/share/jupyter", M.host .. "/share/jupyter",
    "/opt/homebrew/share/jupyter", "/usr/local/share/jupyter", "/usr/share/jupyter",
  })
  return dirs
end

-- name -> { name, display, language, dir } (first dir wins, as in jupyter_client)
function M.kernelspecs()
  local specs = {}
  for _, d in ipairs(spec_dirs()) do
    for name, type in vim.fs.dir(d .. "/kernels") or function() end do
      if type ~= "file" and not specs[name] then
        local j = read_json(d .. "/kernels/" .. name .. "/kernel.json")
        if j then
          specs[name] = { name = name, display = j.display_name or name, language = (j.language or ""):lower(),
            dir = d .. "/kernels/" .. name, argv = j.argv }
        end
      end
    end
  end
  return specs
end

local aliases = { py = "python", python3 = "python", ipython = "python", ipython3 = "python" }
function M.normalize_language(lang)
  lang = (lang or ""):lower()
  return aliases[lang] or lang
end

-- Language of a running kernel id ("" when unknown). Molten suffixes ids of a
-- second instance of the same kernel ("python3_1").
function M.language(id)
  if vim.startswith(id, M.prefix) then return "python" end
  local specs = M.kernelspecs()
  local s = specs[id] or specs[(id:gsub("_%d+$", ""))]
  return s and M.normalize_language(s.language) or ""
end

-- Drop generated specs whose interpreter or dir is gone, or that went unused.
local function prune()
  local now = os.time()
  for name in vim.fs.dir(M.dir .. "/kernels") or function() end do
    local d = M.dir .. "/kernels/" .. name
    local j = read_json(d .. "/kernel.json")
    local st = uv.fs_stat(d .. "/kernel.json")
    if not j or not st or type(j.argv) ~= "table" or vim.fn.executable(j.argv[1] or "") == 0 or not exists(j.argv[4])
      or now - st.mtime.sec > M.max_age then
      vim.fn.delete(d, "rf")
    end
  end
end

-- ── state ────────────────────────────────────────────────────────────────

local function load_state()
  local s = read_json(M.state_file) or {}
  s.files, s.roots = s.files or {}, s.roots or {}
  return s
end

local function remember(buf, choice)
  local s = load_state()
  local file = vim.api.nvim_buf_get_name(buf)
  if file ~= "" then s.files[file] = choice end
  s.roots[(M.root(buf))] = choice
  vim.fn.mkdir(vim.fs.dirname(M.state_file), "p")
  vim.fn.writefile({ vim.json.encode(s) }, M.state_file)
end

local function remembered(buf)
  local s = load_state()
  local c = s.files[vim.api.nvim_buf_get_name(buf)] or s.roots[(M.root(buf))]
  if not c then return end
  if c.python and vim.fn.executable(c.python) == 1 then return M.describe(c.python) end
  if c.kernel and M.kernelspecs()[c.kernel] then return c end
end

-- ── starting ─────────────────────────────────────────────────────────────

local function available()
  if vim.fn.exists(":MoltenInit") == 2 then return true end
  notify("Molten isn't registered: run :UpdateRemotePlugins and restart Neovim", vim.log.levels.ERROR)
end

-- Run `fn` with `buf` current (Molten acts on the current buffer).
local function in_buf(buf, fn)
  if buf == vim.api.nvim_get_current_buf() then return fn() end
  local win = vim.fn.bufwinid(buf)
  if win == -1 then return notify("The notebook's window is gone; kernel not started", vim.log.levels.WARN) end
  return vim.api.nvim_win_call(win, fn)
end

-- Kernel ids attached to `buf`.
function M.attached(buf)
  buf = bufnr(buf)
  if vim.fn.exists("*MoltenRunningKernels") == 0 then return {} end
  return in_buf(buf, function() return vim.fn.MoltenRunningKernels(true) end) or {}
end

local function label(it, root)
  if it.prefix and root and vim.startswith(it.prefix, root .. "/") then
    return vim.fs.basename(root) .. "/" .. it.prefix:sub(#root + 2)
  end
  return it.kind == "system" and tilde(it.python) or tilde(it.prefix)
end

local function slug(s) return (s:gsub("[^%w._-]+", "-"):gsub("^[-.]+", ""):sub(1, 40)) end

-- Write the kernelspec for interpreter `it` running in `dir`; returns its name.
local function write_spec(it, dir, root)
  local where = label(it, root)
  local name = M.prefix .. slug(where) .. "-" .. vim.fn.sha256(it.python .. "\0" .. dir):sub(1, 10)
  local env = { PATH = vim.fs.dirname(it.python) .. ":${PATH}" }
  if it.kind == "venv" then env.VIRTUAL_ENV = it.prefix end
  if it.kind == "conda" then env.CONDA_PREFIX = it.prefix end
  local spec = {
    -- argv[4] is the cwd: popped before ipykernel parses its arguments
    argv = {
      it.python, "-c",
      "import os, runpy, sys; os.chdir(sys.argv.pop(1)); "
        .. "runpy.run_module('ipykernel_launcher', run_name='__main__', alter_sys=True)",
      dir, "-f", "{connection_file}",
    },
    display_name = ("Python %s (%s)"):format(it.version or "?", where),
    language = "python",
    env = env,
    metadata = { debugger = true },
  }
  local d = M.dir .. "/kernels/" .. name
  vim.fn.mkdir(d, "p")
  vim.fn.writefile({ vim.json.encode(spec) }, d .. "/kernel.json")
  return name, spec.display_name
end

local function start(buf, kernel, display, cb)
  local ok, err = pcall(in_buf, buf, function()
    if #M.attached(buf) > 0 then vim.cmd("MoltenDeinit") end -- switching, as in VS Code
    vim.cmd("MoltenInit " .. kernel)
  end)
  if not ok then return notify("MoltenInit failed: " .. tostring(err), vim.log.levels.ERROR) end
  vim.b[buf].molten_kernel = display
  local ids = M.attached(buf)
  if cb and ids[1] then cb(ids[#ids]) end
end

local function run(cmd, opts, done)
  vim.system(cmd, opts or {}, vim.schedule_wrap(done))
end

local function confirm(prompt, choices, fn)
  vim.ui.select(choices, { prompt = prompt }, function(choice)
    if choice and choice ~= "Cancel" then fn(choice) end
  end)
end

-- Facts that need the interpreter itself: exact version, ipykernel, PEP 668.
local PROBE = table.concat({
  "import importlib.util as u, os, sys, sysconfig",
  "print(sys.version.split()[0])",
  "print(int(u.find_spec('ipykernel') is not None))",
  "print(int(sys.prefix != sys.base_prefix))",
  "print(int(os.path.exists(os.path.join(sysconfig.get_path('stdlib'), 'EXTERNALLY-MANAGED'))))",
}, "\n")

local function probe(python, cb)
  run({ python, "-c", PROBE }, { cwd = "/", timeout = 15000 }, function(r)
    local out = vim.split(r.stdout or "", "\n")
    if r.code ~= 0 or not out[4] then return cb(nil, r.stderr) end
    cb({ version = out[1], ipykernel = out[2] == "1", venv = out[3] == "1", managed = out[4] == "1" })
  end)
end

local function install_ipykernel(it, cb)
  local cmd = vim.fn.executable("uv") == 1 and it.kind == "venv"
      and { "uv", "pip", "install", "--python", it.python, "ipykernel" }
    or { it.python, "-m", "pip", "install", "ipykernel" }
  notify(("Installing ipykernel into %s…"):format(tilde(it.prefix)))
  run(cmd, { timeout = 300000 }, function(r)
    if r.code ~= 0 then
      return notify("Installing ipykernel failed:\n" .. vim.trim(r.stderr or ""), vim.log.levels.ERROR)
    end
    cb()
  end)
end

-- Create <root>/.venv (from `base`, an interpreter path, if given) with pip
-- and ipykernel, then start it.
function M.create_venv(buf, base, cb)
  local root = M.root(buf)
  local prefix = root .. "/.venv"
  if exists(prefix) then return notify(tilde(prefix) .. " already exists", vim.log.levels.WARN) end
  local cmd
  if vim.fn.executable("uv") == 1 then
    cmd = { "uv", "venv", "--seed", prefix } -- --seed: pip inside, so %pip works
    if base then vim.list_extend(cmd, { "--python", base }) end
  else
    base = base or vim.fn.exepath("python3")
    cmd = { base, "-m", "venv", prefix }
  end
  notify(("Creating %s…"):format(tilde(prefix)))
  run(cmd, { cwd = root, timeout = 300000 }, function(r)
    if r.code ~= 0 then
      return notify("Creating the venv failed:\n" .. vim.trim(r.stderr or ""), vim.log.levels.ERROR)
    end
    local python = env_python(prefix)
    if python then M.use(buf, vim.tbl_extend("force", M.describe(python), { project = true }), cb, true) end
  end)
end

-- Start `choice` (an interpreter record or { kernel = name }) for `buf`, then
-- cb(kernel_id). `yes` skips the ipykernel confirmation.
function M.use(buf, choice, cb, yes)
  buf = bufnr(buf)
  if not available() then return end
  if choice.kernel then
    remember(buf, { kernel = choice.kernel })
    local s = M.kernelspecs()[choice.kernel]
    return start(buf, choice.kernel, s and s.display or choice.kernel, cb)
  end
  local it = choice
  local root, dir = M.root(buf)
  probe(it.python, function(info, err)
    if not info then
      return notify(("Couldn't run %s:\n%s"):format(it.python, vim.trim(err or "")), vim.log.levels.ERROR)
    end
    it.version = info.version
    local function go()
      remember(buf, { python = it.python })
      local name, display = write_spec(it, dir, root)
      start(buf, name, display, cb)
    end
    if info.ipykernel then return go() end
    if info.managed and not info.venv then
      return confirm(("%s is externally managed (PEP 668), so ipykernel can't be installed into it"):format(
        tilde(it.python)), { "Create " .. tilde(root) .. "/.venv from it", "Cancel" }, function()
        M.create_venv(buf, it.python, cb)
      end)
    end
    if yes then return install_ipykernel(it, go) end
    confirm(("ipykernel isn't installed in %s"):format(label(it, root)), { "Install ipykernel", "Cancel" },
      function() install_ipykernel(it, go) end)
  end)
end

-- ── picker ───────────────────────────────────────────────────────────────

function M.pick(buf, cb)
  buf = bufnr(buf)
  if not available() then return end
  prune()
  local interpreters, root = M.interpreters(buf)
  local current = remembered(buf)
  local function is_current(item)
    return current and (item.python and item.python == current.python or item.kernel and item.kernel == current.kernel)
  end
  -- the remembered choice first, then interpreters (already ranked), kernels
  local items, rest, has_project = {}, {}, false
  local function add(item) table.insert(is_current(item) and items or rest, item) end
  for _, it in ipairs(interpreters) do
    add(it)
    has_project = has_project or it.project
  end
  local specs = vim.tbl_values(M.kernelspecs())
  table.sort(specs, function(a, b) return a.display < b.display end)
  for _, s in ipairs(specs) do
    if not vim.startswith(s.name, M.prefix) then add({ kernel = s.name, display = s.display, language = s.language }) end
  end
  vim.list_extend(items, rest)
  if not has_project then items[#items + 1] = { action = "create" } end
  items[#items + 1] = { action = "path" }
  local function display(item)
    local mark = is_current(item) and "●" or item.project and "★" or item.active and "▶" or " "
    if item.action == "create" then
      return ("+ Create %s/.venv%s"):format(tilde(root), vim.fn.executable("uv") == 1 and " (uv)" or "")
    elseif item.action == "path" then
      return "  Enter interpreter path…"
    elseif item.kernel then
      return ("%s %-14s %-7s %s"):format(mark, item.display, "kernel", item.language)
    end
    return ("%s Python %-7s %-7s %s"):format(mark, item.version or "?", item.kind, label(item, root))
  end
  local function choose(item)
    if item.action == "create" then return M.create_venv(buf, nil, cb) end
    if item.action == "path" then
      return vim.ui.input({ prompt = "Python interpreter: ", completion = "file" }, function(path)
        if not path or path == "" then return end
        path = vim.fn.expand(path)
        if vim.fn.isdirectory(path) == 1 then path = env_python(path) or path end
        if vim.fn.executable(path) == 0 then return notify(path .. " isn't executable", vim.log.levels.ERROR) end
        M.use(buf, M.describe(path), cb)
      end)
    end
    M.use(buf, item, cb)
  end

  local actions = require("telescope.actions")
  local state = require("telescope.actions.state")
  require("telescope.pickers")
    .new({}, {
      prompt_title = "Kernel for " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t"),
      finder = require("telescope.finders").new_table({
        results = items,
        entry_maker = function(item)
          local d = display(item)
          return { value = item, display = d, ordinal = d .. " " .. (item.python or item.kernel or "") }
        end,
      }),
      sorter = require("telescope.config").values.generic_sorter({}),
      attach_mappings = function(bufnr)
        actions.select_default:replace(function()
          local e = state.get_selected_entry()
          actions.close(bufnr)
          if e then choose(e.value) end
        end)
        return true
      end,
    })
    :find()
end

-- First fenced cell language in the buffer ("" if none): decides whether a
-- Python interpreter may be picked automatically (an R-only .qmd must not).
local function buffer_language(buf)
  for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local lang = l:match("^```{?(%a[%w_+-]*)")
    if lang then return M.normalize_language(lang) end
  end
  return vim.bo[buf].filetype == "python" and "python" or ""
end

-- cb(kernel_id) with a kernel attached to `buf`, starting one if needed: the
-- remembered choice, else the only project venv (or the only registered kernel
-- for the buffer's language), else the picker.
function M.ensure(buf, cb)
  buf = bufnr(buf)
  if not available() then return end
  local ids = M.attached(buf)
  if #ids == 1 then return cb(ids[1]) end
  if #ids > 1 then
    return vim.ui.select(ids, { prompt = "Kernel" }, function(id) if id then cb(id) end end)
  end
  local saved = remembered(buf)
  if saved then return M.use(buf, saved, cb) end
  local lang = buffer_language(buf)
  if lang == "python" or lang == "" then
    local project = vim.tbl_filter(function(it) return it.project or it.active end, (M.interpreters(buf)))
    if #project == 1 then
      notify(("Using %s"):format(label(project[1], (M.root(buf)))))
      return M.use(buf, project[1], cb)
    end
  else
    local match = vim.tbl_filter(function(s) return M.normalize_language(s.language) == lang end,
      vim.tbl_values(M.kernelspecs()))
    if #match == 1 then return M.use(buf, { kernel = match[1].name }, cb) end
  end
  M.pick(buf, cb)
end

-- Before the Python host starts (lua/plugins/molten.lua's init).
function M.setup()
  local paths = vim.env.JUPYTER_PATH
  if not (paths or ""):find(M.dir, 1, true) then
    vim.env.JUPYTER_PATH = M.dir .. (paths and paths ~= "" and ":" .. paths or "")
  end
  vim.api.nvim_create_user_command("Kernel", function(o)
    if o.args == "" then return M.pick() end
    local path = vim.fn.expand(o.args)
    if vim.fn.isdirectory(path) == 1 then path = env_python(path) or path end
    M.use(vim.api.nvim_get_current_buf(), M.describe(path))
  end, { nargs = "?", complete = "file", desc = "Pick the notebook's kernel (interpreter, venv or kernelspec)" })
  vim.api.nvim_create_autocmd("User", {
    pattern = "MoltenDeinitPost",
    callback = function() vim.b.molten_kernel = nil end,
  })
end

-- The attached kernel's name for the statusline (set by `start`, cleared on
-- MoltenDeinitPost), so drawing it never calls into the Python host.
function M.statusline()
  return vim.b.molten_kernel and ("󰌠 " .. vim.b.molten_kernel) or ""
end

return M
