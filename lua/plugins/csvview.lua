-- CSV/TSV as a table (issue #40, phase 5): columns aligned with virtual text
-- (the file is not changed), borders between fields, the header row sticky.
-- On by default in csv/tsv buffers; <leader>uv toggles it there.
return {
  "hat0uma/csvview.nvim",
  ft = { "csv", "tsv" },
  cmd = { "CsvViewEnable", "CsvViewDisable", "CsvViewToggle" },
  opts = {
    parser = { comments = { "#", "//" } },
    view = {
      display_mode = "border",
      header_lnum = 1,
      sticky_header = { enabled = true },
    },
    -- no field keymaps: <Tab> is bufferline's and if/af are treesitter's
  },
  config = function(_, opts)
    require("csvview").setup(opts)
    local function on(buf)
      vim.api.nvim_buf_call(buf, function() pcall(vim.cmd, "CsvViewEnable") end)
      vim.keymap.set("n", "<leader>uv", "<cmd>CsvViewToggle<cr>", { buffer = buf, desc = "CSV: toggle the table view" })
    end
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "csv", "tsv" },
      group = vim.api.nvim_create_augroup("CsvViewAuto", { clear = true }),
      callback = function(ev) on(ev.buf) end,
    })
    -- the buffer that triggered the lazy load already had its FileType
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and (vim.bo[buf].filetype == "csv" or vim.bo[buf].filetype == "tsv") then on(buf) end
    end
  end,
}
