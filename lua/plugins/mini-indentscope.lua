return {
    "echasnovski/mini.indentscope",
    version = "*",
    event = "BufReadPre",
    init = function()
        -- disable in special buffers
        vim.api.nvim_create_autocmd("FileType", {
            pattern = { "neo-tree", "toggleterm", "lazy", "mason", "help", "noice", "trouble" },
            callback = function()
                vim.b.miniindentscope_disable = true
            end,
        })
    end,
    config = function()
        require("mini.indentscope").setup({
            symbol = "│",
            options = { try_as_border = true },
            draw = {
                delay = 80,
                animation = require("mini.indentscope").gen_animation.none(),
            },
        })
    end,
}
