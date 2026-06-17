return {
  {
    "nvim-treesitter/nvim-treesitter",
    -- Pin the master branch: it keeps the declarative ensure_installed/highlight
    -- API (and the `nvim-treesitter.configs` module) that this config and
    -- treesitter-context/rainbow-delimiters/textobjects expect. The `main`
    -- rewrite ignores this config shape, so highlighting was silently off.
    branch = "master",
    lazy = false,
    build = ":TSUpdate",
    dependencies = {
      -- master branch to match nvim-treesitter master: it reads the textobjects
      -- table in configs.setup() below and registers the keymaps automatically.
      -- (The main/rewrite branch ignores that table and needs manual binding.)
      { "nvim-treesitter/nvim-treesitter-textobjects", branch = "master" },
    },
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = {
          "lua", "vim", "vimdoc", "bash", "query",
          "python", "cpp", "c",
          "markdown", "markdown_inline",
          "html", "css", "latex",
          "json", "yaml", "toml",
        },
        -- Install into the canonical site dir: nvim-treesitter appends "/parser",
        -- yielding ~/.local/share/nvim/site/parser, which is ALWAYS on the
        -- runtimepath. Compiling here overwrites any stale parsers in place
        -- (the old python.so triggered an "Invalid node type except*" error
        -- against master's newer queries) and survives plugin updates.
        parser_install_dir = vim.fn.stdpath("data") .. "/site",
        highlight = {
          enable = true,
          -- vimtex owns LaTeX syntax/conceal; let it, to avoid double-highlight.
          disable = { "latex" },
          additional_vim_regex_highlighting = false,
        },
        indent = { enable = true },
        textobjects = {
          select = {
            enable = true,
            lookahead = true,
            keymaps = {
              ["af"] = "@function.outer",
              ["if"] = "@function.inner",
              ["ac"] = "@class.outer",
              ["ic"] = "@class.inner",
              ["aa"] = "@parameter.outer",
              ["ia"] = "@parameter.inner",
            },
          },
          swap = {
            enable = true,
            swap_next = { ["<leader>sp"] = "@parameter.inner" },
            swap_previous = { ["<leader>sP"] = "@parameter.inner" },
          },
          move = {
            enable = true,
            set_jumps = true,
            goto_next_start = { ["]m"] = "@function.outer", ["]]"] = "@class.outer" },
            goto_previous_start = { ["[m"] = "@function.outer", ["[["] = "@class.outer" },
          },
        },
      })
    end,
  },
}
