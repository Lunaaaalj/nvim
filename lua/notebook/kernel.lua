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
    for _, l in ipairs(lines) do
      local f = l:match("^```{?([%a]+)")
      if f then lang = f break end
    end
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

--- Write (or refresh) the kernelspec for a Python environment.
---@param env PyEnv
---@return string? name, string? how_or_error
function M.python_spec(env)
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

--- An installed IRkernel spec, wrapped to source kernel_startup.R (plot
--- paper) before IRkernel::main(). Returns the wrapper's name, or `name`
--- unchanged when the spec doesn't look like IRkernel's.
local function wrap_r(name, info)
  local spec = read_json(("%s/kernels/%s/kernel.json"):format(info.dir, name))
  if not spec or type(spec.argv) ~= "table" then return name end
  local plots = require("notebook.plots")
  local argv, found = {}, false
  for _, a in ipairs(spec.argv) do
    if a:find("IRkernel::main()", 1, true) then
      a = ("source(%q); %s"):format(plots.startup_r, a)
      found = true
    end
    argv[#argv + 1] = a
  end
  if not found then return name end
  local wrapped = name .. "-nvim"
  spec.argv = argv
  spec.display_name = (spec.display_name or name) .. " (nvim)"
  spec.env = vim.tbl_extend("force", spec.env or {}, plots.kernel_env())
  spec.metadata = vim.tbl_extend("force", spec.metadata or {}, { nvim = { wraps = name } })
  vim.fn.mkdir(KDIR .. "/" .. wrapped, "p")
  vim.fn.writefile({ vim.json.encode(spec) }, ("%s/%s/kernel.json"):format(KDIR, wrapped))
  return wrapped
end

local function use(name, info, desc)
  if info.language == "r" and not name:match("%-nvim$") then name = wrap_r(name, info) end
  return name, desc
end

--- The kernel a buffer should use.
---@return string? name, string? description_or_error
function M.pick(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local name, lang = M.wanted(buf)
  local installed = M.installed()
  if lang == "python" then
    local env = require("pyenv").find(buf)
    -- a project environment always wins; without one, honour the notebook's
    -- own (registered) kernel before falling back to the system Python
    if env.source == "system" and name and installed[name] and installed[name].language == "python" then
      return name, "from the notebook's metadata"
    end
    local k, how = M.python_spec(env)
    if not k then return nil, how end
    return k, ("%s (%s, %s)"):format(env.python, env.source, how)
  end
  if name and installed[name] then return use(name, installed[name], "from the notebook's metadata") end
  local names = vim.tbl_keys(installed)
  table.sort(names)
  for _, n in ipairs(names) do
    -- skip our own wrappers here: the original is found and re-wrapped fresh
    if installed[n].language == lang and not n:match("%-nvim$") then
      return use(n, installed[n], installed[n].display_name)
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

--- Make sure the current buffer has a kernel, then call `fn`.
---@param fn? fun()
function M.ensure(fn)
  local ks = running()
  if not ks then
    return vim.notify("Molten isn't available (run :UpdateRemotePlugins and restart)", vim.log.levels.ERROR)
  end
  if #ks == 0 then
    local name, desc = M.pick()
    if not name then return vim.notify("Kernel: " .. desc, vim.log.levels.ERROR) end
    -- Evaluate only once the kernel is ready, as Molten's own init-and-run
    -- does: output sent while it is still starting goes out before Molten is
    -- listening, and the cell stays "On Hold" although the code ran.
    local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
    if fn then
      vim.api.nvim_create_autocmd("User", {
        pattern = "MoltenKernelReady",
        once = true,
        callback = function()
          if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
            vim.api.nvim_win_call(win, fn)
          end
        end,
      })
    end
    vim.cmd("MoltenInit " .. name)
    if #(running() or {}) == 0 then return end -- Molten has reported why
    vim.notify(("Kernel %s: %s"):format(name, desc))
    return
  end
  if fn then fn() end
end

return M
