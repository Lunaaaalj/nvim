-- Global LSP keymaps + behaviour. A single LspAttach autocmd binds buffer-local
-- maps for ANY language server (clangd, pyright, ts_ls, texlab, html, ...), so
-- navigation works everywhere instead of only for one hardcoded server.
-- This file is required from lua/defaults/init.lua; it only registers autocmds,
-- so it is safe to load before lazy.nvim brings the servers up.

local function on_attach(client, bufnr)
  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc, silent = true })
  end

  -- Navigation / info
  map("n", "gd", vim.lsp.buf.definition, "LSP: definition")
  map("n", "gD", vim.lsp.buf.declaration, "LSP: declaration")
  map("n", "gr", vim.lsp.buf.references, "LSP: references")
  map("n", "gi", vim.lsp.buf.implementation, "LSP: implementation")
  map("n", "gy", vim.lsp.buf.type_definition, "LSP: type definition")
  map("n", "K", vim.lsp.buf.hover, "LSP: hover")

  -- Refactor / actions
  map("n", "<leader>rn", vim.lsp.buf.rename, "LSP: rename")
  map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, "LSP: code action")

  -- Diagnostics navigation (the <leader>d float lives in keymaps.lua)
  map("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, "Prev diagnostic")
  map("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, "Next diagnostic")

  -- Inlay hints: enable when the server supports them, with a toggle.
  if client and client.supports_method("textDocument/inlayHint") then
    vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
    map("n", "<leader>uh", function()
      vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), { bufnr = bufnr })
    end, "Toggle inlay hints")
  end
end

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspAttach", { clear = true }),
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    on_attach(client, ev.buf)
  end,
})
