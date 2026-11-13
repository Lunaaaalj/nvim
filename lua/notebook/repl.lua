-- The REPL engine for `# %%` scripts (issue #40, phase 5): cells go to the
-- pinned IPython / R terminals (lua/terminals) instead of a Molten kernel.
-- Notebooks (.ipynb/.qmd) keep Molten; <leader>mE switches a buffer.
--
-- Plots can't be drawn inside a Neovim :terminal (it doesn't pass kitty
-- graphics through), so the REPLs save each figure as a PNG and tell the
-- parent Neovim ($NVIM, set for every terminal job), which shows it in the
-- image split (notebook/plots.lua show_file): Python through a tiny
-- matplotlib backend (python/nvim_mpl.py), R through a task callback that
-- replays the display list into a PNG (repl_profile.R). Both use the plot
-- paper (theme / white).
local M = {}

local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))

--- Environment shared by the pinned REPLs (plots back into Neovim).
function M.env()
  local plots = require("notebook.plots")
  local env = plots.kernel_env()
  env.NVIM_PROG = vim.v.progpath
  env.MPLBACKEND = "module://nvim_mpl"
  env.PYTHONPATH = here .. "/python" .. (vim.env.PYTHONPATH and ":" .. vim.env.PYTHONPATH or "")
  -- R reads only R_PROFILE_USER when it is set, so the profile sources the
  -- one R would have read (./.Rprofile — renv —, else ~/.Rprofile) first.
  env.NVIM_R_PROFILE_ORIG = vim.env.R_PROFILE_USER or ""
  env.R_PROFILE_USER = here .. "/repl_profile.R"
  return env
end

--- Command for the Python REPL: IPython from the venv, else an ephemeral
--- IPython layered over it by uv (nothing installed), else plain python.
---@return string cmd, table env, table info
function M.python()
  local pyenv = require("pyenv")
  local e = pyenv.find()
  local env = vim.tbl_extend("force", M.env(), pyenv.activate_env(e))
  local q = vim.fn.shellescape
  local ipython = e.prefix and e.prefix .. "/bin/ipython"
  local cmd, bracketed
  if ipython and vim.fn.executable(ipython) == 1 then
    cmd, bracketed = q(ipython) .. " --no-banner", true
  elseif vim.fn.executable("uv") == 1 then
    cmd = ("%s run --quiet --no-project --python %s --with ipython ipython --no-banner"):format(
      q(vim.fn.exepath("uv")), q(e.python))
    bracketed = true
  else
    cmd = q(e.python)
  end
  return cmd, env, { interp = e.python, bracketed = bracketed }
end

--- Command for the R REPL: radian if installed, else R.
function M.r()
  local cmd = vim.fn.executable("radian") == 1 and "radian" or "R --no-save --quiet"
  return cmd, M.env(), { interp = cmd }
end

-- ---------------------------------------------------------------------------
-- Sending cells

local keys = { python = "python", r = "R" }

local prompts = {
  python = { "^In %[%d+%]:", "^>>> ?$" },
  R = { "^> ?$", "^r%$> ?$" },
}

local function ready(key, buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i = #lines, math.max(1, #lines - 30), -1 do
    local l = vim.trim(lines[i])
    if l ~= "" then
      for _, p in ipairs(prompts[key]) do
        if l:match(p) then return true end
      end
      return false
    end
  end
  return false
end

--- Can this language go to a REPL?
function M.supports(lang)
  return keys[lang] ~= nil
end

--- Send cells (one paste, so IPython runs them as one input) to the REPL for
--- their language, starting it beside the code if needed.
---@param cells NotebookCell[]
function M.run(cells, buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local key = keys[cells[1].lang]
  local lines = {}
  for i, c in ipairs(cells) do
    if i > 1 then lines[#lines + 1] = "" end
    vim.list_extend(lines, vim.api.nvim_buf_get_lines(buf, c.from - 1, c.to, false))
  end
  local terms = require("terminals")
  local id, fresh = terms.ensure_repl(key)
  local t = terms.get(id)
  if t and not fresh and ready(key, t.bufnr) then return terms.send(lines, id) end
  -- wait for the first prompt: typed-ahead input can be lost while the REPL
  -- is still starting (uv may be resolving IPython)
  local waited = 0
  local timer = vim.uv.new_timer()
  timer:start(100, 100, vim.schedule_wrap(function()
    waited = waited + 100
    local tt = terms.get(id)
    if tt and tt.bufnr and ready(key, tt.bufnr) then
      timer:stop(); timer:close()
      terms.send(lines, id)
    elseif waited > 20000 or not tt then
      timer:stop(); timer:close()
      vim.notify(("%s REPL didn't show a prompt; cells not sent"):format(key), vim.log.levels.WARN)
    end
  end))
end

return M
