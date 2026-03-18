# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Opinionated Neovim config written in Lua using `lazy.nvim` as the plugin manager. Targets macOS with Kitty terminal.

## Architecture

### Load order
`init.lua` → `lua/defaults/init.lua` → options, keymaps, lazy bootstrap, theme → all plugin specs under `lua/plugins/`

### Key separation
- `lua/defaults/` — core Neovim settings (not plugin-specific): options, keymaps, lazy bootstrapping, LSP server setup (`lsp.lua`), and theme auto-switching
- `lua/plugins/` — one file per plugin (or tightly related group), each returning a lazy.nvim spec table

### Theme
`lua/defaults/theme.lua` polls macOS `defaults read -g AppleInterfaceStyle` every 2 seconds and switches between `kanso-zen` (dark) and `kanso-pearl` (light). The colorscheme is `kanso` (set in `defaults/init.lua`). On non-macOS, edit this file.

### LSP
Two-layer setup: `lua/plugins/mason.lua` ensures `clangd` and `pyright` are installed via mason-lspconfig; `lua/defaults/lsp.lua` configures `tsserver` with on-attach keymaps. Add new LSP servers to either layer depending on whether they need mason management.

### Molten / notebooks
`molten.nvim` uses `image.nvim` with the Kitty backend. Requires `:UpdateRemotePlugins` after install.

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
| `<leader>n` | Toggle Neo-tree |
| `<leader>t` | Toggle vertical terminal (size 60) |
| `<leader>ac` | Toggle ClaudeCode |
| `<leader>e` | Molten evaluate operator |
| `<leader>r` (visual) | Molten evaluate selection |
| `<leader>rr` | Molten re-evaluate cell |
| `<leader>os` | Molten open output window |
| `<leader>oh` | Molten hide output |
| `<leader>md` | Molten delete cell |
| `<localleader>mx` | Molten open output in browser |
| `gd` / `K` / `gr` / `<leader>rn` | LSP definition / hover / references / rename |
| `<C-h/j/k/l>` | Move between windows |

## External dependencies

- `lazygit` binary (for lazygit.nvim)
- `gh` CLI (for octo.nvim)
- `make` (for telescope-fzf-native)
- Kitty terminal (for image.nvim)
- macOS `defaults` command (for theme auto-switching)
