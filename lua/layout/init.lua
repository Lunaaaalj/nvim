-- Window layout: keep the editor wide when panels open.
--
-- Panels (terminals, including claudecode's and toggleterm's, reference pages,
-- :help) each open as a full-height column at the far right with a fixed
-- width, so a third one used to crush the editor to a sliver. Here the first
-- panel becomes the right column (narrowed so the editor keeps `editor_min`
-- columns) and every later one is stacked below it in that same column:
-- vertical first, then horizontal. Windows are moved, not recreated, so the
-- plugins that own them keep tracking them.
--
-- Only windows that open as the rightmost column are touched: a panel you
-- split by hand inside the column, or a bottom panel (<leader>th), stays put.
-- `<leader>uw` toggles the behaviour.
--
-- Manual splits of any buffer: <leader>| vertical, <leader>- horizontal,
-- <leader>\ along the window's longer side.

local M = {}

M.config = {
  editor_min = 88, -- columns the editor keeps beside the panel column
  panel_min = 40, -- never narrow a panel column below this
}

vim.g.layout_auto = vim.g.layout_auto ~= false

local api = vim.api

local function is_panel(win)
  if not api.nvim_win_is_valid(win) or api.nvim_win_get_config(win).relative ~= "" then return false end
  local buf = api.nvim_win_get_buf(win)
  local bt = vim.bo[buf].buftype
  return bt == "terminal" or bt == "help" or vim.b[buf].refdocs ~= nil
end

local function leaves(node, acc)
  acc = acc or {}
  if node[1] == "leaf" then
    acc[#acc + 1] = node[2]
  else
    for _, c in ipairs(node[2]) do leaves(c, acc) end
  end
  return acc
end

local function has_leaf(node, win)
  return vim.tbl_contains(leaves(node), win)
end

-- The tabpage's main row (the top node, or the row inside a top-level column
-- when a full-width bottom panel exists), with `win`'s index in it.
local function main_row(win)
  local top = vim.fn.winlayout()
  local rows = top[1] == "row" and { top } or {}
  if top[1] == "col" then
    for _, c in ipairs(top[2]) do
      if c[1] == "row" then rows[#rows + 1] = c end
    end
  end
  for _, row in ipairs(rows) do
    for i, c in ipairs(row[2]) do
      if c[1] == "leaf" and c[2] == win then return row, i end
    end
  end
end

-- Columns taken by sidebars (neo-tree) and separators, besides editor + panels.
local function sidebar_width(row, skip)
  local w = 0
  for _, c in ipairs(row[2]) do
    if c ~= skip and c[1] == "leaf" and vim.bo[api.nvim_win_get_buf(c[2])].filetype == "neo-tree" then
      w = w + api.nvim_win_get_width(c[2]) + 1
    end
  end
  return w
end

local function equalize_heights(wins)
  local total = 0
  for _, w in ipairs(wins) do total = total + api.nvim_win_get_height(w) end
  total = total + #wins - 1 -- the separators between them
  local each = math.floor((total - (#wins - 1)) / #wins)
  for i = 1, #wins - 1 do api.nvim_win_set_height(wins[i], each) end
end

function M.arrange(win)
  if not vim.g.layout_auto or not is_panel(win) then return end
  local row, idx = main_row(win)
  if not row or idx ~= #row[2] or idx < 2 then return end

  local prev = row[2][idx - 1]
  local column = leaves(prev)
  if prev[1] ~= "row" and #column > 0 and vim.iter(column):all(is_panel) then
    -- A panel column exists: stack this one at its bottom. The split that
    -- created this window already squeezed the column, so use its remembered
    -- width (kept current on WinResized, i.e. after resizing by hand).
    local width = vim.w[column[1]].layout_width or api.nvim_win_get_width(column[1])
    if not pcall(api.nvim_win_set_config, win, { split = "below", win = column[#column] }) then return end
    column[#column + 1] = win
    vim.wo[win].winfixwidth = true
    api.nvim_win_set_width(win, width)
    for _, w in ipairs(column) do vim.w[w].layout_width = width end
    equalize_heights(column)
  else
    -- First panel: narrow it so the editor keeps its width.
    local max = vim.o.columns - M.config.editor_min - sidebar_width(row, row[2][idx]) - 1
    local width = math.max(M.config.panel_min, math.min(api.nvim_win_get_width(win), max))
    vim.wo[win].winfixwidth = true
    api.nvim_win_set_width(win, width)
    vim.w[win].layout_width = width
  end
end

-- Width for a new panel column (what refdocs asks for).
function M.panel_width()
  return math.max(M.config.panel_min, math.min(90, math.floor(vim.o.columns * 0.4)))
end

--- Split the current window: "v" vertical, "h" horizontal, "auto" along its
--- longer side (a cell is about twice as tall as it is wide).
function M.split(dir)
  if dir == "auto" then
    local w, h = api.nvim_win_get_width(0), api.nvim_win_get_height(0)
    dir = (w >= 2 * M.config.panel_min and w > h * 2.2) and "v" or "h"
  end
  -- A panel's fixed width would make the split take the new window's columns
  -- from the editor; halve the panel instead ('equalalways' is off, see
  -- options.lua, so nothing else moves).
  local win, fixed = api.nvim_get_current_win(), vim.wo.winfixwidth
  vim.wo[win].winfixwidth = false
  vim.cmd(dir == "v" and "vsplit" or "split")
  vim.wo[win].winfixwidth, vim.wo.winfixwidth = fixed, fixed
end

function M.toggle()
  vim.g.layout_auto = not vim.g.layout_auto
  vim.notify("Auto panel layout " .. (vim.g.layout_auto and "on" or "off"), vim.log.levels.INFO, { title = "Layout" })
end

function M.setup()
  -- WinNew doesn't say which window is new (nvim_open_win without `enter`
  -- leaves the old one current), so arrange every window not seen before.
  -- Openers set the buffer synchronously after splitting, so by the next tick
  -- the window shows what it was opened for.
  local function scan(arrange)
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      if not vim.w[w].layout_seen then
        vim.w[w].layout_seen = true
        if arrange then M.arrange(w) end
      end
    end
  end
  -- Sidebars keep their width too: with 'equalalways' off, a panel's
  -- `vertical resize` would otherwise take its columns from neo-tree.
  api.nvim_create_autocmd("FileType", {
    group = api.nvim_create_augroup("layout_sidebars", { clear = true }),
    pattern = "neo-tree",
    callback = function(ev)
      for _, w in ipairs(vim.fn.win_findbuf(ev.buf)) do vim.wo[w].winfixwidth = true end
    end,
  })
  -- ...and file windows never do: 'winfixwidth' is window-local, so a former
  -- panel window now showing a file (`:e` in a terminal's window, `:q`
  -- swapping buffers in place) would keep it and push the squeeze elsewhere.
  api.nvim_create_autocmd("BufWinEnter", {
    group = "layout_sidebars",
    callback = function(ev)
      if vim.bo[ev.buf].filetype == "neo-tree" then
        vim.wo.winfixwidth = true
      elseif vim.bo[ev.buf].buftype == "" and vim.wo.winfixwidth then
        vim.wo.winfixwidth, vim.w.layout_width = false, nil
      end
    end,
  })
  local group = api.nvim_create_augroup("layout_panels", { clear = true })
  api.nvim_create_autocmd("WinNew", {
    group = group,
    callback = function() vim.schedule(function() scan(true) end) end,
  })
  -- Screen updates come after the scheduled arrange, so this records the
  -- restored width, or yours after a manual resize.
  api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      for _, w in ipairs(vim.v.event.windows or {}) do
        if vim.w[w].layout_width and api.nvim_win_is_valid(w) then
          vim.w[w].layout_width = api.nvim_win_get_width(w)
        end
      end
    end,
  })
  api.nvim_create_autocmd({ "VimEnter", "TabEnter", "SessionLoadPost" }, {
    group = group,
    callback = function() scan(false) end,
  })

  local map = vim.keymap.set
  map("n", "<leader>|", function() M.split("v") end, { desc = "Split window vertically" })
  map("n", "<leader>-", function() M.split("h") end, { desc = "Split window horizontally" })
  map("n", "<leader>\\", function() M.split("auto") end, { desc = "Split window along its longer side" })
  map("n", "<leader>uw", M.toggle, { desc = "Toggle auto panel layout" })
  map("n", "<leader>fb", function()
    require("telescope.builtin").buffers({ sort_mru = true, ignore_current_buffer = true })
  end, { desc = "Find buffer (<C-v>/<C-x> open in a split)" })
end

return M
