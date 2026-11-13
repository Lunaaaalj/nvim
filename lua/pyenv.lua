-- The one answer to "which Python does this project use?", shared by pyright,
-- dap-python (the debuggee), the <leader>tp REPL and refdocs' pydoc.
--
-- Order: a venv directory (.venv / venv / env / .env) in the file's directory
-- or any parent up to $HOME, then an activated $VIRTUAL_ENV / $CONDA_PREFIX,
-- then the first python3 on PATH. Neovim's own host venv
-- (g:python3_host_prog) is never returned: it holds pynvim/jupyter_client,
-- not the project's packages.
local M = {}

M.venv_names = { ".venv", "venv", "env", ".env" }

local function host_prefix()
  local p = vim.g.python3_host_prog
  return p and vim.fs.dirname(vim.fs.dirname(vim.fn.expand(p)))
end

local warned = {}

-- A venv whose interpreter is a dangling symlink, usually because
-- `brew upgrade` removed the Cellar path it was created from. executable()
-- says no, so without this the lookup would silently fall through to the
-- system Python and every import would show as unresolved.
local function check_broken(prefix)
  if warned[prefix] or vim.fn.filereadable(prefix .. "/pyvenv.cfg") == 0 then return end
  warned[prefix] = true
  vim.schedule(function()
    vim.notify(
      ("pyenv: %s is broken (its Python is gone, e.g. after a Homebrew upgrade). "
        .. "Repoint it with `python3 -m venv --upgrade %s`, or recreate it."):format(prefix, prefix),
      vim.log.levels.WARN
    )
  end)
end

local function usable(prefix)
  if not prefix or prefix == "" or prefix == host_prefix() then return nil end
  local py = prefix .. "/bin/python"
  if vim.fn.executable(py) == 1 then return py end
  check_broken(prefix)
end

local function start_dir(src)
  if type(src) == "string" and src ~= "" then
    return vim.fn.isdirectory(src) == 1 and src or vim.fs.dirname(src)
  end
  local name = vim.api.nvim_buf_get_name(src or 0)
  -- skip non-file buffers (terminals, ref://, oil://...)
  if name ~= "" and not name:match("^%a[%w+.-]*://") then return vim.fs.dirname(name) end
  return vim.fn.getcwd()
end

local function system_python()
  local host_bin = host_prefix() and host_prefix() .. "/bin"
  for dir in vim.gsplit(vim.env.PATH or "", ":", { plain = true }) do
    local p = dir .. "/python3"
    if dir ~= host_bin and vim.fn.executable(p) == 1 then return p end
  end
  return "python3"
end

---@class PyEnv
---@field python string   interpreter path (or bare "python3" as a last resort)
---@field prefix? string  the venv / conda prefix, nil for the system Python
---@field source "project"|"VIRTUAL_ENV"|"CONDA_PREFIX"|"system"

--- Resolve the environment for a buffer (default: current), a file or a directory.
---@param src? integer|string
---@return PyEnv
function M.find(src)
  local home = vim.env.HOME
  for dir in vim.fs.parents(start_dir(src) .. "/x") do
    for _, v in ipairs(M.venv_names) do
      local prefix = dir .. "/" .. v
      local py = usable(prefix)
      if py then return { python = py, prefix = prefix, source = "project" } end
    end
    if dir == home then break end
  end
  for _, var in ipairs({ "VIRTUAL_ENV", "CONDA_PREFIX" }) do
    local py = usable(vim.env[var])
    if py then return { python = py, prefix = vim.env[var], source = var } end
  end
  return { python = system_python(), source = "system" }
end

--- Interpreter path for a buffer, file or directory.
---@param src? integer|string
function M.python(src)
  return M.find(src).python
end

--- Environment variables that make a child process behave as if the venv were
--- activated (for terminals; the interpreter path alone is enough elsewhere).
---@param env PyEnv
function M.activate_env(env)
  if not env.prefix then return {} end
  return {
    VIRTUAL_ENV = env.prefix,
    PATH = env.prefix .. "/bin:" .. (vim.env.PATH or ""),
  }
end

vim.api.nvim_create_user_command("PyEnv", function()
  local e = M.find()
  vim.notify(("%s\n  source: %s"):format(e.python, e.source))
end, { desc = "Show the Python environment this buffer resolves to" })

return M
