return {
    "kevinhwang91/nvim-ufo",
    dependencies = { "kevinhwang91/promise-async" },
    config = function()
        vim.o.foldcolumn = "1"
        vim.o.foldlevel = 99
        vim.o.foldlevelstart = 99
        vim.o.foldenable = true

        require("ufo").setup({
            provider_selector = function()
                return { "treesitter", "indent" }
            end,
        })

        vim.keymap.set("n", "zR", require("ufo").openAllFolds,          { desc = "Open all folds" })
        vim.keymap.set("n", "zM", require("ufo").closeAllFolds,         { desc = "Close all folds" })
        vim.keymap.set("n", "zr", require("ufo").openFoldsExceptKinds,  { desc = "Open folds (except kinds)" })
        -- Peek fold if cursor is on a fold; otherwise fall through to hover.nvim
        vim.keymap.set("n", "K", function()
            local winid = require("ufo").peekFoldedLinesUnderCursor()
            if not winid then
                require("hover").hover()
            end
        end, { desc = "Peek fold / hover docs" })
    end,
}
