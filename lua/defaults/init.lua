vim.opt.runtimepath:append("~/.local/share/nvim/site/parser/")
require("defaults.options")
require("defaults.keymaps")
require("defaults.lazy")

-- Universal transparency: after ANY colorscheme loads, strip the background of
-- the core editor groups so the Alacritty background shows through. This works
-- even for colorschemes without a built-in transparency option (e.g. melange).
-- Defined before the startup colorscheme load below so it also applies on boot.
local transparent_groups = {
  "Normal", "NormalNC", "NormalFloat", "FloatBorder", "FloatTitle",
  "SignColumn", "LineNr", "CursorLineNr", "FoldColumn", "EndOfBuffer",
  "MsgArea", "TabLineFill", "WinBar", "WinBarNC",
  "TelescopeNormal", "TelescopeBorder", "TelescopePromptNormal",
  "NeoTreeNormal", "NeoTreeNormalNC", "NeoTreeEndOfBuffer", "NeoTreeWinSeparator",
  "SnacksDashboardNormal",
  "WinSeparator", "VertSplit", "StatusLine", "StatusLineNC",
}
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    for _, g in ipairs(transparent_groups) do
      -- only touch the bg attribute; fg/styles from the colorscheme are kept
      vim.cmd(("highlight %s guibg=NONE ctermbg=NONE"):format(g))
    end
    -- Transparent-friendly current line: no bg band, just a subtle underline.
    vim.cmd("highlight CursorLine guibg=NONE ctermbg=NONE gui=underline cterm=underline")
  end,
})

-- Build help tags for this config's own docs so `:help nvim-config` resolves.
-- Cheap and idempotent: only runs when doc/tags is missing (e.g. fresh clone).
local doc_dir = vim.fn.stdpath("config") .. "/doc"
if vim.fn.filereadable(doc_dir .. "/tags") == 0 and vim.fn.isdirectory(doc_dir) == 1 then
  pcall(vim.cmd, "helptags " .. doc_dir)
end

-- Load persisted colorscheme, fallback to kanso
local cs_file = vim.fn.stdpath("config") .. "/.colorscheme"
local ok, cs = pcall(vim.fn.readfile, cs_file)
vim.cmd("colorscheme " .. (ok and cs[1] or "kanso"))

-- Colorscheme picker: opens Telescope with live preview; selection is persisted
vim.keymap.set("n", "<leader>cs", function()
  require("telescope.builtin").colorscheme({ enable_preview = true })
end, { desc = "Pick colorscheme" })

-- Override colorscheme command to auto-persist any :colorscheme call
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function(ev)
    vim.fn.writefile({ ev.match }, cs_file)
  end,
})

-- Dedicated venv for Neovim's Python host (has pynvim + jupyter_client for Molten).
-- Homebrew's python3 is PEP-668 externally-managed, so we don't install into it.
vim.g.python3_host_prog = vim.fn.expand('~/.virtualenvs/neovim/bin/python')
-- Prepend the neovim venv bin so jupytext.nvim (which calls a bare `jupytext`)
-- and the python host resolve, then homebrew bin.
vim.env.PATH = vim.fn.expand('~/.virtualenvs/neovim/bin')
  .. ':/opt/homebrew/bin:' .. vim.env.PATH


