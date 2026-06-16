return {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    opts = {
        formatters_by_ft = {
            python = { "isort", "black" },
            lua = { "stylua" },
            cpp = { "clang_format" },
            c = { "clang_format" },
        },
        format_on_save = {
            timeout_ms = 2000,
            lsp_fallback = true,
        },
    },
    keys = {
        {
            "<leader>cf",
            function() require("conform").format({ async = true, lsp_fallback = true }) end,
            desc = "Format buffer",
        },
    },
}
