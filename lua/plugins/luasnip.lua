return {
    {
        "L3MON4D3/LuaSnip",
        version = "v2.*",
        build = "make install_jsregexp",
        dependencies = { "rafamadriz/friendly-snippets" },
        config = function()
            local ls = require("luasnip")

            ls.setup({
                enable_autosnippets = true,
                update_events = { "TextChanged", "TextChangedI" },
                region_check_events = { "InsertEnter" },
                delete_check_events = { "TextChanged" },
            })

            require("luasnip.loaders.from_vscode").lazy_load()
            require("luasnip.loaders.from_lua").lazy_load({
                paths = { vim.fn.stdpath("config") .. "/lua/snippets" },
            })
        end,
    },
}
