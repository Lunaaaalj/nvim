vim.cmd("let g:netrw_banner = 0")

vim.opt.number = true
vim.opt.relativenumber = true

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.autoindent = true
vim.opt.smartindent = true
vim.opt.wrap = true
vim.opt.linebreak = true

-- True color (explicit; most colorschemes assume it)
vim.opt.termguicolors = true

-- Search: case-insensitive unless the query contains a capital letter
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- System clipboard (macOS pasteboard) for all yanks/puts
vim.opt.clipboard = "unnamedplus"

-- Persistent undo across sessions; no swap/backup clutter
vim.opt.undofile = true
vim.opt.swapfile = false

-- Keep the cursor away from the screen edges; reserve a sign column so the
-- gutter doesn't jump as gitsigns/diagnostics signs appear and disappear.
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"

-- Current line: only in the focused, regular-file window. Styling (accent
-- line number by default, <leader>uc to cycle) and the per-window rules live
-- in lua/defaults/cursorline.lua.
vim.opt.cursorline = true

-- Slight transparency on the popup menu and floating windows so they sit
-- lightly over the (transparent) editor instead of reading as solid blocks.
vim.opt.pumblend = 10
vim.opt.winblend = 10

-- Clean window/gutter glyphs: no end-of-buffer tildes, thin separators.
vim.opt.fillchars = {
  eob = " ",
  vert = "│",
  horiz = "─",
  fold = " ",
  foldopen = "▾",
  foldclose = "▸",
  foldsep = " ",
}

-- Faster CursorHold (drives checktime/hover) and snappier which-key popups
vim.opt.updatetime = 250
vim.opt.timeoutlen = 400

-- New splits open to the right / below
vim.opt.splitright = true
vim.opt.splitbelow = true
-- A split halves only the window it splits, instead of evening out every
-- window (which also kicks in whenever this option is switched back on).
-- Panel columns are arranged by lua/layout.
vim.opt.equalalways = false

-- Mouse support and confirm prompt instead of failing on unsaved :q
vim.opt.mouse = "a"
vim.opt.confirm = true

-- Single global statusline (pairs with lualine globalstatus)
vim.opt.laststatus = 3

-- Diagnostics: icon signs instead of Neovim's default E/W/I/H letters, sorted
-- by severity so the most important sign wins the gutter cell.
vim.diagnostic.config({
  severity_sort = true,
  underline = true,
  virtual_text = { spacing = 2, prefix = "●" },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "",
      [vim.diagnostic.severity.WARN]  = "",
      [vim.diagnostic.severity.INFO]  = "",
      [vim.diagnostic.severity.HINT]  = "",
    },
  },
})

vim.opt.autoread = true
vim.api.nvim_create_autocmd(
  { "FocusGained", "BufEnter", "CursorHold" },
  {
    pattern = "*",
    command = "checktime",
  }
)

-- CursorHold never fires in Terminal mode, so while you sit in the Claude
-- terminal an edit to an open file stayed stale until you moved. Poll instead:
-- `checktime` only stats loaded buffers, so a 400 ms tick is negligible. Runs
-- only while Neovim has focus; skipped in cmdline mode, where it is unsafe.
local reload_timer = assert(vim.uv.new_timer())
local function start_reload_timer()
  reload_timer:start(400, 400, vim.schedule_wrap(function()
    if vim.fn.mode():match("^[cr!]") or vim.fn.getcmdwintype() ~= "" then return end
    vim.cmd("silent! checktime")
  end))
end
local reload_group = vim.api.nvim_create_augroup("auto_reload_files", { clear = true })
vim.api.nvim_create_autocmd("FocusLost", { group = reload_group, callback = function() reload_timer:stop() end })
vim.api.nvim_create_autocmd("FocusGained", { group = reload_group, callback = start_reload_timer })
start_reload_timer()

-- Prose/markup buffers: enable spell-check. The language comes from the nearest
-- .spelllang file above the buffer (one line, e.g. "es,en"), else English.
-- z= suggests corrections, ]s/[s jump between misspellings. Toggle per-buffer with <leader>us.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "tex", "plaintex", "markdown", "gitcommit", "text", "typst" },
  callback = function(args)
    vim.opt_local.spell = true
    local marker = vim.fs.find(".spelllang", {
      upward = true,
      path = vim.fs.dirname(vim.api.nvim_buf_get_name(args.buf)),
    })[1]
    local lang = marker and vim.trim(vim.fn.readfile(marker, "", 1)[1] or "")
    vim.opt_local.spelllang = (lang and lang ~= "") and lang or "en"
  end,
})

