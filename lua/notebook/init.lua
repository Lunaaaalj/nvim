-- Notebook support around Molten (issue #40), kept as a thin layer so Molten
-- stays replaceable:
--   kernel.lua   which kernel a buffer gets; no registration (phase 2)
--   plots.lua    plot paper (theme / paper), flattening, split view (phase 3)
--   ui.lua       themed output windows, full output buffer (phase 3)
--   cells.lua    cell parser, run/move/edit, text objects (phase 4)
-- This file attaches it all to notebook buffers: every key is buffer-local
-- under <leader>m (plus ]c/[c and ij/aj), so none exist in C or Lua buffers.
local M = {}

M.filetypes = { quarto = true, rmd = true }

--- Is this buffer a notebook: a .qmd/.Rmd/.ipynb (ft quarto/rmd) or a
--- .py/.R/.jl percent script with `# %%` cells?
function M.is_notebook(buf)
  return M.filetypes[vim.bo[buf].filetype] or require("notebook.cells").is_percent(buf)
end

--- Where this buffer's cells run: "repl" (IPython / R terminal; the
--- default for `# %%` scripts) or "molten" (notebooks). <leader>mE switches.
function M.engine(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local e = vim.b[buf].notebook_engine
  if e then return e end
  return require("notebook.cells").is_percent(buf) and "repl" or "molten"
end

function M.toggle_engine()
  local e = M.engine() == "repl" and "molten" or "repl"
  vim.b.notebook_engine = e
  vim.notify("Cells run in: " .. (e == "repl" and "the REPL terminal" or "a Molten kernel"))
  vim.cmd("redrawstatus")
end

local function keys(buf)
  local cells = require("notebook.cells")
  local function cmd(c) return function() pcall(vim.cmd, c) end end
  local function k(fn) return function() require("notebook.kernel").ensure(fn) end end
  local maps = {
    -- kernel
    { "n", "<leader>mi", k(), "start the project's kernel" },
    { "n", "<leader>mI", cmd("MoltenInit"), "pick a kernel" },
    { "n", "<leader>mx", cmd("MoltenInterrupt"), "interrupt the kernel" },
    { "n", "<leader>mX", cmd("MoltenRestart"), "restart the kernel" },
    { "n", "<leader>mE", M.toggle_engine, "run cells in REPL / Molten" },
    -- run
    { "n", "<leader>mr", cells.run_cell, "run cell" },
    { "x", "<leader>mr", cells.run_visual, "run selection" },
    { "n", "<leader>mn", cells.run_and_next, "run cell, go to the next" },
    { "n", "<leader>ma", cells.run_all, "run all cells" },
    { "n", "<leader>mk", function() cells.run_split(true) end, "run cells above" },
    { "n", "<leader>mj", function() cells.run_split(false) end, "run this cell and below" },
    { "n", "<leader>ml", cells.run_line, "run line" },
    { "n", "<leader>me", k(function() vim.cmd("MoltenEvaluateOperator") end), "run operator (motion)" },
    { "n", "<leader>mR", k(function() vim.cmd("MoltenReevaluateCell") end), "re-run Molten's cell" },
    -- cells
    { "n", "<leader>mo", function() cells.new_cell(true) end, "new cell below" },
    { "n", "<leader>mO", function() cells.new_cell(false) end, "new cell above" },
    { "n", "]c", function() cells.goto_cell(vim.v.count1) end, "next cell" },
    { "n", "[c", function() cells.goto_cell(-vim.v.count1) end, "previous cell" },
    { { "x", "o" }, "ij", function() cells.select(false) end, "inner cell" },
    { { "x", "o" }, "aj", function() cells.select(true) end, "a cell (with fences)" },
    -- output
    { "n", "<leader>ms", cmd("noautocmd MoltenEnterOutput"), "show / enter output" },
    { "n", "<leader>mh", cmd("MoltenHideOutput"), "hide output" },
    { "n", "<leader>mf", function() require("notebook.ui").full_output() end, "full output in a split" },
    { "n", "<leader>md", cmd("MoltenDelete"), "delete the cell's output" },
    { "n", "<leader>mv", function() require("notebook.plots").view() end, "last plot in a split" },
    { "n", "<leader>mg", cmd("MoltenImagePopup"), "image in the system viewer" },
    { "n", "<leader>mb", cmd("MoltenOpenInBrowser"), "HTML output in the browser" },
    { "n", "<leader>mp", function() require("notebook.plots").toggle() end, "plot paper: theme / white" },
  }
  if vim.bo[buf].filetype == "quarto" then
    -- live-reload document preview in a browser (quarto-nvim)
    maps[#maps + 1] = { "n", "<leader>op", cmd("QuartoPreview"), "Quarto preview (browser)" }
    maps[#maps + 1] = { "n", "<leader>oP", cmd("QuartoClosePreview"), "stop the Quarto preview" }
    -- the document as a PDF in the kitty split (lua/pdfview/quarto.lua), like
    -- <leader>pv in Markdown; code is shown, not run
    local q = function() return require("pdfview.quarto") end
    maps[#maps + 1] = { { "n", "x" }, "<leader>pv", function() q().view() end, "PDF preview in a split (quarto → typst)" }
    maps[#maps + 1] = { "n", "<leader>pF", function() q().toggle_live() end, "PDF preview: toggle live follow" }
    maps[#maps + 1] = { "n", "<leader>pk", function() q().stop() end, "PDF preview: close" }
  end
  for _, m in ipairs(maps) do
    vim.keymap.set(m[1], m[2], m[3], { buffer = buf, desc = "Notebook: " .. m[4] })
  end
end

local attached = {}

function M.attach(buf)
  if attached[buf] then return end
  attached[buf] = true
  vim.b[buf].notebook = true
  keys(buf)
  local cells = require("notebook.cells")
  cells.decorate(buf)
  local timer
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufEnter" }, {
    buffer = buf,
    group = vim.api.nvim_create_augroup("NotebookBuf" .. buf, { clear = true }),
    callback = function()
      if timer then timer:stop() end
      timer = vim.defer_fn(function() cells.decorate(buf) end, 150)
    end,
  })
end

-- ---------------------------------------------------------------------------
-- Statusline: kernel name and idle / busy

local status_cache = {}

local function busy(buf)
  for name, ns in pairs(vim.api.nvim_get_namespaces()) do
    if name:match("^molten") then
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
        for _, line in ipairs(m[4].virt_lines or { m[4].virt_text or {} }) do
          local chunk = line[1] and line[1][1] or ""
          if chunk:find("Running", 1, true) or chunk:find("On Hold", 1, true) then return true end
        end
      end
    end
  end
  return false
end

--- For lualine: "" outside notebooks. Kernel name comes from MoltenInitPost /
--- MoltenDeinitPost (never asks the Python host on redraw); busy is read from
--- Molten's own "Running" / "On Hold" virtual lines, throttled.
function M.status()
  local buf = vim.api.nvim_get_current_buf()
  if not vim.b[buf].notebook then return "" end
  if M.engine(buf) == "repl" then
    local lang = vim.bo[buf].filetype
    if lang ~= "python" and lang ~= "r" then lang = (require("notebook.cells").parse(buf)[1] or {}).lang or lang end
    return "▷ " .. (lang == "r" and "R" or lang == "python" and "IPython" or lang) .. " REPL"
  end
  local kernel = vim.b[buf].notebook_kernel
  if not kernel then return "○ no kernel" end
  local now, c = vim.uv.now(), status_cache[buf]
  if not c or now - c.at > 400 then
    c = { at = now, busy = busy(buf) }
    status_cache[buf] = c
  end
  return (c.busy and "◐ %s busy" or "● %s"):format(kernel)
end

-- ---------------------------------------------------------------------------

function M.setup()
  -- $JUPYTER_PATH must be set before Neovim's Python host (Molten) spawns.
  require("notebook.kernel").setup()
  require("notebook.plots").setup()
  require("notebook.ui").setup()

  local group = vim.api.nvim_create_augroup("Notebook", { clear = true })
  vim.api.nvim_create_autocmd({ "FileType", "BufWritePost" }, {
    group = group,
    -- BufWritePost: a script that just got its first `# %%`
    callback = function(ev)
      if vim.bo[ev.buf].buftype == "" and M.is_notebook(ev.buf) then M.attach(ev.buf) end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "MoltenInitPost", "MoltenDeinitPost" },
    callback = function(ev)
      local buf = vim.api.nvim_get_current_buf()
      local ok, ks = pcall(vim.fn.MoltenRunningKernels, true)
      vim.b[buf].notebook_kernel = ev.match == "MoltenInitPost" and ok and ks[1] or nil
      vim.cmd("redrawstatus")
    end,
  })
  -- Outputs computed here go into the .ipynb on every write (jupytext has
  -- just written the cells; Molten matches its outputs to them by content).
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.ipynb",
    callback = function(ev)
      if vim.b[ev.buf].notebook_kernel and ev.buf == vim.api.nvim_get_current_buf() then
        pcall(vim.cmd, "MoltenExportOutput!")
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufUnload", {
    group = group,
    callback = function(ev) attached[ev.buf], status_cache[ev.buf] = nil, nil end,
  })
end

return M
