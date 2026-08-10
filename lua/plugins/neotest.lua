return {
    "nvim-neotest/neotest",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-treesitter/nvim-treesitter",
        "nvim-neotest/nvim-nio",
        "nvim-neotest/neotest-python",
    },
    config = function()
        require("neotest").setup({
            adapters = {
                require("neotest-python")({
                    runner = "pytest",
                    dap = { justMyCode = false },
                }),
            },
        })
    end,
    keys = {
        { "<leader>Tr", function() require("neotest").run.run() end,                   desc = "Test: run nearest" },
        { "<leader>Tf", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Test: run file" },
        { "<leader>Ts", function() require("neotest").summary.toggle() end,            desc = "Test: toggle summary" },
        { "<leader>To", function() require("neotest").output_panel.toggle() end,       desc = "Test: toggle output" },
        { "<leader>TX", function() require("neotest").run.stop() end,                  desc = "Test: stop" },
        {
            "<leader>Td",
            function() require("neotest").run.run({ strategy = "dap" }) end,
            desc = "Test: debug nearest",
        },
    },
}
