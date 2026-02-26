return {
    {
  "rcarriga/nvim-notify",
  opts = {
    stages = "fade",
    timeout = 2000,
    background_colour = "#000000",
  },
  config = function(_, opts)
    require("notify").setup(opts)
    vim.notify = require("notify")
  end,
}
}
