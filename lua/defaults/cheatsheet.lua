-- A static, grouped keybinding cheatsheet in a floating window.
-- Open with <leader>k; close with q or <Esc>.
-- This is curated by hand. For a searchable/live list of *all* maps use <leader>?.
local M = {}

-- { "Section", { { "keys", "description" }, ... } }
local sections = {
  { "General", {
    { "<leader>?", "Search all keymaps (Telescope)" },
    { "<leader>k", "This cheatsheet" },
    { "<leader>w", "Save file" },
    { "<Esc>", "Clear search highlight" },
    { "<leader>z", "Toggle Zen mode" },
    { "<leader>d", "Show diagnostic float" },
  } },
  { "Find / Files / UI", {
    { "<leader>ff", "Telescope find files" },
    { "<leader>ft", "Find TODOs (Telescope)" },
    { "<leader>sr / sR", "Search & replace / replace selection (grug-far)" },
    { "<leader>cs", "Pick colorscheme (live preview)" },
    { "<leader>n", "Toggle Neo-tree" },
    { "<leader>t", "Terminal: toggle shell #1 (side panel)" },
    { "<leader>tn / ts", "New shell / select-switch shell" },
    { "<leader>tf / th", "Float / horizontal terminal" },
    { "<leader>tp / tN / tR", "Python / Node / R REPL terminal" },
    { "2<C-\\>", "Open numbered shell #2 (count-prefixed)" },
    { "<leader>ut", "Toggle treesitter context" },
    { "<leader>up", "Toggle precognition motion hints" },
    { "<leader>sn", "Show notification history (Noice)" },
    { "<leader>sd", "Dismiss visible notifications" },
  } },
  { "Fun", {
    { "<leader>fml", "Make it rain (cellular automaton)" },
    { "<leader>flife", "Game of Life (cellular automaton)" },
  } },
  { "Windows / Buffers", {
    { "<C-h/j/k/l>", "Move between windows" },
    { "<Tab> / <S-Tab>", "Next / previous buffer" },
    { "<leader>x", "Close buffer (keep layout)" },
  } },
  { "LSP / Diagnostics", {
    { "gd / gD", "Go to definition / declaration" },
    { "gr / gi", "References / implementation" },
    { "gy", "Type definition" },
    { "K", "Hover docs (cycle providers with <C-n>/<C-p>)" },
    { "gK", "Hover: select provider" },
    { "<leader>rn", "Rename symbol" },
    { "<leader>ca", "Code action" },
    { "<leader>d", "Diagnostic float" },
    { "[d / ]d", "Prev / next diagnostic" },
    { "<leader>cf", "Format buffer (conform)" },
    { "<leader>uf", "Toggle format on save" },
    { "<leader>uh", "Toggle inlay hints" },
    { "<leader>us", "Toggle spell-check" },
    { "<leader>xx", "Trouble: workspace diagnostics" },
    { "<leader>xb", "Trouble: buffer diagnostics" },
    { "<leader>xs", "Trouble: document symbols" },
    { "<leader>xt", "Trouble: TODOs" },
    { "<leader>xq", "Trouble: quickfix" },
  } },
  { "Treesitter text objects", {
    { "af / if", "Function outer / inner" },
    { "ac / ic", "Class outer / inner" },
    { "aa / ia", "Parameter outer / inner" },
    { "<leader>sp / sP", "Swap parameter next / prev" },
    { "]m / [m", "Next / prev function start" },
  } },
  { "Navigation", {
    { "s", "Flash jump (2-char)" },
    { "S", "Flash treesitter select" },
    { "-", "Oil: open parent dir (edit filesystem)" },
    { "]t / [t", "Next / prev TODO" },
    { "]x / [x", "Next / prev git conflict" },
    { "<leader>j", "TreeSJ: toggle split/join block" },
  } },
  { "Harpoon", {
    { "<leader>Ha", "Add file to harpoon" },
    { "<leader>Hh", "Open harpoon menu" },
    { "<leader>1-4", "Jump to harpoon file 1-4" },
  } },
  { "Git (Diffview)", {
    { "<leader>gd", "Diffview: open diff" },
    { "<leader>gh", "Diffview: current file history" },
    { "<leader>gH", "Diffview: repo history" },
    { "<leader>gc", "Diffview: close" },
    { "co / ct / cb / c0", "Conflict: ours / theirs / both / none" },
  } },
  { "Test (Neotest)", {
    { "<leader>Tr", "Run nearest test" },
    { "<leader>Tf", "Run test file" },
    { "<leader>Ts", "Toggle test summary" },
    { "<leader>To", "Toggle test output" },
    { "<leader>Td", "Debug nearest test (DAP)" },
    { "<leader>TX", "Stop tests" },
  } },
  { "Debug (DAP)", {
    { "<leader>db", "Toggle breakpoint" },
    { "<leader>dB", "Conditional breakpoint" },
    { "<leader>dc", "Continue / start" },
    { "<leader>di", "Step into" },
    { "<leader>dn", "Step over (next)" },
    { "<leader>de", "Step out (exit)" },
    { "<leader>du", "Toggle DAP UI" },
    { "<leader>dr", "Open REPL" },
    { "<leader>dx", "Terminate session" },
  } },
  { "Session (Persistence)", {
    { "<leader>qs", "Restore session (cwd)" },
    { "<leader>ql", "Restore last session" },
    { "<leader>qS", "Select session" },
    { "<leader>qd", "Don't save session on exit" },
  } },
  { "Molten / Notebooks / Quarto", {
    { "<leader>mi", "Init kernel" },
    { "<leader>e", "Evaluate operator" },
    { "<leader>r", "Evaluate selection (visual)" },
    { "<leader>rc", "Run current cell" },
    { "<leader>ra", "Run all cells" },
    { "<leader>rk", "Run cells above" },
    { "<leader>rj", "Run current cell + below" },
    { "<leader>rr", "Re-evaluate cell" },
    { "<leader>os", "Open output pane (docked, right column)" },
    { "<leader>ot", "Toggle output pane" },
    { "<leader>oh", "Close output pane" },
    { "<leader>md", "Delete cell" },
    { "<leader>oi", "Open image output externally" },
    { "<localleader>mx", "Open output in browser" },
    { "<leader>op / oP", "Quarto: start / stop live preview" },
  } },
  { "Claude Code", {
    { "<leader>ac", "Toggle Claude" },
    { "<leader>af", "Focus Claude" },
    { "<leader>ar / aC", "Resume / continue session" },
    { "<leader>am", "Select model" },
    { "<leader>ab", "Add current buffer to context" },
    { "<leader>as", "Send selection (v) / add file (tree)" },
    { "<leader>aa / ad", "Accept / reject diff" },
  } },
}

local ns = vim.api.nvim_create_namespace("cheatsheet")

-- Build the rendered lines plus a list of highlight instructions.
local function build()
  -- widest key string, so descriptions line up in a column
  local keycol = 0
  for _, sec in ipairs(sections) do
    for _, row in ipairs(sec[2]) do
      keycol = math.max(keycol, #row[1])
    end
  end

  local lines = {}
  local hls = {} -- { line, col_start, col_end, group }
  local title = "  Keybindings   ·   q / <Esc> to close"
  table.insert(lines, title)
  table.insert(hls, { #lines - 1, 0, -1, "Title" })
  table.insert(lines, "")

  for _, sec in ipairs(sections) do
    table.insert(lines, "  " .. sec[1])
    table.insert(hls, { #lines - 1, 0, -1, "Function" })
    for _, row in ipairs(sec[2]) do
      local keys = row[1]
      local line = "    " .. keys .. string.rep(" ", keycol - #keys) .. "   " .. row[2]
      table.insert(lines, line)
      -- highlight just the key portion
      table.insert(hls, { #lines - 1, 4, 4 + #keys, "Keyword" })
    end
    table.insert(lines, "")
  end

  return lines, hls
end

function M.open()
  local lines, hls = build()

  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = width + 2
  local height = #lines

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(buf, ns, h[4], h[1], h[2], h[3])
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "cheatsheet"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2 - 1),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " nvim ",
    title_pos = "center",
  })
  vim.wo[win].cursorline = false
  -- inherit transparency from the global ColorScheme autocmd
  vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"

  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, { buffer = buf, nowait = true, silent = true })
  end
end

return M
