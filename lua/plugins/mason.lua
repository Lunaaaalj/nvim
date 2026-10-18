return {
  {
    "mason-org/mason.nvim",
    build = ":MasonUpdate",
    config = function()
      require("mason").setup()

      -- Shared capabilities for every server. Neovim 0.11 layers configs as
      -- vim.lsp.config("*") -> lspconfig's lsp/<name>.lua -> vim.lsp.config(name),
      -- so per-server entries below only need to state what differs.
      vim.lsp.config("*", { capabilities = require("cmp_nvim_lsp").default_capabilities() })

      -- Per-server overrides. on_attach keymaps are bound globally via the
      -- LspAttach autocmd in lua/defaults/lsp.lua.
      local servers = {
        clangd = {
          -- clangd defaults to utf-8 offsets; nvim/cmp expect utf-16. Pinning
          -- this silences the "multiple offset encodings" warning.
          capabilities = { offsetEncoding = { "utf-16" } },
        },
        pyright = {
          settings = {
            -- ruff owns linting + import organising; keep pyright for types only.
            pyright = { disableOrganizeImports = true },
            python = { analysis = { typeCheckingMode = "basic" } },
          },
        },
        ruff = {
          -- ruff exposes a hover handler that duplicates pyright; quiet it.
          on_attach = function(client) client.server_capabilities.hoverProvider = false end,
        },
        emmet_language_server = {
          filetypes = { "html", "css", "scss", "javascriptreact", "typescriptreact" },
        },
      }
      for name, opts in pairs(servers) do
        vim.lsp.config(name, opts)
      end

      -- mason-lspconfig v2 has no `handlers`: `automatic_enable` (default true)
      -- calls vim.lsp.enable() for each installed server, picking up the configs
      -- registered above. They must be registered before this setup() call.
      require("mason-lspconfig").setup({
        ensure_installed = {
          "clangd",                 -- C/C++
          "pyright",                -- Python types
          "ruff",                   -- Python lint/imports
          "ts_ls",                  -- JS/TS
          "html",                   -- HTML
          "cssls",                  -- CSS
          "emmet_language_server",  -- Emmet expansion
          "texlab",                 -- LaTeX
          "lua_ls",                 -- Lua (this config)
          "r_language_server",      -- R / Quarto .qmd R chunks
        },
      })
    end,
  },
  {
    "mason-org/mason-lspconfig.nvim",
    dependencies = { "mason-org/mason.nvim", "neovim/nvim-lspconfig" },
  },
  {
    -- Guarantees the non-LSP tools that conform.nvim (formatters) and nvim-dap
    -- (debug adapters) call by name are actually installed, instead of silently
    -- relying on them being on PATH.
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "mason-org/mason.nvim" },
    config = function()
      require("mason-tool-installer").setup({
        ensure_installed = {
          "black", "isort",      -- Python format
          "stylua",              -- Lua format
          "clang-format",        -- C/C++ format
          "latexindent",         -- LaTeX format
          "prettier",            -- web/markdown format
          "codelldb",            -- C/C++ debug adapter
          "debugpy",             -- Python debug adapter
        },
      })
    end,
  },
}
