return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
   -- Shows `recording @q` while a macro is being recorded (noice silences the
   -- default message, so surface it here instead).
   local function macro_recording()
     local reg = vim.fn.reg_recording()
     if reg == "" then return "" end
     return "recording @" .. reg
   end

   -- Names of the LSP clients attached to the current buffer, e.g. "  pyright".
   local function lsp_clients()
     local bufnr = vim.api.nvim_get_current_buf()
     local names = {}
     for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
       names[#names + 1] = client.name
     end
     if #names == 0 then return "" end
     return "  " .. table.concat(names, ", ")
   end

   require('lualine').setup {
  options = {
    icons_enabled = true,
    theme = 'auto',
    component_separators = { left = '', right = ''},
    section_separators = { left = '', right = ''},
    disabled_filetypes = {
      statusline = {},
      winbar = {},
    },
    ignore_focus = {},
    always_divide_middle = true,
    always_show_tabline = true,
    globalstatus = true,
    refresh = {
      statusline = 1000,
      tabline = 1000,
      winbar = 1000,
      refresh_time = 16, -- ~60fps
      events = {
        'WinEnter',
        'BufEnter',
        'BufWritePost',
        'SessionLoadPost',
        'FileChangedShellPost',
        'VimResized',
        'Filetype',
        'CursorMoved',
        'CursorMovedI',
        'ModeChanged',
      },
    }
  },
  sections = {
    lualine_a = { 'mode' },
    lualine_b = { 'branch', 'diff' },
    lualine_c = {
      -- relative path + modified/readonly flags
      { 'filename', path = 1, symbols = { modified = ' ●', readonly = ' ', unnamed = '[No Name]' } },
      { macro_recording, color = { fg = '#ff5555', gui = 'bold' } },
    },
    lualine_x = {
      { 'diagnostics', sources = { 'nvim_lsp' }, symbols = { error = ' ', warn = ' ', info = ' ' } },
      { lsp_clients },
      'filetype',
    },
    lualine_y = { 'progress' },
    lualine_z = { 'location' },
  },
  inactive_sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = {'filename'},
    lualine_x = {'location'},
    lualine_y = {},
    lualine_z = {}
  },
  tabline = {},
  winbar = {},
  inactive_winbar = {},
  extensions = {}
}  end,
}
