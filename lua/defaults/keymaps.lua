vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
vim.keymap.set('n','<leader>ff','<cmd>Telescope find_files<cr>',{ desc = 'Telescope find files' })
-- Searchable menu of ALL keybinds (fuzzy filter, <CR> to run one)
vim.keymap.set('n','<leader>?','<cmd>Telescope keymaps<cr>',{ desc = 'Search keymaps' })
-- Static grouped cheatsheet in a floating window
local cheatsheet = require("defaults.cheatsheet")
vim.api.nvim_create_user_command("Cheatsheet", cheatsheet.open, {})
vim.keymap.set('n','<leader>k', cheatsheet.open, { desc = 'Keybindings cheatsheet' })

vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Move to lower window" })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Move to upper window" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })


vim.keymap.set('n','<leader>n', "<cmd>Neotree toggle<cr>", { desc = "Toogle Neo-Tree" })

vim.keymap.set("n", "<leader>t", function()
    vim.cmd("ToggleTerm direction=vertical size=80")
end)

vim.keymap.set("t", "<C-h>", [[<C-\><C-n><C-w>h]], { desc = "Exit terminal and go left" })

vim.keymap.set("n", "<leader>mi", ":MoltenInit<CR>", { desc = "init Molten kernel", silent = true })
vim.keymap.set("n", "<leader>e", ":MoltenEvaluateOperator<CR>", { desc = "evaluate operator", silent = true })
vim.keymap.set("n", "<leader>os", ":noautocmd MoltenEnterOutput<CR>", { desc = "open output window", silent = true })
vim.keymap.set("n", "<leader>rr", ":MoltenReevaluateCell<CR>", { desc = "re-eval cell", silent = true })
vim.keymap.set("v", "<leader>r", ":<C-u>MoltenEvaluateVisual<CR>gv", { desc = "execute visual selection", silent = true })
vim.keymap.set("n", "<leader>oh", ":MoltenHideOutput<CR>", { desc = "close output window", silent = true })
vim.keymap.set("n", "<leader>md", ":MoltenDelete<CR>", { desc = "delete Molten cell", silent = true })

-- if you work with html outputs:
vim.keymap.set("n", "<localleader>mx", ":MoltenOpenInBrowser<CR>", { desc = "open output in browser", silent = true })
-- open the current cell's image output in an external viewer (use in Alacritty)
vim.keymap.set("n", "<leader>oi", ":MoltenImagePopup<CR>", { desc = "open image output externally", silent = true })

vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float, { desc = "Show diagnostic" })

-- bufferline navigation
vim.keymap.set("n", "<Tab>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next buffer" })
vim.keymap.set("n", "<S-Tab>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Prev buffer" })
vim.keymap.set("n", "<leader>x", "<cmd>bd<cr>", { desc = "Close buffer" })

-- claude keymaps live in lua/plugins/claude.lua (the `keys` table)

vim.keymap.set("n", "<leader>z", "<cmd>ZenMode<cr>", { desc = "Toogle Zen mode" })
