return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    lazy = false,

    config = function()
      require("neo-tree").setup({
        window = {
          width = 40,
        },
        default_component_configs = {
          -- Explicit git symbols so the gutter reads clearly regardless of the
          -- terminal's nerd-font variant (the defaults use wide nf-md glyphs
          -- that render cramped/ambiguous in the "Mono" font variant).
          git_status = {
            symbols = {
              added     = "",
              modified  = "",
              deleted   = "✖",
              renamed   = "󰁕",
              untracked = "",
              ignored   = "",
              unstaged  = "󰄱",
              staged    = "",
              conflict  = "",
            },
          },
        },
      })
    end,
  },
}
