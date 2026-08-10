return {
  "akinsho/bufferline.nvim",
  version = "*",
  dependencies = "nvim-tree/nvim-web-devicons",
  opts = {
    options = {
      mode = "buffers",
      -- Underline the active buffer instead of a filled block — reads cleanly
      -- against the transparent background.
      indicator = { style = "underline" },
      separator_style = "thin",
      diagnostics = "nvim_lsp",
      diagnostics_indicator = function(count, level)
        local icon = level:match("error") and " " or " "
        return " " .. icon .. count
      end,
      color_icons = true,
      show_buffer_close_icons = false,
      show_close_icon = false,
      always_show_bufferline = true,
      modified_icon = "●",
      left_trunc_marker = "",
      right_trunc_marker = "",
      hover = { enabled = true, delay = 150, reveal = { "close" } },
      offsets = {
        {
          filetype = "neo-tree",
          text = "  Explorer",
          highlight = "Directory",
          text_align = "left",
          separator = true,
        },
      },
    },
    -- Keep the bufferline transparent: strip the backgrounds so only text,
    -- icons and the active-buffer underline show.
    highlights = {
      fill = { bg = "NONE" },
      background = { bg = "NONE" },
      buffer_visible = { bg = "NONE" },
      buffer_selected = { bg = "NONE", bold = true, italic = false },
      separator = { bg = "NONE" },
      separator_visible = { bg = "NONE" },
      separator_selected = { bg = "NONE" },
      modified = { bg = "NONE" },
      modified_visible = { bg = "NONE" },
      modified_selected = { bg = "NONE" },
      duplicate = { bg = "NONE", italic = true },
      duplicate_visible = { bg = "NONE", italic = true },
      duplicate_selected = { bg = "NONE", italic = true },
      indicator_selected = { bg = "NONE" },
    },
  },
}
