return {
    "MagicDuck/grug-far.nvim",
    opts = {},
    keys = {
        {
            "<leader>sr",
            function()
                local grug = require("grug-far")
                local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
                grug.open(ext and ext ~= "" and { prefills = { filesFilter = "*." .. ext } } or {})
            end,
            desc = "Search & replace (grug-far)",
        },
        {
            "<leader>sR",
            function()
                require("grug-far").with_visual_selection({})
            end,
            mode = "v",
            desc = "Search & replace selection",
        },
    },
}
