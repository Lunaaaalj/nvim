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
  -- K is owned by ufo (peek fold -> hover.nvim, whose LSP provider covers this);
  -- a buffer-local map here would shadow it in every LSP buffer.

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

-- Inlay hint labels go into inline virtual text verbatim. Some servers put
-- control characters in them (texlab's \ref hints copy the figure's \caption,
-- line breaks included). The terminal acts on a raw "\n", so the drawn text
-- and Neovim's grid disagree, and scrolling smears it over neighbouring
-- windows (the kitty PDF preview). Flatten whitespace, and cap the label so
-- a long caption doesn't push the line past the window.
local max_hint_width = 40

local function clean_hints(hints)
  for _, hint in ipairs(hints or {}) do
    local is_str = type(hint.label) == "string"
    local parts = is_str and { { value = hint.label } } or hint.label --[[@as table]]
    local room = max_hint_width
    local kept = {}
    for _, part in ipairs(parts) do
      local v = part.value:gsub("%s+", " ")
      local w = vim.fn.strdisplaywidth(v)
      if w > room then
        v = vim.fn.strcharpart(v, 0, math.max(room - 1, 0)) .. "…"
        while vim.fn.strdisplaywidth(v) > room and #v > 3 do
          v = vim.fn.strcharpart(v, 0, vim.fn.strchars(v) - 2) .. "…"
        end
        part.value = v
        kept[#kept + 1] = part
        break
      end
      part.value = v
      kept[#kept + 1] = part
      room = room - w
    end
    hint.label = is_str and (kept[1] and kept[1].value or "") or kept
  end
  return hints
end

local inlay_handler = vim.lsp.handlers["textDocument/inlayHint"]
vim.lsp.handlers["textDocument/inlayHint"] = function(err, result, ctx, config)
  return inlay_handler(err, clean_hints(result), ctx, config)
end

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspAttach", { clear = true }),
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    on_attach(client, ev.buf)
  end,
})
