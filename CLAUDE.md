# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Opinionated Neovim config written in Lua using `lazy.nvim` as the plugin manager. Targets macOS, primarily run in Alacritty (inline notebook images require a Kitty-graphics terminal instead — see Molten / notebooks).

## Architecture

### Load order
`init.lua` → `lua/defaults/init.lua` → options, keymaps, lazy bootstrap, colorscheme restore → all plugin specs under `lua/plugins/`

### Key separation
- `lua/defaults/` — core Neovim settings (not plugin-specific): options, keymaps, lazy bootstrapping, and LSP server setup (`lsp.lua`)
- `lua/plugins/` — one file per plugin (or tightly related group), each returning a lazy.nvim spec table

### Colorscheme
The last used colorscheme is persisted to `.colorscheme` (in the config root) and restored on startup via `lua/defaults/init.lua`. Any `:colorscheme` call triggers an autocmd that writes the name to that file. `<leader>cs` opens Telescope with live colorscheme preview.

Installed schemes (one file each under `lua/plugins/`): catppuccin, kanagawa, kanso, lackluster, nightfox, everforest, melange, gruvbox-material, zenbones (+ its variants forestbones/neobones/kanagawabones/seoulbones). The palette leans earthy (grays/greens/browns), minimalist, with dark and light variants.

**Transparency:** every colorscheme renders with no editor background so the Alacritty background shows through. This is enforced two ways: native `transparent` options are set per-plugin where supported, and a global `ColorScheme` autocmd in `lua/defaults/init.lua` (`transparent_groups`) strips the bg of core groups after any scheme loads — covering schemes without a transparency option (e.g. melange). Add new groups to that list if a plugin leaves a background. Note: light colorschemes only look right if Alacritty's background is also light, since transparency means the terminal background is what shows.

### LSP
Two-layer setup: `lua/plugins/mason.lua` ensures `clangd` and `pyright` are installed via mason-lspconfig; `lua/defaults/lsp.lua` configures LSP on-attach keymaps. `lua/plugins/lsp.lua` handles additional server configuration. Add new LSP servers to either layer depending on whether they need mason management.

### Molten / notebooks
`molten.nvim` runs code in Jupyter kernels and `jupytext.nvim` handles `.ipynb` ↔ markdown conversion. Requires `:UpdateRemotePlugins` after install.

**Python host:** Neovim's Python provider points at a dedicated venv `~/.virtualenvs/neovim` (set via `vim.g.python3_host_prog` in `lua/defaults/init.lua`) that holds `pynvim`, `jupyter_client`, and `jupytext`. Homebrew's python3 is PEP-668 externally-managed, so deps aren't installed there. That venv's `bin` is prepended to `PATH` so `jupytext.nvim` (which calls a bare `jupytext`) resolves. Notebook kernels are separate per-project venvs registered with `jupyter kernelspec`.

**Kernels:** `:MoltenInit` lists *registered Jupyter kernels*, not venvs — a venv must be registered as a kernel before it appears. The `jkernel` helper (`~/.local/bin/jkernel`) does this: `jkernel add` registers the current directory's venv (prompts for a name), `jkernel rm` removes one, `jkernel list` lists them. It uses the Neovim host's `jupyter` so the list matches what Molten sees. Full workflow in [`docs/molten.md`](docs/molten.md).

**Images / terminal:** inline image output (plots) only works in terminals speaking the Kitty graphics protocol (Kitty/WezTerm/Ghostty). `lua/plugins/molten.lua` detects the terminal at startup: in a capable terminal it uses `image.nvim` (loaded via `cond`); otherwise (e.g. **Alacritty**, the current terminal) it sets `molten_image_provider = "none"` and relies on virtual-text output. View plots externally with `<leader>oi` (`:MoltenImagePopup`) or `<localleader>mx` (`:MoltenOpenInBrowser`).

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

`<leader>?` opens a live searchable list of all maps (Telescope). `<leader>k` opens a hand-curated cheatsheet floating window defined in `lua/defaults/cheatsheet.lua` — keep its `sections` table in sync when you add/change keymaps.

| Key | Action |
|-----|--------|
| `<leader>ff` | Telescope find files |
| `<leader>?` | Search all keymaps (Telescope) |
| `<leader>k` | Keybindings cheatsheet (floating window) |
| `<leader>cs` | Pick colorscheme (live preview, persisted) |
| `<leader>n` | Toggle Neo-tree |
| `<leader>t` | Toggle vertical terminal (size 80) |
| `<leader>ac` | Toggle ClaudeCode |
| `<leader>z` | Toggle Zen Mode |
| `<leader>d` | Show diagnostic float |
| `<leader>mi` | Molten init kernel |
| `<leader>e` | Molten evaluate operator |
| `<leader>r` (visual) | Molten evaluate selection |
| `<leader>rc` | Molten run current cell (auto-selects the ```` ```python ```` fence) |
| `<leader>ra` | Molten run all cells |
| `<leader>rk` / `<leader>rj` | Molten run cells above / current cell and below |
| `<leader>rr` | Molten re-evaluate cell |
| `<leader>os` | Molten open output window |
| `<leader>oh` | Molten hide output |
| `<leader>md` | Molten delete cell |
| `<localleader>mx` | Molten open output in browser |
| `<leader>oi` | Molten open image output externally |
| `<Tab>` / `<S-Tab>` | Next / previous buffer (bufferline) |
| `<leader>x` | Close buffer |
| `gd` / `K` / `gr` / `<leader>rn` | LSP definition / hover / references / rename |
| `<C-h/j/k/l>` | Move between windows |

## External dependencies

- `lazygit` binary (for lazygit.nvim)
- `make` (for telescope-fzf-native)
- `~/.virtualenvs/neovim` venv with `pynvim`, `jupyter_client`, `jupytext` (Neovim Python host / Molten / jupytext.nvim)
- `~/.local/bin/jkernel` helper script for registering/removing per-project Jupyter kernels (see [`docs/molten.md`](docs/molten.md)). Not part of this repo — lives in `~/.local/bin`.
- A Kitty-graphics terminal (Kitty/WezTerm/Ghostty) is only needed for inline Molten images; Alacritty works for everything else
