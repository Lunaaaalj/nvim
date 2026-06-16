return {
    "lewis6991/hover.nvim",
    config = function()
        require("hover").setup({
            init = function()
                require("hover.providers.lsp")
                require("hover.providers.man")
                require("hover.providers.dictionary")
            end,
            preview_opts = { border = "rounded" },
            preview_window = false,
            title = true,
        })
        -- override K to use hover.nvim; scroll with gs/gS
        vim.keymap.set("n", "K", require("hover").hover, { desc = "Hover docs" })
        vim.keymap.set("n", "gK", require("hover").hover_select, { desc = "Hover: select provider" })
        vim.keymap.set("n", "<C-p>", function() require("hover").hover_switch("previous") end, { desc = "Hover: prev provider" })
        vim.keymap.set("n", "<C-n>", function() require("hover").hover_switch("next") end, { desc = "Hover: next provider" })
    end,
}
