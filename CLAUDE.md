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

**UI chrome (`lua/defaults/options.lua`):** a few options keep the UI clean against the transparent background. `fillchars` blanks the end-of-buffer `~` and uses a thin `│` window separator. The `cursorline` is shown only in the active window (toggled via autocmds) and rendered as a transparent underline — its `CursorLine` background is stripped inside the same `ColorScheme` autocmd as `transparent_groups`, so don't expect a background band. `pumblend`/`winblend` give the popup menu and floats slight transparency. Diagnostics use icon signs (via `vim.diagnostic.config`) instead of the default `E`/`W`/`I`/`H` letters.

### Aesthetics & ambience
A layer of plugins exists purely for a pleasant feel (one file each under `lua/plugins/`):
- **`snacks.lua`** — enables the snacks `dashboard` and `scroll` modules (snacks itself comes in via `claudecode.nvim`). The dashboard is **static** (no animation) and **transparent** — its `SnacksDashboardNormal` group is in the `transparent_groups` list in `lua/defaults/init.lua`. The header art is read verbatim from `dashboard-header.txt` in the config root if that file exists (paste any ASCII art there to swap it), otherwise a built-in Python snake is used. Sections: header, a date/version subtitle, quick-action keys (find/recent/grep/projects/session/config/lazy/mason), **GitHub contribution heatmap**, **GitHub PR/review/issue counts**, **Claude token-usage sparkline**, a **local git summary** (branch + dirty state + recent commits), recent files, and a startup footer.
- **`lua/defaults/dashboard_data.lua`** — the async/cached data layer behind those live sections. It fetches the GitHub contribution calendar + PR/issue counts via `gh` (authenticated `viewer`, no hardcoded username) and Claude per-day token totals via `scripts/claude_usage.py` (pure-stdlib aggregation of `~/.claude/projects/**/*.jsonl`). Results are written to `stdpath('cache')/dashboard/*.json` with a 30-min TTL; sections read the cache instantly (never blocking startup) and a debounced `Snacks.dashboard.update()` refreshes the view when each source returns. Everything degrades gracefully (no `gh`/not authed/no logs → that section renders nothing). The heatmap/sparkline use hardcoded GitHub-green `GhContrib0..4` highlight groups (re-applied on `ColorScheme`) as a deliberate homage.
- **`mini-animate.lua`** — window resize/open/close animations. Its cursor + scroll animations are disabled on purpose (smear_cursor handles the cursor, snacks.scroll handles scrolling) to avoid double-animating.
- **`colorizer.lua`**, **`rainbow-delimiters.lua`**, **`tiny-devicons.lua`**, **`satellite.lua`** (scrollbar with git/diagnostic/search marks), **`illuminate.lua`** (word-under-cursor), **`precognition.lua`** (motion hints), **`cellular-automaton.lua`** (fun screensaver).

When adding cursor/scroll-animating plugins, check this list first — multiple plugins animating the same thing will conflict.

### LSP
Two-layer setup:
- `lua/plugins/mason.lua` ensures the servers are installed via mason-lspconfig (`clangd`, `pyright`, `ruff`, `ts_ls`, `html`, `cssls`, `emmet_language_server`, `texlab`, `lua_ls`) and sets them up through a single `handlers` default function. Per-server overrides (capabilities/settings/filetypes) live in the `servers` table in that file — `clangd` pins utf-16 offset encoding, `pyright` defers import-organizing to `ruff`, `ruff` drops its hover so it doesn't duplicate pyright. The same file also registers **mason-tool-installer** to guarantee the non-LSP tools conform/dap call by name (`black`, `isort`, `stylua`, `clang-format`, `latexindent`, `prettier`, `codelldb`, `debugpy`).
- `lua/defaults/lsp.lua` is a single global `LspAttach` autocmd that binds buffer-local keymaps (`gd`/`gD`/`gr`/`gi`/`gy`/`K`/`<leader>rn`/`<leader>ca`/`[d`/`]d`) for **any** attached server, and enables inlay hints (toggle `<leader>uh`) when the server supports them. It is `require`d from `lua/defaults/init.lua`. Do not add per-server `on_attach` keymaps — extend this autocmd instead.

`lua/plugins/lsp.lua` just pulls in `nvim-lspconfig`. Add new LSP servers to `ensure_installed` (and `servers` for overrides) in `mason.lua`.

A `.luarc.json` at the config root configures lua_ls for this repo: it declares `vim` and `Snacks` as globals so editing the config produces no spurious "undefined global" warnings (LuaJIT runtime, third-party checks off). Add to its `diagnostics.globals` if another runtime global trips lua_ls.

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

The authoritative human-facing reference is the in-editor `:help` documentation under `doc/` (`:help nvim-config`, `:help nvim-keymaps`, `:help nvim-plugins`, `:help nvim-notebooks`). When you add or change a keymap/plugin, update the matching `doc/*.txt` file — tags rebuild automatically on startup when `doc/tags` is absent (see `lua/defaults/init.lua`), or run `:helptags doc` manually.

| Key | Action |
|-----|--------|
| `<leader>ff` | Telescope find files |
| `<leader>?` | Search all keymaps (Telescope) |
| `<leader>k` | Keybindings cheatsheet (floating window) |
| `<leader>w` | Save file |
| `<Esc>` | Clear search highlight |
| `<leader>cs` | Pick colorscheme (live preview, persisted) |
| `<leader>n` | Toggle Neo-tree |
| `<leader>t` | Terminal: toggle shell #1 (vertical side panel) |
| `<leader>tn` / `<leader>ts` | New shell / select-switch shell (`:TermSelect`) |
| `<leader>tf` / `<leader>th` | Float / horizontal terminal |
| `<leader>tp` / `<leader>tN` | Python / Node REPL terminal |
| `2<C-\>` | Open numbered shell #2 (count-prefix `<C-\>` for any id) |
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
| `<leader>x` | Close buffer (preserves window layout) |
| `gd` / `gD` / `gr` / `gi` / `gy` | LSP definition / declaration / references / implementation / type def |
| `K` / `<leader>rn` / `<leader>ca` | LSP hover / rename / code action |
| `[d` / `]d` | Previous / next diagnostic |
| `<leader>uh` / `<leader>uf` / `<leader>us` | Toggle inlay hints / format-on-save / spell-check |
| `af`/`if`, `ac`/`ic`, `aa`/`ia` | Treesitter text objects: function / class / parameter |
| `<leader>db` / `<leader>dc` / `<leader>du` | DAP breakpoint / continue / toggle UI (Python + C/C++) |
| `<C-h/j/k/l>` | Move between windows |
| `<leader>up` | Toggle precognition motion hints |
| `<leader>fml` | Make it rain (cellular-automaton, fun) |

## External dependencies

- `lazygit` binary (for lazygit.nvim)
- `gh` CLI, authenticated (`gh auth login`) — optional; powers the dashboard's GitHub contribution heatmap and PR/issue counts. Without it those sections simply don't render.
- `python3` — also used by `scripts/claude_usage.py` for the dashboard's Claude token-usage sparkline.
- `make` (for telescope-fzf-native)
- `~/.virtualenvs/neovim` venv with `pynvim`, `jupyter_client`, `jupytext` (Neovim Python host / Molten / jupytext.nvim)
- `~/.local/bin/jkernel` helper script for registering/removing per-project Jupyter kernels (see [`docs/molten.md`](docs/molten.md)). Not part of this repo — lives in `~/.local/bin`.
- A Kitty-graphics terminal (Kitty/WezTerm/Ghostty) is only needed for inline Molten images; Alacritty works for everything else
