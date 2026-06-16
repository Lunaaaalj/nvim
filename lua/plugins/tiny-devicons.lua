-- Colorizes file-type icons (in neo-tree, telescope, bufferline, ...) by their
-- real devicon color instead of a flat single tone.
return {
  "rachartier/tiny-devicons-auto-colors.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = "VeryLazy",
  opts = {},
}
