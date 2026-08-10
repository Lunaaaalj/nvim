return {
    "stevearc/oil.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
        default_file_explorer = false, -- keep neo-tree as default
        view_options = { show_hidden = true },
        float = { padding = 2 },
    },
    keys = {
        { "-", "<cmd>Oil<cr>", desc = "Oil: open parent dir" },
    },
}
