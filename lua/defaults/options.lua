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

-- Highlight the current line number + a subtle underline on the line itself.
-- The CursorLine bg is stripped on ColorScheme (see init.lua) so it stays
-- transparent; the underline is what reads against the Alacritty background.
vim.opt.cursorline = true
vim.opt.cursorlineopt = "number,line"

-- Only show the cursorline in the focused window so inactive splits stay clean.
local cursorline_grp = vim.api.nvim_create_augroup("ActiveCursorLine", { clear = true })
vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
  group = cursorline_grp,
  callback = function() vim.opt_local.cursorline = true end,
})
vim.api.nvim_create_autocmd({ "WinLeave" }, {
  group = cursorline_grp,
  callback = function() vim.opt_local.cursorline = false end,
})

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

vim.api.nvim_create_autocmd(
  { "FocusGained", "BufEnter", "CursorHold" },
  {
    pattern = "*",
    command = "checktime",
  }
)

