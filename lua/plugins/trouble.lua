return {
    "folke/trouble.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
        modes = {
            diagnostics = { auto_close = true },
        },
    },
    keys = {
        { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Trouble: workspace diagnostics" },
        { "<leader>xb", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Trouble: buffer diagnostics" },
        { "<leader>xs", "<cmd>Trouble symbols toggle<cr>", desc = "Trouble: document symbols" },
        { "<leader>xl", "<cmd>Trouble lsp toggle<cr>", desc = "Trouble: LSP refs/defs" },
        { "<leader>xq", "<cmd>Trouble qflist toggle<cr>", desc = "Trouble: quickfix list" },
    },
}
