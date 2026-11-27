return {
    {
  "folke/noice.nvim",
  event = "VeryLazy",
  dependencies = {
    "MunifTanjim/nui.nvim",
    -- murmur.nvim replaces nvim-notify: it owns vim.notify and ships the
    -- "murmur" view backend that messages are routed to below.
    "murmur.nvim",
  },
  -- <leader>sn / <leader>sd (centre, dismiss) are murmur's now
  opts = {
    -- Noice's message router re-arms a timer every `throttle` ms forever, idle
    -- or not: the default 1000/30 was ~30 of an idle Neovim's ~55 wake-ups/s
    -- (`nvim --clean`: 0). The cmdline renders in blocking mode, which this
    -- doesn't affect; only notifications, LSP progress and the search count can
    -- now appear up to 100 ms later.
    throttle = 100,
    cmdline = {
      enabled = true,
      view = "cmdline_popup", -- popup command line (can appear near top)
    },
    -- murmur (lua/plugins/murmur.lua) owns vim.notify; noice must not replace it
    notify = { enabled = false },
    -- every message noice catches (`:w` written, errors, echo…) goes to murmur,
    -- through the backend at murmur.nvim/lua/noice/view/backend/murmur.lua
    messages = { enabled = true, view = "murmur", view_error = "murmur", view_warn = "murmur" },
    popupmenu = { enabled = true },
    lsp = {
      -- murmur draws LSP progress itself (one line per task, from LspProgress)
      progress = { enabled = false },
      message = { view = "murmur" }, -- window/showMessage
      hover = { enabled = true },
      signature = { enabled = true },
    },
    presets = {
      bottom_search = true,
      command_palette = true, -- cmdline + popupmenu together, like LazyVim
      long_message_to_split = true,
      lsp_doc_border = true,
    },
    -- Transparency: route the cmdline popup and its popupmenu through NormalFloat
    -- instead of Noice's own groups. Noice re-links NoicePopupmenu -> Pmenu (a
    -- solid dark bg) whenever the menu renders, which fights any one-shot strip;
    -- NormalFloat is kept transparent by the global ColorScheme autocmd in
    -- lua/defaults/init.lua and Noice never touches it, so the popup shows the
    -- terminal background through. (Noice's own defaults suggest NormalFloat
    -- "to make it look like other floats".)
    views = {
      murmur = { backend = "murmur" },
      cmdline_popup = {
        win_options = {
          winhighlight = {
            Normal = "NormalFloat",
            FloatBorder = "FloatBorder",
            FloatTitle = "FloatTitle",
          },
        },
      },
      popupmenu = {
        win_options = {
          winhighlight = {
            Normal = "NormalFloat",
            FloatBorder = "FloatBorder",
          },
        },
      },
    },
  },
}
}
