return {
  "akinsho/toggleterm.nvim",
  version = "*",
  opts = {
    -- Count-prefix <C-\> to open numbered shells, VSCode-style: 2<C-\> opens
    -- terminal #2, 3<C-\> opens #3, etc. Each id is an independent persistent shell.
    open_mapping = [[<C-\>]],
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
    terminal_mappings = true, -- the terminal-mode maps below also work inside terms
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
    -- Per-terminal winbar rendered as a tab-strip of ALL open terminals, with the
    -- one owning this window bracketed — so each terminal shows which shell you're
    -- in and what else is open (the VSCode terminal tabs). name_formatter is called
    -- once per terminal window; we ignore the per-term arg's name and rebuild the
    -- whole strip, marking `term`'s own id.
    winbar = {
      enabled = true,
      name_formatter = function(term)
        local ok, mod = pcall(require, "toggleterm.terminal")
        if not ok then
          return ("%d: %s"):format(term.id, term.display_name or "term")
        end
        local parts = {}
        for _, t in ipairs(mod.get_all()) do
          local nm = t.display_name or vim.fn.fnamemodify(t.name or "term", ":t")
          local label = ("%d:%s"):format(t.id, nm)
          parts[#parts + 1] = (t.id == term.id) and ("[" .. label .. "]") or (" " .. label .. " ")
        end
        return table.concat(parts, " ")
      end,
    },
  },
}
