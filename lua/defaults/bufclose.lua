-- Buffer-centric closing: `:q` closes the current buffer instead of Neovim.
--
--   * In a split, a float, neo-tree, or with several tabpages, `:q` behaves
--     normally (closes just that window / tab).
--   * In the last editing window it closes the BUFFER and keeps the window:
--     the most recently used other listed buffer takes its place, or the
--     dashboard when none is left. `:q` on that dashboard quits Neovim.
--   * Terminal and unlisted buffers (toggleterm, Claude chats, help) are only
--     hidden, never deleted, so their jobs keep running.
--   * A modified buffer prompts Save / Discard / Cancel; `:q!` discards.
--
-- `:q` / `:q!` / `:wq` / `:wq!` are redirected by a command-line <CR> mapping
-- (only when that is the whole typed command line), so `:qa`, `:quit`,
-- searches and `<cmd>q<cr>` in mappings are untouched; the full word `:quit`
-- is the escape hatch to Vim's behaviour.
-- <leader>x and <leader>qq (quit Neovim) are bound in lua/defaults/keymaps.lua.

local M = {}

local function is_float(win)
  return vim.api.nvim_win_get_config(win).relative ~= ""
end

-- Windows that count as editing windows: not floats, not the neo-tree sidebar.
local function editing_wins()
  return vim.tbl_filter(function(w)
    return not is_float(w) and vim.bo[vim.api.nvim_win_get_buf(w)].filetype ~= "neo-tree"
  end, vim.api.nvim_tabpage_list_wins(0))
end

-- Other listed buffers: files before terminals, then most recently used first,
-- so closing a file lands on another file rather than a shell.
local function others(cur)
  local infos = vim.tbl_filter(function(b) return b.bufnr ~= cur end, vim.fn.getbufinfo({ buflisted = 1 }))
  local function term(b) return vim.bo[b.bufnr].buftype == "terminal" and 1 or 0 end
  table.sort(infos, function(a, b)
    if term(a) ~= term(b) then return term(a) < term(b) end
    return a.lastused > b.lastused
  end)
  return vim.tbl_map(function(b) return b.bufnr end, infos)
end

-- true when it is OK to drop `buf`; second value: delete with force.
local function settle_changes(buf, force)
  if force or not vim.bo[buf].modified then return true, force end
  local name = vim.api.nvim_buf_get_name(buf)
  name = name == "" and "[No Name]" or vim.fn.fnamemodify(name, ":~:.")
  local choice = vim.fn.confirm(("Save changes to %q?"):format(name), "&Yes\n&No\n&Cancel", 1, "Question")
  if choice == 1 then
    local ok, err = pcall(vim.api.nvim_buf_call, buf, function() vim.cmd("write") end)
    if not ok then vim.notify(err, vim.log.levels.ERROR) end
    return ok, false
  end
  return choice == 2, true
end

-- Close the current buffer but keep the window (<leader>x, and `:q` in the
-- last editing window).
function M.close_buffer(force)
  local cur, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  -- terminals / unlisted buffers are only hidden, so nothing is lost
  local keep = vim.bo[cur].buftype == "terminal" or not vim.bo[cur].buflisted
  local ok, hard = true, force
  if not keep then
    ok, hard = settle_changes(cur, force)
    if not ok then return end
  end

  local nxt = others(cur)[1]
  if nxt then
    vim.api.nvim_win_set_buf(win, nxt)
  else
    -- nothing left: the dashboard takes over this window (not a float)
    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, scratch)
    Snacks.dashboard.open({ buf = scratch, win = win })
  end
  if not keep and vim.api.nvim_buf_is_valid(cur) then
    vim.cmd(("bdelete%s %d"):format(hard and "!" or "", cur))
  end
end

-- `:q` / `:q!`
function M.quit(force)
  local win = vim.api.nvim_get_current_win()
  local wins = editing_wins()
  if is_float(win) or #wins > 1 or not vim.tbl_contains(wins, win) or vim.fn.tabpagenr("$") > 1 then
    return vim.cmd(force and "quit!" or "quit")
  end
  if vim.bo.filetype == "snacks_dashboard" and #others(vim.api.nvim_get_current_buf()) == 0 then
    return vim.cmd(force and "qall!" or "qall") -- nothing left to close: leave
  end
  M.close_buffer(force)
end

vim.api.nvim_create_user_command("BufQuit", function(o) M.quit(o.bang) end,
  { bang = true, desc = "Close buffer; dashboard when it was the last one" })
vim.api.nvim_create_user_command("BufWriteQuit", function(o)
  vim.cmd(o.bang and "write!" or "write")
  M.quit(false)
end, { bang = true, desc = "Write, then :BufQuit" })

-- Redirect on <CR> rather than with :cabbrev: a `q` abbreviation does not
-- expand when `!` follows it, and a `q!` abbreviation never matches (Vim only
-- scans back over non-keyword chars for it), so `:q!` would still exit.
local redirect = { ["q"] = "BufQuit", ["q!"] = "BufQuit!", ["wq"] = "BufWriteQuit", ["wq!"] = "BufWriteQuit!" }
vim.keymap.set("c", "<CR>", function()
  local to = vim.fn.getcmdtype() == ":" and redirect[vim.trim(vim.fn.getcmdline())]
  return to and ("<C-u>" .. to .. "<CR>") or "<CR>"
end, { expr = true, desc = "Redirect :q / :q! / :wq to BufQuit" })

return M
