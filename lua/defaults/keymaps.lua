vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
vim.keymap.set('n','<leader>ff','<cmd>Telescope find_files<cr>',{ desc = 'Telescope find files' })
-- Searchable menu of ALL keybinds (fuzzy filter, <CR> to run one)
vim.keymap.set('n','<leader>?','<cmd>Telescope keymaps<cr>',{ desc = 'Search keymaps' })
-- Static grouped cheatsheet in a floating window
local cheatsheet = require("defaults.cheatsheet")
vim.api.nvim_create_user_command("Cheatsheet", cheatsheet.open, {})
vim.keymap.set('n','<leader>k', cheatsheet.open, { desc = 'Keybindings cheatsheet' })

-- Clear search highlight on Esc (keeps normal-mode Esc behaviour otherwise)
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })

-- Quick write
vim.keymap.set("n", "<leader>w", "<cmd>write<cr>", { desc = "Save file" })

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

-- Run whole notebook cells with a single keystroke. Notebooks open as jupytext
-- markdown, so a "cell" is a fenced code block: opening fence carries a language
-- (```python), closing fence is bare (```). We collect those spans and hand line
-- ranges to Molten (MoltenEvaluateRange auto-resolves a single attached kernel,
-- and the kernel runs queued evaluations in order).
local function molten_cells()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local cells, open = {}, nil
    for i, l in ipairs(lines) do
        if not open then
            if l:match("^```%a") then
                open = i
            end
        elseif l:match("^```") then
            cells[#cells + 1] = { open = open, close = i }
            open = nil
        end
    end
    return cells
end

-- Evaluate a list of {open, close} cells, skipping empties.
local function molten_run(cells)
    local ran = 0
    for _, c in ipairs(cells) do
        if c.close - 1 >= c.open + 1 then
            vim.fn.MoltenEvaluateRange(c.open + 1, c.close - 1)
            ran = ran + 1
        end
    end
    return ran
end

-- Split all cells into those above the cursor and those at/below it. If the
-- cursor is inside a cell, that cell counts as "below" (current + below);
-- otherwise the split falls on the cursor line.
local function molten_split()
    local cells = molten_cells()
    local cur = vim.api.nvim_win_get_cursor(0)[1]
    local idx
    for i, c in ipairs(cells) do
        if cur >= c.open and cur <= c.close then
            idx = i
            break
        end
    end
    local above, below = {}, {}
    for i, c in ipairs(cells) do
        local is_above = idx and i < idx or (not idx and c.close < cur)
        if is_above then
            above[#above + 1] = c
        else
            below[#below + 1] = c
        end
    end
    return above, below
end

local function molten_eval_cell()
    local cur = vim.api.nvim_win_get_cursor(0)[1]
    local _, below = molten_split()
    local c = below[1]
    -- Only fire when the cursor is actually inside the cell, not in prose above it.
    if c and cur >= c.open and cur <= c.close then
        molten_run({ c })
    else
        vim.notify("Not inside a code cell", vim.log.levels.WARN)
    end
end

vim.keymap.set("n", "<leader>rc", molten_eval_cell, { desc = "Molten run current cell", silent = true })
vim.keymap.set("n", "<leader>ra", function()
    molten_run(molten_cells())
end, { desc = "Molten run all cells", silent = true })
vim.keymap.set("n", "<leader>rk", function()
    local above = molten_split()
    molten_run(above)
end, { desc = "Molten run cells above", silent = true })
vim.keymap.set("n", "<leader>rj", function()
    local _, below = molten_split()
    molten_run(below)
end, { desc = "Molten run current cell and below", silent = true })
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
-- Close the current buffer without destroying the window layout: switch the
-- window to the alternate/previous buffer first, then delete the original.
vim.keymap.set("n", "<leader>x", function()
  local cur = vim.api.nvim_get_current_buf()
  local alt = vim.fn.bufnr("#")
  if alt > 0 and vim.fn.buflisted(alt) == 1 then
    vim.cmd("buffer #")
  else
    vim.cmd("bprevious")
  end
  -- If nothing else was open we may still be on the same buffer; only delete
  -- when we actually moved away from it.
  if vim.api.nvim_get_current_buf() ~= cur then
    vim.cmd("bdelete " .. cur)
  else
    vim.cmd("bdelete")
  end
end, { desc = "Close buffer (keep layout)" })

-- claude keymaps live in lua/plugins/claude.lua (the `keys` table)

vim.keymap.set("n", "<leader>z", "<cmd>ZenMode<cr>", { desc = "Toogle Zen mode" })

-- Toggle spell-check in the current buffer
vim.keymap.set("n", "<leader>us", function()
  vim.wo.spell = not vim.wo.spell
  vim.notify("Spell: " .. (vim.wo.spell and "ON" or "OFF"))
end, { desc = "Toggle spell-check" })
