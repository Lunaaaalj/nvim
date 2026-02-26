return {
    {
  "williamboman/mason.nvim",
  build = ":MasonUpdate",
  config = function()
      require("mason").setup()

require("mason-lspconfig").setup({
  ensure_installed = {
    "clangd",   -- C/C++
    "pyright",  -- Python
  },
})
end
},
{
  "williamboman/mason-lspconfig.nvim",
  dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
},
}
