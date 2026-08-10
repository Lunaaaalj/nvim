# Neovim config

Opinionated Neovim setup focused on a clean UI, fast navigation, and a small set of productive plugins. Written in Lua using `lazy.nvim` as the plugin manager. Targets macOS, primarily run in Alacritty.

> **Full docs live in-editor.** Run `:help nvim-config` for the complete reference: `:help nvim-keymaps` (every keymap), `:help nvim-plugins` (every plugin), and `:help nvim-notebooks` (Molten/Jupyter workflow).

## Requirements
- Neovim (recent version with Lua support)
- Git
- macOS (recommended)
- Alacritty, or any terminal (light colorschemes need a light terminal background)
- `make` (builds `telescope-fzf-native`)
- `lazygit` binary (for `lazygit.nvim`)
- `sioyek` (PDF viewer for `vimtex`)
- Formatters used by `conform`: `stylua`, `black`, `isort`, `clang-format`
- A Kitty-graphics terminal (Kitty/WezTerm/Ghostty) is only needed for inline Molten notebook images; everything else works in Alacritty
- For notebooks: a `~/.virtualenvs/neovim` venv with `pynvim`, `jupyter_client`, `jupytext` (see `:help nvim-notebooks`)

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
A short tour — see `:help nvim-plugins` for the full catalog.
- Plugin management via `lazy.nvim`
- LSP via `nvim-lspconfig` + `mason.nvim` (`clangd`, `pyright` auto-installed), completion via `nvim-cmp` + `luasnip`, formatting via `conform.nvim`
- Treesitter with sticky context; diagnostics/symbols via `trouble.nvim`
- Editing: `flash` motions, `nvim-surround`, `Comment.nvim`, `mini.ai`, `treesj`, `nvim-ufo` folds, `nvim-autopairs`
- Navigation: `telescope` + `telescope-fzf-native`, `neo-tree`, `oil.nvim`, `harpoon`, `grug-far` search/replace, `which-key`
- UI polish: `lualine`, `noice`, `nvim-notify`, `barbecue` + `nvim-navic`, `bufferline`, `smear-cursor`, `mini.indentscope`
- Terminal: `toggleterm`
- Git: `lazygit.nvim`, `gitsigns.nvim`, `diffview.nvim`, `git-conflict.nvim`
- Test & debug: `neotest` (pytest), `nvim-dap` with UI and Python support
- Sessions: `persistence.nvim`
- Notebooks: `molten.nvim` (+ `image.nvim`, `jupytext.nvim`) — see `:help nvim-notebooks`
- Prose: `zen-mode.nvim`, `render-markdown.nvim`, `vimtex`
- AI: `claudecode.nvim` integration
- Persistent, transparent colorschemes: last used scheme is saved and restored on startup

## Keymaps (core)
Leader is `<Space>`, localleader is `\`. This is a subset — `:help nvim-keymaps` is the complete reference, `<leader>?` searches all maps live, and `<leader>k` opens an in-editor cheatsheet.

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
- `doc/` — in-editor `:help` documentation (`:help nvim-config`)
- `docs/` — long-form prose guides (e.g. `docs/molten.md`)
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
