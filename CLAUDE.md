# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Opinionated Neovim config written in Lua using `lazy.nvim` as the plugin manager. Targets macOS with Kitty terminal.

## Architecture

### Load order
`init.lua` → `lua/defaults/init.lua` → options, keymaps, lazy bootstrap, colorscheme restore → all plugin specs under `lua/plugins/`

### Key separation
- `lua/defaults/` — core Neovim settings (not plugin-specific): options, keymaps, lazy bootstrapping, and LSP server setup (`lsp.lua`)
- `lua/plugins/` — one file per plugin (or tightly related group), each returning a lazy.nvim spec table

### Colorscheme
The last used colorscheme is persisted to `.colorscheme` (in the config root) and restored on startup via `lua/defaults/init.lua`. Any `:colorscheme` call triggers an autocmd that writes the name to that file. `<leader>cs` opens Telescope with live colorscheme preview.

### LSP
Two-layer setup: `lua/plugins/mason.lua` ensures `clangd` and `pyright` are installed via mason-lspconfig; `lua/defaults/lsp.lua` configures LSP on-attach keymaps. `lua/plugins/lsp.lua` handles additional server configuration. Add new LSP servers to either layer depending on whether they need mason management.

### Molten / notebooks
`molten.nvim` uses `image.nvim` with the Kitty backend. Requires `:UpdateRemotePlugins` after install. `jupytext.nvim` handles `.ipynb` ↔ script conversion.

## Adding a plugin

Create a new file in `lua/plugins/` returning a lazy.nvim spec:

```lua
return {
  "author/plugin-name",
  opts = { ... },
}
```

lazy.nvim auto-imports everything under `lua/plugins/`.

## Keymaps

Leader: `<Space>`, localleader: `\`

| Key | Action |
|-----|--------|
| `<leader>ff` | Telescope find files |
| `<leader>cs` | Pick colorscheme (live preview, persisted) |
| `<leader>n` | Toggle Neo-tree |
| `<leader>t` | Toggle vertical terminal (size 80) |
| `<leader>ac` | Toggle ClaudeCode |
| `<leader>z` | Toggle Zen Mode |
| `<leader>d` | Show diagnostic float |
| `<leader>e` | Molten evaluate operator |
| `<leader>r` (visual) | Molten evaluate selection |
| `<leader>rr` | Molten re-evaluate cell |
| `<leader>os` | Molten open output window |
| `<leader>oh` | Molten hide output |
| `<leader>md` | Molten delete cell |
| `<localleader>mx` | Molten open output in browser |
| `<Tab>` / `<S-Tab>` | Next / previous buffer (bufferline) |
| `<leader>x` | Close buffer |
| `gd` / `K` / `gr` / `<leader>rn` | LSP definition / hover / references / rename |
| `<C-h/j/k/l>` | Move between windows |

## External dependencies

- `lazygit` binary (for lazygit.nvim)
- `make` (for telescope-fzf-native)
- Kitty terminal (for image.nvim)
