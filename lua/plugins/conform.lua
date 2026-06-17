return {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    opts = {
        formatters_by_ft = {
            python = { "isort", "black" },
            lua = { "stylua" },
            cpp = { "clang_format" },
            c = { "clang_format" },
            tex = { "latexindent" },
            html = { "prettier" },
            css = { "prettier" },
            scss = { "prettier" },
            json = { "prettier" },
            yaml = { "prettier" },
            markdown = { "prettier" },
        },
        -- Function form so the <leader>uf toggle (vim.g.disable_autoformat) can
        -- disable format-on-save globally without unloading the plugin.
        format_on_save = function(bufnr)
            if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
                return
            end
            return { timeout_ms = 2000, lsp_fallback = true }
        end,
    },
    keys = {
        {
            "<leader>cf",
            function() require("conform").format({ async = true, lsp_fallback = true }) end,
            desc = "Format buffer",
        },
        {
            "<leader>uf",
            function()
                vim.g.disable_autoformat = not vim.g.disable_autoformat
                vim.notify("Format on save: " .. (vim.g.disable_autoformat and "OFF" or "ON"))
            end,
            desc = "Toggle format on save",
        },
    },
}
