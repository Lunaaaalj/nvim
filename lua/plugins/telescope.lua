return {
    {
    'nvim-telescope/telescope.nvim', version = '*',
    dependencies = {
        'nvim-lua/plenary.nvim',
        -- optional but recommended
        { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
        },
    config = function()
      local telescope = require('telescope')
      telescope.setup({
        defaults = {
          -- Rounded borders read clearly against the transparent background
          borderchars = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
          layout_strategy = 'flex',
          layout_config = {
            prompt_position = 'top',
            horizontal = { preview_width = 0.55 },
          },
          sorting_strategy = 'ascending',
          path_display = { 'truncate' },
        },
      })
      pcall(telescope.load_extension, 'fzf')
    end,
    }
}
