vim.g.mapleader = " "
vim.keymap.set('n','<leader>ex','<cmd>Ex<cr>',{ desc = 'Open directory explorer' }) 
vim.keymap.set('n','<leader>ff','<cmd>Telescope find_files<cr>',{ desc = 'Telescope find files' })

vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Move to lower window" })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Move to upper window" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })


vim.keymap.set('n','<leader>n', "<cmd>Neotree toggle<cr>", { desc = "Toogle Neo-Tree" })

vim.keymap.set("n", "<leader>t", function()
  vim.cmd("ToggleTerm direction=vertical size=60")
end)

vim.keymap.set("t", "<C-h>", [[<C-\><C-n><C-w>h]], { desc = "Exit terminal and go left" })

vim.keymap.set("n","<leader>mc","<cmd>MoltenEvaluateVisual<cr>",{ desc = "Evaluate a notebook cell"})
vim.keymap.set("n","<leader>ml", "<cmd>MoltenEvaluateLine<cr>", { desc = "Evaluate a notebook line"})
