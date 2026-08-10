return {
  {
    "folke/zen-mode.nvim",
    dependencies = {
      -- Dims all code except the paragraph/function under the cursor.
      { "folke/twilight.nvim", opts = { context = 12, treesitter = true } },
    },
    keys = {
      { "<leader>z", "<cmd>ZenMode<cr>", desc = "Toggle Zen mode" },
    },
    opts = {
      window = {
        -- backdrop = 1 disables the dim overlay so the transparent Alacritty
        -- background still shows through (the default 0.95 paints a dark tint
        -- that fights this config's transparency).
        backdrop = 1,
        width = 90,        -- columns of text; absolute so prose/code stays comfortable
        height = 1,        -- full height
        options = {
          number = false,
          relativenumber = false,
          signcolumn = "no",
          cursorline = false,
          foldcolumn = "0", -- hide the ufo fold-depth digits
          list = false,
        },
      },
      plugins = {
        -- Strip global UI chrome for the duration of zen.
        options = { enabled = true, ruler = false, showcmd = false, laststatus = 0 },
        twilight = { enabled = true },  -- auto-enable Twilight inside zen
        gitsigns = { enabled = false }, -- hide git signs in the gutter
        tmux = { enabled = false },
      },
      -- Pause this config's ambience plugins so zen is genuinely quiet, then
      -- restore them on exit. Each call is guarded — a missing/disabled plugin
      -- just no-ops rather than erroring.
      on_open = function()
        vim.g.miniindentscope_disable = true
        pcall(function() require("illuminate").pause() end)
        pcall(vim.cmd, "SatelliteDisable")
        pcall(function() require("precognition").hide() end)
      end,
      on_close = function()
        vim.g.miniindentscope_disable = false
        pcall(function() require("illuminate").resume() end)
        pcall(vim.cmd, "SatelliteEnable")
      end,
    },
  },
}
