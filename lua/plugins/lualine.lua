return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
    local lutils = require("lualine.utils.utils")

    -- Pull a color out of the active colorscheme (with a fallback) so the theme
    -- tracks `<leader>cs` changes instead of hardcoding a palette.
    local function pick(group, attr, fallback)
      local c = lutils.extract_highlight_colors(group, attr)
      return c or fallback
    end

    -- Choose readable text for a colored block based on the accent's luminance,
    -- so the mode/edge labels stay legible on both dark and light schemes.
    local function on_accent(hex)
      if type(hex) ~= "string" or hex:sub(1, 1) ~= "#" or #hex < 7 then
        return "#11121a"
      end
      local r = tonumber(hex:sub(2, 3), 16) or 0
      local g = tonumber(hex:sub(4, 5), 16) or 0
      local b = tonumber(hex:sub(6, 7), 16) or 0
      local luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
      return luminance > 0.55 and "#16181a" or "#11121a"
    end

    -- Build a transparent-middle, earthy-accent theme from the current scheme:
    -- only the mode (section a) and the final progress (section z) get a colored
    -- block; everything between flows over the transparent terminal background.
    local function build_theme()
      local normal_acc  = pick("Function", "fg", "#7daea3")
      local insert_acc  = pick("String", "fg", "#a9b665")
      local visual_acc  = pick("Statement", "fg", "#d8a657")
      local replace_acc = pick("DiagnosticError", "fg", "#ea6962")
      local command_acc = pick("Constant", "fg", "#d3869b")
      local fg_main     = pick("Normal", "fg", "#d4be98")
      local fg_muted    = pick("Comment", "fg", "#7c6f64")

      local function edge(acc)
        return { a = { bg = acc, fg = on_accent(acc), gui = "bold" }, z = { bg = acc, fg = on_accent(acc), gui = "bold" } }
      end
      local mid = {
        b = { bg = "none", fg = fg_main },
        c = { bg = "none", fg = fg_muted },
        x = { bg = "none", fg = fg_muted },
        y = { bg = "none", fg = fg_main },
      }
      local function mode(acc)
        return vim.tbl_extend("force", {}, edge(acc), mid)
      end

      return {
        normal   = mode(normal_acc),
        insert   = mode(insert_acc),
        visual   = mode(visual_acc),
        replace  = mode(replace_acc),
        command  = mode(command_acc),
        inactive = {
          a = { bg = "none", fg = fg_muted, gui = "bold" },
          b = { bg = "none", fg = fg_muted },
          c = { bg = "none", fg = fg_muted },
          x = { bg = "none", fg = fg_muted },
          y = { bg = "none", fg = fg_muted },
          z = { bg = "none", fg = fg_muted },
        },
      }
    end

    -- Shows `recording @q` while a macro is being recorded (noice silences the
    -- default message, so surface it here instead).
    local function macro_recording()
      local reg = vim.fn.reg_recording()
      if reg == "" then return "" end
      return " recording @" .. reg
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

    local function setup()
      require("lualine").setup({
        options = {
          icons_enabled = true,
          theme = build_theme(),
          component_separators = { left = "", right = "" },
          section_separators = { left = "", right = "" },
          disabled_filetypes = { statusline = {}, winbar = {} },
          ignore_focus = { "neo-tree" },
          always_divide_middle = true,
          globalstatus = true,
          refresh = {
            statusline = 1000,
            refresh_time = 16, -- ~60fps
            events = {
              "WinEnter", "BufEnter", "BufWritePost", "SessionLoadPost",
              "FileChangedShellPost", "VimResized", "Filetype",
              "CursorMoved", "CursorMovedI", "ModeChanged", "RecordingEnter", "RecordingLeave",
            },
          },
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = {
            { "branch", icon = "" },
            { "diff", symbols = { added = " ", modified = " ", removed = " " } },
          },
          lualine_c = {
            { "filename", path = 1, symbols = { modified = " ●", readonly = " ", unnamed = "[No Name]" } },
            { macro_recording, color = { fg = "#ea6962", gui = "bold" } },
            { "searchcount" },
            { "selectioncount" },
          },
          lualine_x = {
            { "diagnostics", sources = { "nvim_lsp" }, symbols = { error = " ", warn = " ", info = " ", hint = " " } },
            { lsp_clients, color = { gui = "italic" } },
            { "filetype", colored = true, icon_only = false },
            { "encoding", fmt = string.upper },
          },
          lualine_y = { "location" },
          lualine_z = { "progress" },
        },
        inactive_sections = {
          lualine_a = {},
          lualine_b = {},
          lualine_c = { { "filename", path = 1 } },
          lualine_x = { "location" },
          lualine_y = {},
          lualine_z = {},
        },
        extensions = { "neo-tree", "lazy", "toggleterm", "trouble", "quickfix" },
      })
    end

    setup()

    -- Rebuild the earthy palette whenever the colorscheme changes so the accent
    -- colors stay derived from the active scheme.
    vim.api.nvim_create_autocmd("ColorScheme", { callback = setup })
  end,
}
