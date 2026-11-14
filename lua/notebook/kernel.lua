-- Kernels without registration (issue #40, phase 2).
--
-- The first run in a buffer with no Molten kernel picks one and starts it:
--   * Python: a kernelspec generated for the project's environment
--     (lua/pyenv.lua) in a private dir under stdpath("data"), never in
--     ~/Library/Jupyter. If the venv has ipykernel, its python runs it
--     directly; otherwise `uv run --with ipykernel` layers an ephemeral
--     ipykernel over the venv, so nothing is installed into it.
--   * Other languages (R, Julia): the kernel the notebook's metadata names,
--     else the first installed kernel for that language (R = IRkernel's `ir`).
--
-- The private dir reaches Molten through $JUPYTER_PATH, set in setup() before
-- the Python host starts (it inherits Neovim's environment when it spawns).
local M = {}

M.dir = vim.fn.stdpath("data") .. "/jupyter"
local KDIR = M.dir .. "/kernels"

function M.setup()
  local cur = vim.env.JUPYTER_PATH
  if not (cur and (":" .. cur .. ":"):find(":" .. M.dir .. ":", 1, true)) then
    vim.env.JUPYTER_PATH = M.dir .. (cur and cur ~= "" and ":" .. cur or "")
  end
end

-- ---------------------------------------------------------------------------
-- Installed kernelspecs (read directly: no subprocess, no Python host)

local function data_dirs()
  local dirs = vim.split(vim.env.JUPYTER_PATH or "", ":", { trimempty = true })
  local host = vim.g.python3_host_prog and vim.fs.dirname(vim.fs.dirname(vim.fn.expand(vim.g.python3_host_prog)))
  vim.list_extend(dirs, {
    vim.fn.expand("~/Library/Jupyter"),
    host and host .. "/share/jupyter" or nil,
    "/opt/homebrew/share/jupyter",
    "/usr/local/share/jupyter",
    "/usr/share/jupyter",
  })
  return dirs
end

local function read_json(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return nil end
  local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  return ok2 and data or nil
end

--- name -> { language, display_name, dir }, first data dir wins (as Jupyter does).
function M.installed()
  local out = {}
  for _, d in ipairs(data_dirs()) do
    for name, kind in vim.fs.dir(d .. "/kernels") do
      if kind == "directory" and not out[name] then
        local spec = read_json(("%s/kernels/%s/kernel.json"):format(d, name))
        if spec then
          out[name] = { language = (spec.language or ""):lower(), display_name = spec.display_name, dir = d }
        end
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- What the buffer wants

local function norm_lang(l)
  l = (l or ""):lower()
  if l == "python3" or l == "ipython" or l == "py" then return "python" end
  return l ~= "" and l or nil
end

--- Kernel name + language from the YAML front matter (jupytext markdown of an
--- .ipynb, or a .qmd's `jupyter:` key) and the first code fence.
function M.wanted(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, math.min(vim.api.nvim_buf_line_count(buf), 400), false)
  local name, lang
  if lines[1] == "---" then
    local in_spec = false
    for i = 2, #lines do
      local l = lines[i]
      if l == "---" or l == "..." then break end
      local short = l:match("^jupyter:%s*([%w_.-]+)%s*$") -- qmd: `jupyter: ir`
      if short then name = short end
      if l:match("^%s*kernelspec:%s*$") then
        in_spec = true
      elseif in_spec and l:match("^%s+") then
        name = l:match("^%s+name:%s*['\"]?([%w_.-]+)") or name
        lang = l:match("^%s+language:%s*['\"]?([%w_.-]+)") or lang
      elseif not l:match("^%s") then
        in_spec = false
      end
    end
  end
  if not lang then
    -- the code cell being run (an R chunk in a .qmd that starts with Python
    -- wants R), else the first real one (not a ```bash fence in prose)
    local cells = require("notebook.cells")
    local line = vim.api.nvim_get_current_buf() == buf and vim.api.nvim_win_get_cursor(0)[1] or 0
    local c, _, all = cells.at(line, buf)
    c = c or all[1]
    lang = c and c.lang
  end
  lang = norm_lang(lang) or (vim.bo[buf].filetype == "r" and "r") or "python"
  return name, lang
end

-- ---------------------------------------------------------------------------
-- Generated Python kernelspecs

local function spec_name(env)
  local key = env.prefix or env.python
  local label = env.prefix and vim.fs.basename(vim.fs.dirname(env.prefix)) or "system"
  label = label:gsub("[^%w_.-]", "_"):sub(1, 24)
  return ("py-%s-%s"):format(label, vim.fn.sha256(key):sub(1, 6)), label
end

local function has_ipykernel(prefix)
  return prefix and #vim.fn.glob(prefix .. "/lib/python*/site-packages/ipykernel", false, true) > 0
end

-- Drop generated specs whose interpreter is gone (deleted or broken venvs).
local function sweep()
  for name, kind in vim.fs.dir(KDIR) do
    if kind == "directory" then
      local spec = read_json(("%s/%s/kernel.json"):format(KDIR, name))
      local py = spec and vim.tbl_get(spec, "metadata", "nvim", "python")
      if py and vim.fn.executable(py) == 0 then vim.fn.delete(KDIR .. "/" .. name, "rf") end
    end
  end
end

-- Working directory. Molten can't pass one, so jupyter_client would start
-- every kernel in the Python host's cwd (Neovim's cwd when the host spawned).
-- Chunks are written for the document's folder instead (`source("../R/x.R")`,
-- `pd.read_csv("data.csv")`), as Quarto/knitr and Jupyter run them, so the
-- spec (rewritten on every start) carries it: `sh` cds and execs the kernel,
-- whose pid stays the one jupyter_client signals.
local function doc_dir(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
end

local function in_dir(dir, argv)
  return vim.list_extend({ "/bin/sh", "-c", 'cd "$0" && exec "$@"', dir }, argv)
end

--- Write (or refresh) the kernelspec for a Python environment, started in
--- `dir` (the document's folder).
---@param env PyEnv
---@param dir? string
---@return string? name, string? how_or_error
function M.python_spec(env, dir)
  local name, label = spec_name(env)
  local argv, how
  if has_ipykernel(env.prefix) then
    argv, how = { env.python }, "its ipykernel"
  elseif vim.fn.executable("uv") == 1 then
    argv = { vim.fn.exepath("uv"), "run", "--quiet", "--no-project", "--python", env.python, "--with", "ipykernel", "python" }
    how = "uv + ephemeral ipykernel"
  else
    return nil, ("%s has no ipykernel and `uv` isn't installed: install one of them"):format(env.prefix or env.python)
  end
  local plots = require("notebook.plots")
  vim.list_extend(argv, {
    "-m", "ipykernel_launcher", "-f", "{connection_file}",
    "--IPKernelApp.exec_files=" .. plots.startup_py, -- plot paper hook
  })
  if dir then argv = in_dir(dir, argv) end
  local kenv = plots.kernel_env()
  if env.prefix then
    -- `!pip`, `!python` and subprocesses inside the kernel see the venv
    kenv.VIRTUAL_ENV = env.prefix
    kenv.PATH = env.prefix .. "/bin:${PATH}"
  end
  local spec = {
    argv = argv,
    display_name = ("Python (%s)"):format(label),
    language = "python",
    env = kenv,
    metadata = { nvim = { python = env.python, prefix = env.prefix } },
  }
  sweep()
  vim.fn.mkdir(KDIR .. "/" .. name, "p")
  vim.fn.writefile({ vim.json.encode(spec) }, ("%s/%s/kernel.json"):format(KDIR, name))
  return name, how
end

-- R's own libraries (system + user), as R sees them without any profile.
-- renv projects replace .libPaths() with the project library (and a sandbox
-- standing in for the system one), so IRkernel, installed machine-wide, is
-- gone and the kernel dies on startup. Queried once per session.
local global_libs
local function r_global_libs(r)
  if global_libs == nil then
    local res = vim.system({ r, "--vanilla", "--slave", "-e", 'cat(.libPaths(), sep = "\\n")' }, { text = true }):wait(5000)
    global_libs = res.code == 0 and vim.split(vim.trim(res.stdout or ""), "\n", { trimempty = true }) or {}
  end
  return global_libs
end

--- R code that makes IRkernel loadable inside a renv (or packrat) project:
--- the global libraries go *after* the project's, so the project's packages
--- still win and only what it lacks (IRkernel and its deps) comes from them.
local function r_libfix(r)
  local libs = vim.tbl_map(function(p) return ("%q"):format(p) end, r_global_libs(r))
  local fallback = 'file.path(R.home(), "library")'
  return ('if (!requireNamespace("IRkernel", quietly = TRUE)) .libPaths(c(.libPaths(), %s))'):format(
    #libs > 0 and table.concat(libs, ", ") or fallback)
end

--- An installed IRkernel spec, wrapped to source kernel_startup.R (plot
--- paper) before IRkernel::main(), and to find IRkernel inside renv projects.
--- R starts in the project root (the nearest renv.lock/.Rprofile, so the
--- project's profile and renv run as in an R session there) and then works
--- in the document's folder, as knitr does.
--- Returns the wrapper's name, or `name` unchanged when the spec doesn't look
--- like IRkernel's.
local function wrap_r(name, info, dir)
  local spec = read_json(("%s/kernels/%s/kernel.json"):format(info.dir, name))
  if not spec or type(spec.argv) ~= "table" then return name end
  local plots = require("notebook.plots")
  local argv, found = {}, false
  for _, a in ipairs(spec.argv) do
    if a:find("IRkernel::main()", 1, true) then
      a = ("%s; setwd(%q); source(%q); %s"):format(r_libfix(spec.argv[1]), dir, plots.startup_r, a)
      found = true
    end
    argv[#argv + 1] = a
  end
  if not found then return name end
  local wrapped = name .. "-nvim"
  spec.argv = in_dir(vim.fs.root(dir, { "renv.lock", ".Rprofile" }) or dir, argv)
  spec.display_name = (spec.display_name or name) .. " (nvim)"
  spec.env = vim.tbl_extend("force", spec.env or {}, plots.kernel_env())
  spec.metadata = vim.tbl_extend("force", spec.metadata or {}, { nvim = { wraps = name } })
  vim.fn.mkdir(KDIR .. "/" .. wrapped, "p")
  vim.fn.writefile({ vim.json.encode(spec) }, ("%s/%s/kernel.json"):format(KDIR, wrapped))
  return wrapped
end

local function use(name, info, desc, dir)
  if info.language == "r" and not name:match("%-nvim$") then name = wrap_r(name, info, dir) end
  return name, desc
end

--- The kernel a buffer should use.
---@return string? name, string? description_or_error
function M.pick(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local name, lang = M.wanted(buf)
  local installed = M.installed()
  local dir = doc_dir(buf)
  if lang == "python" then
    local env = require("pyenv").find(buf)
    -- a project environment always wins; without one, honour the notebook's
    -- own (registered) kernel before falling back to the system Python
    if env.source == "system" and name and installed[name] and installed[name].language == "python" then
      return name, "from the notebook's metadata"
    end
    local k, how = M.python_spec(env, dir)
    if not k then return nil, how end
    return k, ("%s (%s, %s)"):format(env.python, env.source, how)
  end
  if name and installed[name] then return use(name, installed[name], "from the notebook's metadata", dir) end
  local names = vim.tbl_keys(installed)
  table.sort(names)
  for _, n in ipairs(names) do
    -- skip our own wrappers here: the original is found and re-wrapped fresh
    if installed[n].language == lang and not n:match("%-nvim$") then
      return use(n, installed[n], installed[n].display_name, dir)
    end
  end
  local hint = lang == "r" and ' (install.packages("IRkernel"); IRkernel::installspec())' or ""
  return nil, ("no Jupyter kernel installed for %s%s"):format(lang, hint)
end

-- ---------------------------------------------------------------------------
-- Molten glue

local function running()
  local ok, ks = pcall(vim.fn.MoltenRunningKernels, true)
  if not ok then return nil end
  return ks
end

-- Why the checks below exist: until a kernel answers kernel_info, every
-- Molten tick (a *synchronous* call, every 500 ms) runs jupyter_client's
-- wait_for_ready(timeout=0), which still blocks up to ~1.2 s on the shell
-- channel. Neovim freezes while a kernel boots, and for good if it dies on
-- startup (Molten never gives up on it). So a kernel is only handed to Molten
-- once its command is known to work, and one that doesn't come up in time is
-- shut down.
M.ready_timeout = 30000

-- Where Molten's kernels start: the Python host's cwd (jupyter_client's
-- default), which is Neovim's cwd when the host spawned, not today's :cd.
local function host_cwd()
  local ok, cwd = pcall(vim.fn.py3eval, "__import__('os').getcwd()")
  return ok and cwd or vim.fn.getcwd()
end

local function spec_file(name)
  for _, d in ipairs(data_dirs()) do
    local f = ("%s/kernels/%s/kernel.json"):format(d, name)
    if vim.uv.fs_stat(f) then return read_json(f) end
  end
end

--- A quick command that fails the way the kernel would: the same interpreter,
--- env and cwd, importing ipykernel (which also fills uv's cache, the slow
--- part of a first `uv run --with ipykernel`) or loading IRkernel after the
--- same profile/renv/libPaths steps. nil for kernels we don't know.
local function preflight_cmd(spec)
  local argv = spec.argv or {}
  for i, a in ipairs(argv) do
    if a == "-m" and argv[i + 1] == "ipykernel_launcher" then
      local cmd = vim.list_slice(argv, 1, i - 1)
      vim.list_extend(cmd, { "-c", "import ipykernel" })
      return cmd
    end
    if (a == "-e" or a == "--eval") and (argv[i + 1] or ""):find("IRkernel::main()", 1, true) then
      local cmd = vim.list_slice(argv, 1, i)
      cmd[#cmd + 1] = argv[i + 1]:gsub("IRkernel::main%(%)",
        'quit(status = if (requireNamespace("IRkernel", quietly = TRUE)) 0 else 3)')
      return cmd
    end
  end
end

local function preflight(name, cwd, done)
  local spec = spec_file(name)
  if not spec then return done(true) end
  local cmd = preflight_cmd(spec)
  if not cmd then return done(true) end
  local env = {}
  for k, v in pairs(spec.env or {}) do
    env[k] = tostring(v):gsub("%${PATH}", vim.env.PATH or "")
  end
  local ok, err = pcall(vim.system, cmd, { cwd = cwd, env = env, text = true, timeout = 300000 }, function(res)
    vim.schedule(function()
      if res.code == 0 then return done(true) end
      local out = vim.trim((res.stderr or "") .. "\n" .. (res.stdout or ""))
      local tail = vim.list_slice(vim.split(out, "\n"), math.max(1, #vim.split(out, "\n") - 8))
      if res.code == 3 then
        tail = { ("IRkernel isn't loadable from %s"):format(cwd), unpack(tail) }
      elseif res.signal == 15 or res.signal == 9 then
        tail = { "timed out", unpack(tail) }
      elseif out == "" then
        tail = { ("%s exited with code %d"):format(cmd[1], res.code) }
      end
      done(false, table.concat(tail, "\n"))
    end)
  end)
  if not ok then done(false, tostring(err)) end
end

local starting = {} -- buf -> callbacks waiting for its kernel

--- Make sure the current buffer has a kernel, then call `fn`.
---@param fn? fun()
function M.ensure(fn)
  local ks = running()
  if not ks then
    return vim.notify("Molten isn't available (run :UpdateRemotePlugins and restart)", vim.log.levels.ERROR)
  end
  if #ks > 0 then
    if fn then fn() end
    return
  end
  local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  if starting[buf] then
    -- a second run while the kernel starts: queue it behind the first
    if fn then table.insert(starting[buf], fn) end
    return
  end
  local name, desc = M.pick()
  if not name then return vim.notify("Kernel: " .. desc, vim.log.levels.ERROR) end
  starting[buf] = { fn }
  local cwd = host_cwd()
  vim.notify(("Starting kernel %s…"):format(name))

  local function finish(run)
    local fns = starting[buf] or {}
    starting[buf] = nil
    if not run or not (vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf) then return end
    vim.api.nvim_win_call(win, function()
      -- outputs saved in the notebook come back with its kernel
      if vim.api.nvim_buf_get_name(buf):match("%.ipynb$") then pcall(vim.cmd, "MoltenImportOutput") end
      for _, f in pairs(fns) do f() end
    end)
  end

  preflight(name, cwd, function(ok, err)
    if not ok then
      starting[buf] = nil
      return vim.notify(("Kernel %s can't start (nothing was handed to Molten):\n%s"):format(name, err),
        vim.log.levels.ERROR)
    end
    if not vim.api.nvim_buf_is_valid(buf) then starting[buf] = nil return end
    -- Evaluate only once the kernel is ready, as Molten's own init-and-run
    -- does: output sent while it is still starting goes out before Molten is
    -- listening, and the cell stays "On Hold" although the code ran.
    local ready = false
    local au = vim.api.nvim_create_autocmd("User", {
      pattern = "MoltenKernelReady",
      once = true,
      callback = function()
        ready = true
        finish(true)
      end,
    })
    vim.api.nvim_buf_call(buf, function() vim.cmd("MoltenInit " .. name) end)
    if #(running() or {}) == 0 then -- Molten has reported why
      pcall(vim.api.nvim_del_autocmd, au)
      starting[buf] = nil
      return
    end
    vim.notify(("Kernel %s: %s"):format(name, desc))
    -- a kernel that never answers would keep Molten's tick blocking forever
    vim.defer_fn(function()
      if ready then return end
      pcall(vim.api.nvim_del_autocmd, au)
      finish(false)
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_call(buf, function() pcall(vim.cmd, "MoltenDeinit") end)
      end
      vim.notify(("Kernel %s didn't answer within %d s; shut it down"):format(name, M.ready_timeout / 1000),
        vim.log.levels.ERROR)
    end, M.ready_timeout)
  end)
end

return M
