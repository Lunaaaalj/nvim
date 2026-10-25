-- toggleterm only draws the terminal windows; ids, names, state, sending and
-- sessions live in lua/terminals/ (keymaps in lua/defaults/keymaps.lua).
return {
  "akinsho/toggleterm.nvim",
  version = "*",
  opts = {
    -- <C-\> is mapped by lua/terminals (count-aware, toggles the last used
    -- terminal), so toggleterm's own toggle-all mapping is off.
    open_mapping = nil,
    -- Default to a side (vertical) panel; make the size sensible per direction.
    direction = "vertical",
    size = function(term)
      if term.direction == "horizontal" then
        return 15
      else -- vertical / others: ~40% of the editor width (min 80 cols when wide)
        return math.max(80, math.floor(vim.o.columns * 0.4))
      end
    end,
    persist_size = true,
    persist_mode = true,
    start_in_insert = true,
    -- Don't darken the terminal background — keep it transparent so the
    -- Alacritty background shows through like every other window.
    shade_terminals = false,
    highlights = {
      Normal = { guibg = "NONE" },
      NormalFloat = { guibg = "NONE" },
      FloatBorder = { guibg = "NONE" },
      WinBar = { guibg = "NONE" },
      WinBarNC = { guibg = "NONE" },
    },
    float_opts = { border = "rounded" },
    -- Every terminal (including ones made by :ToggleTerm / :TermExec) reports
    -- to lua/terminals, which tracks its state and names.
    on_create = function(t) require("terminals").attach(t) end,
    on_open = function(t) require("terminals").on_open(t) end,
    on_exit = function(t) require("terminals").on_exit(t) end,
    -- Winbar = a tab-strip of all terminals. toggleterm calls name_formatter
    -- once per terminal and highlights the window's own one (WinBarActive);
    -- each label is "<id> <state glyph> <name>".
    winbar = {
      enabled = true,
      name_formatter = function(term) return require("terminals").winbar_label(term) end,
    },
  },
  config = function(_, opts)
    require("toggleterm").setup(opts)
    require("terminals").setup()
  end,
}
