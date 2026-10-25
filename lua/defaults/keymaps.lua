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

-- Terminals (lua/terminals/, drawn by toggleterm). <C-\> toggles the last used
-- terminal; with a count, shell N (2<C-\>). Shells are ids 1-99, the pinned
-- REPLs 100+, so they never steal each other's number. There's no bare
-- <leader>t: as a prefix of the maps below it would always wait 'timeoutlen'.
local function terms(fn, ...)
    local args = { ... }
    return function() require("terminals")[fn](unpack(args)) end
end
vim.keymap.set({ "n", "t" }, "<C-\\>", function() require("terminals").toggle(vim.v.count) end,
    { desc = "Terminal: toggle (count = shell N)" })
vim.keymap.set("n", "<leader>tt", function() require("terminals").toggle(vim.v.count) end,
    { desc = "Terminal: toggle last used" })
vim.keymap.set("n", "<leader>tn", terms("new"), { desc = "Terminal: new shell (cwd)" })
vim.keymap.set("n", "<leader>t.", terms("new_here", false), { desc = "Terminal: new shell in file's dir" })
vim.keymap.set("n", "<leader>tg", terms("new_here", true), { desc = "Terminal: new shell at project root" })
vim.keymap.set("n", "<leader>ts", function() require("terminals.picker").pick() end,
    { desc = "Terminal: pick (preview, rename, kill)" })
vim.keymap.set("n", "<leader>te", "<cmd>Neotree source=terminals reveal=false<cr>",
    { desc = "Terminal: list in neo-tree" })
vim.keymap.set("n", "<leader>tf", terms("toggle_direction", "float"), { desc = "Terminal: as float" })
vim.keymap.set("n", "<leader>th", terms("toggle_direction", "horizontal"), { desc = "Terminal: as bottom panel" })
vim.keymap.set("n", "<leader>tl", terms("send_line"), { desc = "Terminal: send line ([count] lines)" })
vim.keymap.set("x", "<leader>tl", terms("send_selection"), { desc = "Terminal: send selection" })
vim.keymap.set("n", "<leader>tr", terms("repeat_last"), { desc = "Terminal: repeat last command" })
vim.keymap.set("n", "<leader>tq", terms("quickfix"), { desc = "Terminal: output → quickfix" })
vim.keymap.set("n", "<leader>tk", terms("kill"), { desc = "Terminal: kill current" })
vim.keymap.set("n", "<leader>tm", terms("rename"), { desc = "Terminal: rename current" })
vim.keymap.set("n", "<leader>tp", terms("repl", "python"), { desc = "Terminal: Python REPL" })
vim.keymap.set("n", "<leader>tN", terms("repl", "node"), { desc = "Terminal: Node REPL" })
vim.keymap.set("n", "<leader>tR", terms("repl", "R"), { desc = "Terminal: R REPL" })

-- Terminal-mode escapes: jump to other windows or back to normal mode without
-- getting trapped in insert. <Esc><Esc> leaves terminal-insert to normal mode.
vim.keymap.set("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Terminal: to normal mode" })
vim.keymap.set("t", "<C-h>", [[<C-\><C-n><C-w>h]], { desc = "Terminal: window left" })
vim.keymap.set("t", "<C-j>", [[<C-\><C-n><C-w>j]], { desc = "Terminal: window down" })
vim.keymap.set("t", "<C-k>", [[<C-\><C-n><C-w>k]], { desc = "Terminal: window up" })
vim.keymap.set("t", "<C-l>", [[<C-\><C-n><C-w>l]], { desc = "Terminal: window right" })

vim.keymap.set("n", "<leader>mi", ":MoltenInit<CR>", { desc = "init Molten kernel", silent = true })
vim.keymap.set("n", "<leader>e", ":MoltenEvaluateOperator<CR>", { desc = "evaluate operator", silent = true })
vim.keymap.set("n", "<leader>os", ":noautocmd MoltenEnterOutput<CR>", { desc = "open output window", silent = true })
vim.keymap.set("n", "<leader>rr", ":MoltenReevaluateCell<CR>", { desc = "re-eval cell", silent = true })
vim.keymap.set("v", "<leader>r", ":<C-u>MoltenEvaluateVisual<CR>gv", { desc = "execute visual selection", silent = true })

-- Run whole notebook cells with a single keystroke. Notebooks open as jupytext
-- markdown, so a "cell" is a fenced code block: opening fence carries a language
-- (```python), closing fence is bare (```). Quarto/R-Markdown documents (.qmd)
-- use curly-brace chunk headers instead (```{r}, ```{python}), so both forms
-- are matched. We collect those spans and hand line ranges to Molten
-- (MoltenEvaluateRange auto-resolves a single attached kernel, and the kernel
-- runs queued evaluations in order).
local function molten_cells()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local cells, open = {}, nil
    for i, l in ipairs(lines) do
        if not open then
            if l:match("^```%a") or l:match("^```{%a") then
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

-- Quarto: live-reload preview (runs `quarto preview` in an integrated
-- terminal tab and opens/refreshes a browser); QuartoClosePreview stops it.
vim.keymap.set("n", "<leader>op", ":QuartoPreview<CR>", { desc = "Quarto: start preview" })
vim.keymap.set("n", "<leader>oP", ":QuartoClosePreview<CR>", { desc = "Quarto: stop preview" })

-- LaTeX (VimTeX). VimTeX already ships its own `\l*` maps on localleader; these
-- mirror the ones worth memorising under <leader>l so LaTeX reads like every
-- other group in this config (<leader>g git, <leader>T test, ...). They are
-- buffer-local on purpose: <leader>l means nothing outside a TeX buffer, and
-- registering them globally would show dead entries in <leader>? everywhere.
local vimtex_maps = {
  { "ll", "<cmd>VimtexCompile<cr>",       "LaTeX: toggle continuous compile" },
  { "lo", "<cmd>VimtexCompileSS<cr>",     "LaTeX: compile once (single shot)" },
  { "lv", "<cmd>VimtexView<cr>",          "LaTeX: view PDF (forward search)" },
  { "lk", "<cmd>VimtexStop<cr>",          "LaTeX: stop compilation" },
  { "lK", "<cmd>VimtexStopAll<cr>",       "LaTeX: stop all compilations" },
  { "lc", "<cmd>VimtexClean<cr>",         "LaTeX: clean aux files" },
  { "lC", "<cmd>VimtexClean!<cr>",        "LaTeX: clean aux files + PDF" },
  { "le", "<cmd>VimtexErrors<cr>",        "LaTeX: toggle error/quickfix list" },
  { "lg", "<cmd>VimtexCompileOutput<cr>", "LaTeX: raw compiler output" },
  { "lt", "<cmd>VimtexTocToggle<cr>",     "LaTeX: toggle table of contents" },
  { "ls", "<cmd>VimtexStatus<cr>",        "LaTeX: compiler status" },
  { "li", "<cmd>VimtexInfo<cr>",          "LaTeX: project info (debug)" },
  { "lm", "<cmd>VimtexImapsList<cr>",     "LaTeX: list insert-mode math maps" },
  { "lw", "<cmd>VimtexCountWords<cr>",    "LaTeX: word count" },
  { "ld", "<cmd>VimtexDocPackage<cr>",    "LaTeX: open docs for package under cursor" },
  { "lx", "<cmd>VimtexReload<cr>",        "LaTeX: reload VimTeX state" },
}
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "tex", "plaintex", "latex" },
  group = vim.api.nvim_create_augroup("VimtexKeymaps", { clear = true }),
  callback = function(ev)
    for _, m in ipairs(vimtex_maps) do
      vim.keymap.set("n", "<leader>" .. m[1], m[2], { buffer = ev.buf, silent = true, desc = m[3] })
    end
  end,
})

vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float, { desc = "Show diagnostic" })

-- bufferline navigation
vim.keymap.set("n", "<Tab>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next buffer" })
vim.keymap.set("n", "<S-Tab>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Prev buffer" })
-- Buffer-centric closing (lua/defaults/bufclose.lua): `:q` closes the buffer,
-- not Neovim, falling back to the next buffer or the dashboard. <leader>x is the
-- same close as a key; <leader>qq quits Neovim (sits in the <leader>q session
-- group, so <leader>q itself stays a prefix).
local bufclose = require("defaults.bufclose")
vim.keymap.set("n", "<leader>x", function() bufclose.close_buffer(false) end, { desc = "Close buffer (keep layout)" })
vim.keymap.set("n", "<leader>qq", "<cmd>qall<cr>", { desc = "Quit Neovim" })

-- claude keymaps live in lua/plugins/claude.lua (the `keys` table)
-- <leader>z (Zen mode) lives in lua/plugins/zen.lua (the `keys` table) so the
-- plugin lazy-loads on first use.

-- Background: transparent <-> solid, and dark <-> light (persisted; see
-- lua/defaults/ui_toggle.lua). Light mode forces solid until you go dark again.
vim.keymap.set("n", "<leader>ub", function() require("defaults.ui_toggle").toggle_transparency() end,
  { desc = "Toggle transparent / solid background" })
vim.keymap.set("n", "<leader>uB", function() require("defaults.ui_toggle").toggle_background() end,
  { desc = "Toggle dark / light background" })

vim.keymap.set("n", "<leader>uc", function() require("defaults.cursorline").cycle() end,
  { desc = "Cycle cursorline style (number / underline / band)" })

-- Toggle spell-check in the current buffer
vim.keymap.set("n", "<leader>us", function()
  vim.wo.spell = not vim.wo.spell
  vim.notify("Spell: " .. (vim.wo.spell and "ON" or "OFF"))
end, { desc = "Toggle spell-check" })
