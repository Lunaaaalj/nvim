return {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
    opts = {},
    keys = {
        { "<leader>gd", "<cmd>DiffviewOpen<cr>",          desc = "Diffview: open" },
        { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: file history" },
        { "<leader>gH", "<cmd>DiffviewFileHistory<cr>",   desc = "Diffview: repo history" },
        { "<leader>gc", "<cmd>DiffviewClose<cr>",         desc = "Diffview: close" },
    },
}
