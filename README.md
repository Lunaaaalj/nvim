# Neovim config

Opinionated Neovim setup focused on a clean UI, fast navigation, and a small set of productive plugins. This config is written in Lua and uses `lazy.nvim` as the plugin manager.

## Requirements
- Neovim (recent version with Lua support)
- Git
- macOS (recommended) for automatic light/dark theme switching via `defaults`

## Install
1. Clone the repo into your Neovim config path:

```bash
git clone <repo-url> ~/.config/nvim
```

2. Open Neovim and let `lazy.nvim` bootstrap and sync:

```bash
nvim
```

## Features
- Plugin management via `lazy.nvim`
- LSP support via `nvim-lspconfig` + `mason.nvim` (`clangd`, `pyright` ensured)
- Treesitter with common language parsers
- UI polish: `lualine`, `noice`, `notify`, `barbecue`, `nvim-navic`, winbar location
- Navigation: `telescope` + `telescope-fzf-native`, `neo-tree`
- Terminal: `toggleterm`
- Git: `lazygit.nvim`, `octo.nvim`
- Notebook-style evaluation: `molten.nvim` with `image.nvim`

## Keymaps (core)
Leader is `<Space>`.

- `<leader>ex` open netrw (`:Ex`)
- `<leader>ff` Telescope find files
- `<leader>n` toggle Neo-tree
- `<leader>t` toggle vertical terminal
- `<leader>lg` LazyGit
- `<leader>mc` Molten evaluate visual selection
- `<leader>ml` Molten evaluate line
- `gd` / `K` / `gr` / `<leader>rn` (LSP) definition / hover / references / rename
- `<C-h/j/k/l>` move between windows

## Notes and Dependencies
- Theme auto-switching uses `defaults` (macOS). On non-macOS, edit `lua/defaults/theme.lua`.
- `telescope-fzf-native` requires `make`.
- `lazygit.nvim` requires the `lazygit` binary.
- `octo.nvim` expects GitHub CLI (`gh`).
- `image.nvim` is configured for the Kitty terminal backend.

## Layout
- `init.lua` loads the defaults
- `lua/defaults/` options, keymaps, LSP, theme, and lazy bootstrapping
- `lua/plugins/` plugin specs
- `lazy-lock.json` locked plugin versions

## Troubleshooting
- If a plugin fails to load, run `:Lazy sync`.
- If the theme looks off, confirm your terminal supports true color and check `lua/defaults/theme.lua`.

