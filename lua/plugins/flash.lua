return {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {
        modes = {
            search = { enabled = false }, -- keep / unmodified
            char = {
                enabled = true,
                jump_labels = true, -- label every f/t match
            },
        },
    },
    keys = {
        { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash jump" },
        { "S", mode = { "n", "o" }, function() require("flash").treesitter() end, desc = "Flash treesitter select" },
        { "r", mode = "o", function() require("flash").remote() end, desc = "Flash remote" },
        { "<c-s>", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle Flash search" },
    },
}
