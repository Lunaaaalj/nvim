return {
    "EdenEast/nightfox.nvim",
    config = function()
        require("nightfox").setup({
            options = {
                transparent = true, -- disable setting the background color
            },
        })
    end,
}
