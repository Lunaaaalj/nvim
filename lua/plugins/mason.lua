return {
    {
  "williamboman/mason.nvim",
  build = ":MasonUpdate",
  config = function()
      require("mason").setup()

local capabilities = require("cmp_nvim_lsp").default_capabilities()
require("mason-lspconfig").setup({
  ensure_installed = {
    "clangd",   -- C/C++
    "pyright",  -- Python
  },
  handlers = {
    function(server_name)
      require("lspconfig")[server_name].setup({ capabilities = capabilities })
    end,
  },
})
end
},
{
  "williamboman/mason-lspconfig.nvim",
  dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
},
}
