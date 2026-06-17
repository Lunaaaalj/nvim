return {
    {
        "mfussenegger/nvim-dap",
        dependencies = {
            "rcarriga/nvim-dap-ui",
            "nvim-neotest/nvim-nio",
            "mfussenegger/nvim-dap-python",
            "theHamsta/nvim-dap-virtual-text",
        },
        keys = {
            { "<leader>db", function() require("dap").toggle_breakpoint() end,                                     desc = "DAP: toggle breakpoint" },
            { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input("Condition: ")) end,             desc = "DAP: conditional breakpoint" },
            { "<leader>dc", function() require("dap").continue() end,                                              desc = "DAP: continue/start" },
            { "<leader>di", function() require("dap").step_into() end,                                             desc = "DAP: step into" },
            { "<leader>dn", function() require("dap").step_over() end,                                             desc = "DAP: step over (next)" },
            { "<leader>de", function() require("dap").step_out() end,                                              desc = "DAP: step out (exit)" },
            { "<leader>dr", function() require("dap").repl.open() end,                                             desc = "DAP: open REPL" },
            { "<leader>du", function() require("dapui").toggle() end,                                              desc = "DAP: toggle UI" },
            { "<leader>dx", function() require("dap").terminate() end,                                             desc = "DAP: terminate" },
        },
        config = function()
            local dap = require("dap")
            local dapui = require("dapui")

            require("nvim-dap-virtual-text").setup()
            require("dap-python").setup(vim.fn.expand("~/.virtualenvs/neovim/bin/python"))

            -- C/C++ via codelldb (installed by mason-tool-installer).
            dap.adapters.codelldb = {
                type = "server",
                port = "${port}",
                executable = {
                    command = vim.fn.stdpath("data") .. "/mason/bin/codelldb",
                    args = { "--port", "${port}" },
                },
            }
            dap.configurations.cpp = {
                {
                    name = "Launch (codelldb)",
                    type = "codelldb",
                    request = "launch",
                    program = function()
                        return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
                    end,
                    cwd = "${workspaceFolder}",
                    stopOnEntry = false,
                },
            }
            dap.configurations.c = dap.configurations.cpp

            dapui.setup()

            -- auto-open/close UI with debug session
            dap.listeners.after.event_initialized["dapui"] = function() dapui.open() end
            dap.listeners.before.event_terminated["dapui"] = function() dapui.close() end
            dap.listeners.before.event_exited["dapui"]     = function() dapui.close() end
        end,
    },
}
