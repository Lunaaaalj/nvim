return {
    {
  "folke/noice.nvim",
  event = "VeryLazy",
  dependencies = {
    "MunifTanjim/nui.nvim",
    {
      "rcarriga/nvim-notify",
      opts = {
        -- `static` (no fade) avoids the dark-corner artifacts that fade/slide
        -- stages leave when the toast bg is transparent. The hex below is only
        -- the blend reference and silences nvim-notify's "NotifyBackground has
        -- no background highlight" warning; actual transparency comes from the
        -- Notify* groups stripped in lua/defaults/init.lua's ColorScheme autocmd.
        stages = "static",
        background_colour = "#000000",
        timeout = 3000,
      },
    },
  },
  keys = {
    { "<leader>sn", "<cmd>Noice history<cr>", desc = "Show notification history" },
    { "<leader>sd", "<cmd>Noice dismiss<cr>", desc = "Dismiss visible notifications" },
  },
  opts = {
    cmdline = {
      enabled = true,
      view = "cmdline_popup", -- popup command line (can appear near top)
    },
    messages = { enabled = true },
    popupmenu = { enabled = true },
    lsp = {
      progress = { enabled = true },
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
