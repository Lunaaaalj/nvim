return {
    "kdheepak/lazygit.nvim",
    lazy = true,
    cmd = {
        "LazyGit",
        "LazyGitConfig",
        "LazyGitCurrentFile",
        "LazyGitFilter",
        "LazyGitFilterCurrentFile",
    },
    -- optional for floating window border decoration
    dependencies = {
        "nvim-lua/plenary.nvim",
    },
    -- setting the keybinding for LazyGit with 'keys' is recommended in
    -- order to load the plugin when the command is run for the first time
    -- <leader>gg, not <leader>lg: git lives under the <leader>g group (declared
    -- in which-key.lua, alongside diffview's gd/gh/gH/gc), and <leader>l is the
    -- LaTeX group -- where VimTeX's buffer-local maps would shadow this one in
    -- TeX buffers.
    keys = {
        { "<leader>gg", "<cmd>LazyGit<cr>", desc = "LazyGit" }
    }
}
