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

-- Highlight only the current line number (clean against transparent bg)
vim.opt.cursorline = true
vim.opt.cursorlineopt = "number"

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

vim.api.nvim_create_autocmd(
  { "FocusGained", "BufEnter", "CursorHold" },
  {
    pattern = "*",
    command = "checktime",
  }
)

