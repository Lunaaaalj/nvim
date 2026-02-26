return {
    {
  "folke/noice.nvim",
  event = "VeryLazy",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "rcarriga/nvim-notify",
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
  },
}
}
