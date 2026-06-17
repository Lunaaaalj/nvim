return {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
        preset = "classic",
        delay = 200,
        -- Anchor a narrow, tall panel to the bottom-left of the screen.
        -- col = 0 / row = math.huge place it bottom-left; the small width keeps
        -- it a vertical column rather than a wide bottom bar.
        win = {
            no_overlap = true,
            col = 0,
            row = math.huge,
            width = 0.3,
            height = { min = 4, max = 0.85 },
            border = "rounded",
            -- winblend 0: the buggy translucent-then-black flicker came from the
            -- global winblend=10 applied to which-key's float. Backgrounds are
            -- made transparent via the WhichKey* groups in defaults/init.lua.
            wo = { winblend = 0 },
        },
        layout = {
            width = { min = 20 },
            spacing = 3,
        },
        spec = {
            { "<leader>a", group = "AI/Claude" },
            { "<leader>c", group = "Code" },
            { "<leader>d", group = "Debug/Diagnostic" },
            { "<leader>f", group = "Find" },
            { "<leader>g", group = "Git" },
            { "<leader>h", group = "Git hunks" },
            { "<leader>H", group = "Harpoon" },
            { "<leader>m", group = "Molten" },
            { "<leader>o", group = "Output/Open" },
            { "<leader>q", group = "Session" },
            { "<leader>r", group = "Run/Rename" },
            { "<leader>s", group = "Search/Replace" },
            { "<leader>T", group = "Test" },
            { "<leader>u", group = "UI" },
            { "<leader>x", group = "Trouble/Diagnostics" },
            -- git-conflict default chord prefix
            { "c", group = "conflict", mode = "n" },
        },
    },
}
