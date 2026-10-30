return {
    "lewis6991/hover.nvim",
    config = function()
        require("hover").config({
            providers = {
                "hover.providers.diagnostic",
                "hover.providers.lsp",
                "hover.providers.dap",
                -- C/C++/Python/R references (lua/refdocs), right after LSP.
                "refdocs.hover",
                -- The stock man provider looks up section 1, so `printf` in C
                -- showed the shell command; refdocs owns C, this keeps the shells.
                {
                    module = "hover.providers.man",
                    enabled = function(bufnr)
                        return vim.tbl_contains({ "sh", "zsh", "tcl", "make" }, vim.bo[bufnr].filetype)
                    end,
                },
                "hover.providers.dictionary",
            },
            preview_opts = { border = "rounded" },
            preview_window = false,
            title = true,
        })
        -- K itself is bound in ufo.lua (peek fold, else hover.nvim).
        vim.keymap.set("n", "gK", require("hover").select, { desc = "Hover: select provider" })
        vim.keymap.set("n", "<C-p>", function() require("hover").switch("previous") end, { desc = "Hover: prev provider" })
        vim.keymap.set("n", "<C-n>", function() require("hover").switch("next") end, { desc = "Hover: next provider" })
    end,
}
