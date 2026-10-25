-- Single definition of the neo-tree source tabs: the selector shows only the
-- icon (five labels don't fit the 34-col tree), and bufferline's neo-tree
-- offset shows the active source's icon + name, so both read from here.
--
-- Glyphs are \u{} escapes on purpose (literal glyphs were silently stripped to
-- spaces once) and BMP-only: nf-md (U+F0001+) renders as tofu in
-- JetBrainsMono Nerd Font Light under Alacritty.

local M = {}

M.tabs = {
  { source = "filesystem", icon = "\u{f07c}", name = "Files" },  -- nf-fa-folder_open
  { source = "buffers",    icon = "\u{f0c5}", name = "Buffers" }, -- nf-fa-copy
  { source = "git_status", icon = "\u{e725}", name = "Git" },    -- nf-dev-git_branch
  { source = "claude",     icon = "\u{f086}", name = "Claude" }, -- nf-fa-comments
  { source = "terminals",  icon = "\u{f120}", name = "Terminals" }, -- nf-fa-terminal
}

-- source_selector.sources entries (icon only).
function M.selector()
  return vim.tbl_map(function(t) return { source = t.source, display_name = t.icon } end, M.tabs)
end

-- "<icon>  <Name>" for the neo-tree source visible in the current tabpage.
function M.active_label()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local src = vim.b[vim.api.nvim_win_get_buf(win)].neo_tree_source
    if src then
      for _, t in ipairs(M.tabs) do
        if t.source == src then return t.icon .. "  " .. t.name end
      end
      return src
    end
  end
  return "Explorer"
end

return M
