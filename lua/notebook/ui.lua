-- Readable Molten output (issue #40, phase 3).
--
-- Molten's groups are `default` links to generic ones (NormalFloat,
-- FloatBorder, Comment, CursorLine) that this config strips or blanks in
-- transparent mode, so the output float blended into the code behind it and
-- the running cell wasn't marked. Here they get real colours from the scheme,
-- re-applied on ColorScheme, and output floats lose the global winblend
-- (with no background of their own, the code underneath showed through).
local M = {}

local colors = require("defaults.colors")

function M.highlights()
  local bg = colors.bg()
  local fg = colors.fg("Normal") or (vim.o.background == "light" and 0x222222 or 0xdddddd)
  local win = colors.blend(fg, bg, 0.05) -- solid, slightly tinted, in every mode
  local muted = colors.blend(fg, bg, 0.55)
  local set = function(name, val) vim.api.nvim_set_hl(0, name, val) end
  set("MoltenOutputWin", { fg = fg, bg = win })
  set("MoltenOutputWinNC", { fg = fg, bg = win })
  set("MoltenOutputBorder", { fg = muted, bg = win })
  set("MoltenOutputBorderSuccess", { fg = colors.fg("DiagnosticOk", "String") or muted, bg = win })
  set("MoltenOutputBorderFail", { fg = colors.fg("DiagnosticError", "ErrorMsg") or muted, bg = win })
  set("MoltenOutputFooter", { fg = muted, bg = win, italic = true })
  -- output, not a comment: nearly full foreground, no italics
  set("MoltenVirtualText", { fg = colors.blend(fg, bg, 0.85) })
  set("MoltenCell", { bg = colors.blend(colors.accent() or fg, bg, 0.10) })
end

local function unblend(buf)
  for _, w in ipairs(vim.fn.win_findbuf(buf)) do
    vim.wo[w].winblend = 0
  end
end

--- The output of the cell under the cursor in a scratch split, all of it
--- (the float and the virtual text are both capped in height).
function M.full_output()
  local src = vim.api.nvim_get_current_win()
  pcall(vim.cmd, "MoltenShowOutput")
  pcall(vim.cmd, "noautocmd MoltenEnterOutput")
  local win = vim.api.nvim_get_current_win()
  if win == src or vim.bo.filetype ~= "molten_output" then
    return vim.notify("No output for the cell under the cursor", vim.log.levels.WARN)
  end
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  vim.api.nvim_set_current_win(src)
  pcall(vim.cmd, "MoltenHideOutput")
  while #lines > 0 and not lines[#lines]:find("%S") do lines[#lines] = nil end -- image padding

  local name = "molten://output"
  local buf = vim.fn.bufnr(name)
  if buf == -1 then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, name)
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].filetype = "text"
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local shown = vim.fn.win_findbuf(buf)[1]
  if shown then
    vim.api.nvim_set_current_win(shown)
  else
    vim.cmd("botright split")
    vim.api.nvim_win_set_buf(0, buf)
  end
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

function M.setup()
  local group = vim.api.nvim_create_augroup("NotebookUI", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    -- scheduled: after the strip autocmd has recorded the scheme's bg
    callback = function() vim.schedule(M.highlights) end,
  })
  vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].filetype == "molten_output" then
        unblend(ev.buf)
        vim.schedule(function() unblend(ev.buf) end) -- the float may open after the ft is set
      end
    end,
  })
  if vim.g.colors_name then M.highlights() end
end

return M
