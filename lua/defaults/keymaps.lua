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

-- Music (lua/music/): drives the Apple Music app. <leader>m is Molten's.
local function music(fn, ...)
    local args = { ... }
    return function() require("music")[fn](unpack(args)) end
end
vim.keymap.set("n", "<leader>Mo", function() require("music.ui").toggle() end, { desc = "Music: player" })
vim.keymap.set("n", "<leader>Mp", music("toggle"), { desc = "Music: play / pause" })
vim.keymap.set("n", "<leader>Mn", music("next"), { desc = "Music: next track" })
vim.keymap.set("n", "<leader>MN", music("prev"), { desc = "Music: previous track" })
vim.keymap.set("n", "<leader>Ms", function() require("music.ui").open({ tab = 4, filter = true }) end,
    { desc = "Music: search songs" })

-- Terminal-mode escapes: jump to other windows or back to normal mode without
-- getting trapped in insert. <Esc><Esc> leaves terminal-insert to normal mode.
vim.keymap.set("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Terminal: to normal mode" })
vim.keymap.set("t", "<C-h>", [[<C-\><C-n><C-w>h]], { desc = "Terminal: window left" })
vim.keymap.set("t", "<C-j>", [[<C-\><C-n><C-w>j]], { desc = "Terminal: window down" })
vim.keymap.set("t", "<C-k>", [[<C-\><C-n><C-w>k]], { desc = "Terminal: window up" })
vim.keymap.set("t", "<C-l>", [[<C-\><C-n><C-w>l]], { desc = "Terminal: window right" })

-- Every evaluation goes through notebook.kernel.ensure(): with no kernel in the
-- buffer it starts the project's one (generated kernelspec for the project's
-- venv, or the notebook's R/Julia kernel) instead of prompting.
local function with_kernel(fn)
    return function() require("notebook.kernel").ensure(fn) end
end
vim.keymap.set("n", "<leader>mi", with_kernel(), { desc = "Molten: start the project's kernel" })
vim.keymap.set("n", "<leader>mI", ":MoltenInit<CR>", { desc = "Molten: pick a kernel", silent = true })
vim.keymap.set("n", "<leader>e", with_kernel(function() vim.cmd("MoltenEvaluateOperator") end), { desc = "evaluate operator" })
vim.keymap.set("n", "<leader>os", ":noautocmd MoltenEnterOutput<CR>", { desc = "open output window", silent = true })
vim.keymap.set("n", "<leader>rr", with_kernel(function() vim.cmd("MoltenReevaluateCell") end), { desc = "re-eval cell" })
vim.keymap.set("v", "<leader>r", function()
    vim.cmd("normal! \27") -- leave visual mode so '< and '> are set
    require("notebook.kernel").ensure(function()
        -- separate calls: MoltenEvaluateVisual takes args, so `|` would be one
        vim.cmd("MoltenEvaluateVisual")
        vim.cmd("normal! gv")
    end)
end, { desc = "execute visual selection" })

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
    if #cells == 0 then return 0 end
    local ran = 0
    require("notebook.kernel").ensure(function()
        for _, c in ipairs(cells) do
            if c.close - 1 >= c.open + 1 then
                vim.fn.MoltenEvaluateRange(c.open + 1, c.close - 1)
                ran = ran + 1
            end
        end
    end)
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
-- lua/notebook/: the last plot full size in a split, the cell's whole output in
-- a scratch buffer, and the plot paper (theme colours <-> white, persisted).
vim.keymap.set("n", "<leader>ov", function() require("notebook.plots").view() end, { desc = "Molten: last plot in a split" })
vim.keymap.set("n", "<leader>of", function() require("notebook.ui").full_output() end, { desc = "Molten: full output in a split" })
vim.keymap.set("n", "<leader>mp", function() require("notebook.plots").toggle() end, { desc = "Molten: plot paper theme / white" })

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
  -- In-terminal kitty preview (lua/pdfview/tex.lua); system viewer outside kitty. In
  -- visual mode it highlights the selected lines on the page.
  { "lv", function() require("pdfview.tex").view() end, "LaTeX: preview PDF in a split (forward search)", { "n", "x" } },
  { "lF", function() require("pdfview.tex").toggle_live() end, "LaTeX: toggle live follow in the preview" },
  { "lV", "<cmd>VimtexView<cr>",          "LaTeX: open PDF in the system viewer" },
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
      vim.keymap.set(m[4] or "n", "<leader>" .. m[1], m[2], { buffer = ev.buf, silent = true, desc = m[3] })
    end
  end,
})

-- Markdown preview (lua/pdfview/markdown.lua): the LaTeX preview's split, fed
-- by pandoc -> typst. Buffer-local for the same reason as the LaTeX maps.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  group = vim.api.nvim_create_augroup("MarkdownPreviewKeymaps", { clear = true }),
  callback = function(ev)
    local md = function() return require("pdfview.markdown") end
    vim.keymap.set({ "n", "x" }, "<leader>pv", function() md().view() end,
      { buffer = ev.buf, silent = true, desc = "Markdown: preview in a split (sync to cursor)" })
    vim.keymap.set("n", "<leader>pF", function() md().toggle_live() end,
      { buffer = ev.buf, silent = true, desc = "Markdown: toggle live follow in the preview" })
    vim.keymap.set("n", "<leader>ps", function() require("pdfview.md_picker").pick() end,
      { buffer = ev.buf, silent = true, desc = "Markdown: preview style (live, per file)" })
    -- :MarkdownStyle         picker
    -- :MarkdownStyle book    use for this file      (:MarkdownStyle! book = default for all)
    -- :MarkdownStyle -       drop this file's pick, follow the default
    vim.api.nvim_buf_create_user_command(ev.buf, "MarkdownStyle", function(o)
      if o.args == "" then return require("pdfview.md_picker").pick() end
      local name = o.args ~= "-" and o.args or nil
      md().set_style(ev.buf, name, o.bang and "default" or "file")
      vim.notify("Markdown style: " .. md().style(ev.buf))
    end, {
      nargs = "?",
      bang = true,
      desc = "Markdown preview style (! = default for all files)",
      complete = function()
        return vim.list_extend(vim.tbl_map(function(s) return s.name end, md().styles), { "-" })
      end,
    })
  end,
})

-- Typst (lua/pdfview/typst.lua; tinymist does LSP/format): the same <leader>l
-- keys as LaTeX do the same jobs, buffer-local like the VimTeX maps. The
-- preview recompiles on every edit, so there is no "continuous compile" key.
local typst = function() return require("pdfview.typst") end
local typst_maps = {
  { "lv", function() typst().view() end, "Typst: live preview in a split (sync to cursor)", { "n", "x" } },
  { "lF", function() typst().toggle_live() end, "Typst: toggle live follow in the preview" },
  { "lk", function() typst().stop() end, "Typst: close the preview" },
  { "lo", function() typst().compile_file() end, "Typst: compile once to foo.pdf" },
  { "lV", function() typst().open_external() end, "Typst: compile and open the PDF in the system viewer" },
  { "le", function() vim.diagnostic.setloclist() end, "Typst: error list (diagnostics)" },
}
vim.api.nvim_create_autocmd("FileType", {
  pattern = "typst",
  group = vim.api.nvim_create_augroup("TypstKeymaps", { clear = true }),
  callback = function(ev)
    for _, m in ipairs(typst_maps) do
      vim.keymap.set(m[4] or "n", "<leader>" .. m[1], m[2], { buffer = ev.buf, silent = true, desc = m[3] })
    end
  end,
})

-- New Typst document from a template (lua/typst_templates.lua). Global, unlike
-- the maps above: you start a document from anywhere (the only global
-- <leader>l map, and no buffer-local one shadows it).
vim.keymap.set("n", "<leader>ln", function() require("typst_templates").pick() end,
  { desc = "Typst: new document from a template" })
vim.api.nvim_create_user_command("TypstNew", function(o)
  require("typst_templates").new(o.args ~= "" and o.args or nil)
end, {
  nargs = "?",
  complete = function(lead) return require("typst_templates").complete(lead) end,
  desc = "New Typst document from a template",
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
-- lua/defaults/ui_toggle.lua). The two are independent (kitty swaps its own
-- background with the macOS appearance). <leader>uT follows the macOS
-- appearance; a manual <leader>uB turns that off.
vim.keymap.set("n", "<leader>ub", function() require("defaults.ui_toggle").toggle_transparency() end,
  { desc = "Toggle transparent / solid background" })
vim.keymap.set("n", "<leader>uB", function() require("defaults.ui_toggle").toggle_background() end,
  { desc = "Toggle dark / light background" })
vim.keymap.set("n", "<leader>uT", function() require("defaults.ui_toggle").toggle_auto() end,
  { desc = "Toggle auto dark / light (follow macOS)" })

vim.keymap.set("n", "<leader>uc", function() require("defaults.cursorline").cycle() end,
  { desc = "Cycle cursorline style (number / underline / band)" })

-- Toggle spell-check in the current buffer
vim.keymap.set("n", "<leader>us", function()
  vim.wo.spell = not vim.wo.spell
  vim.notify("Spell: " .. (vim.wo.spell and "ON" or "OFF"))
end, { desc = "Toggle spell-check" })
