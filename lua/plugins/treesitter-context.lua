return {
    "nvim-treesitter/nvim-treesitter-context",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
        max_lines = 3,
        trim_scope = "outer",
        mode = "cursor",
    },
    keys = {
        { "<leader>ut", "<cmd>TSContextToggle<cr>", desc = "Toggle treesitter context" },
    },
}
