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
            typst = { "typstyle" },
            html = { "prettier" },
            css = { "prettier" },
            scss = { "prettier" },
            json = { "prettier" },
            yaml = { "prettier" },
            markdown = { "prettier" },
        },
        formatters = {
            -- Without a .clang-format, use the same fallback style the editor's
            -- C-family indent is derived from (projectrc.nvim).
            clang_format = {
                prepend_args = function(_, ctx)
                    return require("projectrc").clang_format_args(ctx.filename)
                end,
            },
        },
        -- Function form so the <leader>uf toggle (vim.g.disable_autoformat) can
        -- disable format-on-save globally without unloading the plugin.
        format_on_save = function(bufnr)
            if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
                return
            end
            -- project settings (projectrc.nvim) can turn it off or pick formatters
            local project = require("projectrc").format_opts(bufnr, true)
            if not project then return end
            return vim.tbl_extend("force", { timeout_ms = 2000, lsp_fallback = true }, project)
        end,
    },
    keys = {
        {
            "<leader>cf",
            function()
                local project = require("projectrc").format_opts(0)
                require("conform").format(vim.tbl_extend("force", { async = true, lsp_fallback = true }, project))
            end,
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
