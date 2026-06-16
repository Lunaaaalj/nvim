return {
    "folke/todo-comments.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = "BufReadPost",
    opts = {
        signs = true,
        keywords = {
            FIX  = { icon = " ", color = "error",   alt = { "FIXME", "BUG", "FIXIT", "ISSUE" } },
            TODO = { icon = " ", color = "info" },
            HACK = { icon = " ", color = "warning" },
            NOTE = { icon = " ", color = "hint",    alt = { "INFO" } },
        },
        highlight = { before = "", keyword = "wide_fg", after = "" },
    },
    keys = {
        { "<leader>ft", "<cmd>TodoTelescope<cr>", desc = "Find TODOs (Telescope)" },
        { "<leader>xt", "<cmd>Trouble todo toggle<cr>", desc = "Trouble: TODOs" },
        { "]t", function() require("todo-comments").jump_next() end, desc = "Next TODO" },
        { "[t", function() require("todo-comments").jump_prev() end, desc = "Prev TODO" },
    },
}
