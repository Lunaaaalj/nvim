# Neovim config

Opinionated Neovim setup focused on a clean UI, fast navigation, and a small set of productive plugins. Written in Lua using `lazy.nvim` as the plugin manager. Targets macOS with Kitty terminal.

## Requirements
- Neovim (recent version with Lua support)
- Git
- macOS (recommended)
- Kitty terminal (for `image.nvim`)

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
- Completion via `nvim-cmp` with autopairs
- Treesitter with common language parsers
- UI polish: `lualine`, `noice`, `notify`, `barbecue`, `nvim-navic`, `bufferline`, `smear-cursor`
- Navigation: `telescope` + `telescope-fzf-native`, `neo-tree`
- Terminal: `toggleterm`
- Git: `lazygit.nvim`, `gitsigns.nvim`
- Notebook-style evaluation: `molten.nvim` with `image.nvim`, `jupytext.nvim`
- Prose: `zen-mode.nvim`, `render-markdown.nvim`, `vimtex`
- AI: `claude-code` integration
- Persistent colorscheme: last used colorscheme is saved and restored on startup

## Keymaps (core)
Leader is `<Space>`, localleader is `\`.

| Key | Action |
|-----|--------|
| `<leader>ff` | Telescope find files |
| `<leader>cs` | Pick colorscheme (with live preview) |
| `<leader>n` | Toggle Neo-tree |
| `<leader>t` | Toggle vertical terminal (size 80) |
| `<leader>ac` | Toggle Claude Code |
| `<leader>z` | Toggle Zen Mode |
| `<leader>d` | Show diagnostics float |
| `<leader>e` | Molten evaluate operator |
| `<leader>r` (visual) | Molten evaluate selection |
| `<leader>rr` | Molten re-evaluate cell |
| `<leader>os` | Molten open output window |
| `<leader>oh` | Molten hide output |
| `<leader>md` | Molten delete cell |
| `<localleader>mx` | Molten open output in browser |
| `<Tab>` / `<S-Tab>` | Next / previous buffer |
| `<leader>x` | Close buffer |
| `gd` / `K` / `gr` / `<leader>rn` | LSP definition / hover / references / rename |
| `<C-h/j/k/l>` | Move between windows |

## Layout
- `init.lua` loads the defaults
- `lua/defaults/` — options, keymaps, LSP, and lazy bootstrapping
- `lua/plugins/` — one file per plugin spec
- `lazy-lock.json` — locked plugin versions
- `.colorscheme` — persisted colorscheme name

## Notes and Dependencies
- Colorscheme is persisted to `.colorscheme`; use `<leader>cs` to pick with live preview.
- `telescope-fzf-native` requires `make`.
- `lazygit.nvim` requires the `lazygit` binary.
- `image.nvim` is configured for the Kitty terminal backend.

## Troubleshooting
- If a plugin fails to load, run `:Lazy sync`.
- For `molten.nvim`, run `:UpdateRemotePlugins` after install.
- If the colorscheme looks off, check `.colorscheme` or run `<leader>cs` to repick.
