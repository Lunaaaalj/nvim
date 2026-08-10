return {
    "Wansmer/treesj",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
        use_default_keymaps = false,
        max_join_length = 150,
    },
    keys = {
        { "<leader>j", function() require("treesj").toggle() end, desc = "TreeSJ: toggle split/join block" },
    },
}
