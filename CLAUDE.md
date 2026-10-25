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
The last used colorscheme is persisted to `stdpath("state")/colorscheme` (machine-local, **not** in the repo — `.colorscheme` is gitignored and only read once as a legacy migration) and restored on startup via `lua/defaults/init.lua`. Any `:colorscheme` call triggers an autocmd that writes the name to that file. The startup load is wrapped in `pcall` and falls back to `kanso`, so a missing/uninstalled scheme never aborts startup. `<leader>cs` opens Telescope with live colorscheme preview.

Installed schemes (one file each under `lua/plugins/`): catppuccin, kanagawa, kanso, lackluster, nightfox, everforest, melange, gruvbox-material, zenbones (+ its variants forestbones/neobones/kanagawabones/seoulbones). Warm set: rose-pine (`name = "rose-pine"`), kanagawa-paper, bamboo, flexoki (`name = "flexoki"`; no transparency option, relies on the strip autocmd), evergarden, vesper (dark only). **evergarden sets `'background'` from its variant**, so its spec chooses the variant (`fall`/`summer`) from `vim.o.background`; bamboo's colors file resets its modules on every load, but its options live in `vim.g.bamboo_config` so they survive. The palette leans earthy (grays/greens/browns), minimalist, with dark and light variants.

**Transparency:** by default every colorscheme renders with no editor background so the Alacritty background shows through. This is enforced two ways, both gated on `vim.g.ui_transparent`: native `transparent` options are set per-plugin where supported (each theme spec passes `vim.g.ui_transparent`, never a literal `true` — keep that when adding a theme), and a global `ColorScheme` autocmd in `lua/defaults/init.lua` (`transparent_groups`) strips the bg of core groups after any scheme loads — covering schemes without a transparency option (e.g. melange) — and returns early in solid mode. Add new groups to that list if a plugin leaves a background.

**Toggles (`lua/defaults/ui_toggle.lua`):** `<leader>ub` / `:ToggleTransparency` flips transparent ↔ solid, `<leader>uB` / `:ToggleBackground` flips `'background'` dark ↔ light. State persists to `stdpath("state")/ui.json` and `restore()` runs **before** `require("defaults.lazy")` because the theme specs read the flag in `setup()`. A toggle finds the active theme's lazy plugin by locating `colors/<name>.{lua,vim}` on the runtimepath (no hand-kept name→plugin table), re-runs its `init`/`config` (nightfox/catppuccin hash options and recompile on change), and reloads the scheme. Going light while transparent forces solid (light text over the dark terminal is unreadable) and going dark restores it; `toggle_background()` clears `g:colors_name` before setting `'background'` (otherwise Neovim auto-reloads the scheme with its *old* config, which variant-driven schemes like evergarden flip straight back), and a scheme with no variant for the target — pins `'background'` back (nightfox, lackluster) or ignores it and keeps drawing dark (vesper; detected by `Normal` bg/fg luminance) — is undone completely, `'background'` included, with a warning. Inside Alacritty (`$ALACRITTY_SOCKET`), solid mode sets `window.opacity=1` live via `alacritty msg config`, and transparent mode / `VimLeavePre` run `--reset` to restore `alacritty.toml`'s value.

**UI chrome (`lua/defaults/options.lua`):** a few options keep the UI clean against the transparent background. `fillchars` blanks the end-of-buffer `~` and uses a thin `│` window separator. The `cursorline` is owned by `lua/defaults/cursorline.lua` (required from `defaults/init.lua` *after* the strip autocmd so its `ColorScheme` handler runs second): it is on only in the focused regular-file window and explicitly **off** in terminals, floats (Zen), and `skip_ft` filetypes, because window-local options are copied into new windows; neo-tree is `unmanaged_ft` (its cursorline is the selection marker); `w:no_cursorline` opts a window out. In transparent mode the default style is number-only (accent bold `CursorLineNr` from the scheme's `Function` fg, `cursorlineopt=number`); `<leader>uc` cycles number → underline (single-colour `sp`) → band (blended tint). Highlights use `nvim_set_hl` (replace, not merge). Solid mode leaves the scheme's own cursorline band alone. Accent/blend helpers live in `lua/defaults/colors.lua` — reuse them for any theme-derived accent instead of hardcoding colours. `pumblend`/`winblend` give the popup menu and floats slight transparency. Diagnostics use icon signs (via `vim.diagnostic.config`) instead of the default `E`/`W`/`I`/`H` letters.

### Aesthetics & ambience
A layer of plugins exists purely for a pleasant feel (one file each under `lua/plugins/`):
- **`snacks.lua`** — enables the snacks `dashboard` and `scroll` modules (snacks itself comes in via `claudecode.nvim`). The dashboard is a **minimal single column**, everything centered, and **transparent** — its `SnacksDashboardNormal` group is in the `transparent_groups` list in `lua/defaults/init.lua`. Sections: header art (read verbatim from `dashboard-header.txt` in the config root if it exists, else a built-in Python snake; `dashboard.width` = the art's widest line, floor 60), a **live clock** + date, a **GitHub stats line** (open PRs · issues · contributions · streak), and a **one-line key hint**. The `keys` table drives both the hint (entries with `hint`) and the bindings (every entry as a `hidden = true` item), so g/n/p/l/m stay bound without rows — add keys there, not as separate sections. The clock is a uv timer aligned to the minute that only runs while a `snacks_dashboard` window is visible (started on `SnacksDashboardOpened`/`BufEnter`, stopped on leave). Colors are `DashboardMuted` (Comment fg) plus one `DashboardAccent` (scheme `Function` fg via `lua/defaults/colors.lua`), re-applied on `ColorScheme` — no hardcoded palette.
- **`lua/defaults/dashboard_data.lua`** — the async/cached data layer behind the stats line. **One** `gh api graphql` request (authenticated `viewer`, no hardcoded username) returns the contribution calendar plus `search { issueCount }` for open PRs and issues — exact counts, unlike `gh search … -q length`, which is capped at gh's default limit of 30. The streak is computed from the calendar's `date`s against the local date (today may be empty; days after today are ignored). The result is written to `stdpath('cache')/dashboard/stats.json` with a 30-min TTL; the section reads the cache instantly (never blocking startup) and a debounced `Snacks.dashboard.update()` refreshes when the fetch returns. `setup({ issues = "assignee" | "author" })` picks which issues count (default: assigned; the cache is keyed on it). No `gh`/not authed → no cache → the line is hidden.
- **Fades vs. transparency:** a terminal cell is either a solid colour or the terminal bg, so anything that fades over a transparent editor needs to be told what colour is behind it. That colour is `require("defaults.colors").terminal_bg` (Alacritty's default `#181818`; `alacritty.toml` sets none) — used by **`smear_cursor.lua`** (`transparent_bg_fallback_color`; also stiffer than default) and **`tiny-glimmer.lua`** (flash on yank, `transparency_color`; only yank is on, so `p`/`n`/`u` aren't hijacked). Prefer motion over opacity for new animations: nvim-notify uses `slide`, not `fade`. snacks.scroll is 140ms outQuad (50ms for held-key repeats); mini.indentscope's guide grows out over 80ms.
- **`colorizer.lua`**, **`rainbow-delimiters.lua`**, **`tiny-devicons.lua`**, **`satellite.lua`** (scrollbar with git/diagnostic/search marks), **`illuminate.lua`** (word-under-cursor), **`precognition.lua`** (motion hints), **`cellular-automaton.lua`** (fun screensaver), **`typr.lua`** (typing practice + stats, via `nvzone/volt`).

When adding cursor/scroll-animating plugins, check this list first — multiple plugins animating the same thing will conflict.

### LSP
Two-layer setup:
- `lua/plugins/mason.lua` ensures the servers are installed via mason-lspconfig (`clangd`, `pyright`, `ruff`, `ts_ls`, `html`, `cssls`, `emmet_language_server`, `texlab`, `lua_ls`) and configures them through Neovim 0.11's native API: shared cmp capabilities go on `vim.lsp.config("*")`, per-server overrides (capabilities/settings/filetypes/on_attach) live in the `servers` table and are applied with `vim.lsp.config(name, opts)`, and mason-lspconfig v2's `automatic_enable` calls `vim.lsp.enable` for each installed server (v2 has no `handlers` option — don't reintroduce one, and register configs *before* `mason-lspconfig.setup()`) — `clangd` pins utf-16 offset encoding, `pyright` defers import-organizing to `ruff`, `ruff` drops its hover so it doesn't duplicate pyright. The same file also registers **mason-tool-installer** to guarantee the non-LSP tools conform/dap call by name (`black`, `isort`, `stylua`, `clang-format`, `latexindent`, `prettier`, `codelldb`, `debugpy`).
- `lua/defaults/lsp.lua` is a single global `LspAttach` autocmd that binds buffer-local keymaps (`gd`/`gD`/`gr`/`gi`/`gy`/`<leader>rn`/`<leader>ca`/`[d`/`]d`) for **any** attached server, and enables inlay hints (toggle `<leader>uh`) when the server supports them. It is `require`d from `lua/defaults/init.lua`. Do not add per-server `on_attach` keymaps — extend this autocmd instead. `K` is deliberately **not** bound there: its single owner is `lua/plugins/ufo.lua` (peek fold → hover.nvim, which includes the LSP provider), and a buffer-local map would shadow it.

`lua/plugins/lsp.lua` just pulls in `nvim-lspconfig`. Add new LSP servers to `ensure_installed` (and `servers` for overrides) in `mason.lua`.

A `.luarc.json` at the config root configures lua_ls for this repo: it declares `vim` and `Snacks` as globals so editing the config produces no spurious "undefined global" warnings (LuaJIT runtime, third-party checks off). Add to its `diagnostics.globals` if another runtime global trips lua_ls.

### Buffer-centric quitting
`lua/defaults/bufclose.lua` (required from `keymaps.lua`) makes `:q` close the **buffer**, not Neovim. It is wired as a command-line `<CR>` `expr` mapping that rewrites a whole-line `q` / `q!` / `wq` / `wq!` to `:BufQuit[!]` / `:BufWriteQuit[!]` — **not** `:cabbrev`: a `q` abbreviation doesn't expand when `!` follows, and a `q!` abbreviation never matches, so `:q!` would still exit. `:quit`, `:qa`, searches and `<cmd>q<cr>` inside mappings are untouched. In a split / float / neo-tree / multi-tab, BufQuit is a plain `:quit`; in the last editing window (floats and neo-tree don't count) it switches to the next listed buffer (files before terminals, then MRU) or opens the dashboard **in that window** (`Snacks.dashboard.open({ buf, win })` — without `win` snacks opens a float), and `:q` on that dashboard runs `:qall`. Terminal/unlisted buffers are only hidden (jobs survive); modified buffers prompt Save/Discard/Cancel. `<leader>x` calls the same `close_buffer()`.

### Claude chats in buffers
`lua/claude_chats/` (not a lazy spec — a plain module) runs `claude` in ordinary terminal buffers, any number at once, as an alternative to claudecode.nvim's single split. Each buffer gets the same env claudecode gives its own terminal (`ENABLE_IDE_INTEGRATION`, `CLAUDE_CODE_SSE_PORT` from `claudecode.server.init`'s port, loopback `no_proxy`), so IDE features keep working. New chats are spawned with a pre-generated `--session-id` and tagged `b:claude_chat`, which is how running buffers are matched to their session logs. Past sessions are read from `~/.claude/projects/<cwd with non-alnum → "-">/*.jsonl`; titles come from `custom-title` > `ai-title` > `last-prompt` lines (tail of file, cached by mtime). `claude_chats/neotree/` is a custom neo-tree source (`name = "claude"`) registered in `sources` in `lua/plugins/neo-tree.lua` (its tab icon/name, like every source's, lives in `lua/neotree_tabs.lua` — the selector shows icons only and bufferline's neo-tree offset shows the active source's name, both from that one table; keep glyphs as BMP `\u{}` escapes); its commands module overrides neo-tree's filesystem-mutating commands because chat nodes carry the `.jsonl` as `path` (stock `delete` would remove the log).

### Terminals
`lua/terminals/` (a plain module, like `claude_chats`) owns terminal sessions; `lua/plugins/toggleterm.lua` only draws the windows and forwards toggleterm's `on_create`/`on_open`/`on_exit` to it, then calls `require("terminals").setup()`. **Ids are partitioned:** shells 1–99 (`new()` takes the first free id), the pinned REPLs 100+ (`M.repls`) — toggleterm hands out the lowest free id from one pool, so never create a terminal without an explicit id. Per-terminal state (`info(id)`: custom name, cwd, running command, last command, exit, output rows, unseen) is fed by **zsh prompt hooks**: shells get `ZDOTDIR=shell/zsh` (+ the real one in `NVIM_TERM_ZDOTDIR`), whose `.zshenv` restores the user's ZDOTDIR, sources their files unchanged, and (interactive only — toggleterm runs `zsh -c "zsh;#toggleterm#N"`, so the outer non-interactive zsh must keep pointing at the wrapper) emits OSC `633;E;<cmd>`, `133;C`, `133;D;<status>` and `7`, read through the `TermRequest` autocmd. The cursor rows at C/D are the first output row and the row after the output (1-indexed), which `quickfix()` uses (with a `%D` line in the errorformat so paths resolve against the shell's cwd). "Last used" is set only by `on_open`/`TermEnter`, **not** `BufEnter` (toggleterm moves focus through other terminal windows while closing). State changes fire a debounced `User TermsChanged`, consumed by the winbar (`winbar_label`, toggleterm's per-terminal `name_formatter`) and the neo-tree source `terminals/neotree/` (`name = "terminals"`, tab in `lua/neotree_tabs.lua`). Python paste: 3.13+ (pyrepl) gets bracketed paste and a **separately delayed** second Enter (pyrepl reads a fast burst as more paste); older REPLs get blank lines stripped. Sessions: `persistence.lua` stores `session_state()` as JSON in `g:Session_terminals` and `session_restore()` re-spawns them.

### Molten / notebooks
`molten.nvim` runs code in Jupyter kernels and `jupytext.nvim` handles `.ipynb` ↔ markdown conversion. Requires `:UpdateRemotePlugins` after install.

**Python host:** Neovim's Python provider points at a dedicated venv `~/.virtualenvs/neovim` (set via `vim.g.python3_host_prog` in `lua/defaults/init.lua`) that holds `pynvim`, `jupyter_client`, and `jupytext`. Homebrew's python3 is PEP-668 externally-managed, so deps aren't installed there. That venv's `bin` is prepended to `PATH` so `jupytext.nvim` (which calls a bare `jupytext`) resolves. Notebook kernels are separate per-project venvs registered with `jupyter kernelspec`.

**Kernels:** `:MoltenInit` lists *registered Jupyter kernels*, not venvs — a venv must be registered as a kernel before it appears. The `jkernel` helper (`~/.local/bin/jkernel`) does this: `jkernel add` registers the current directory's venv (prompts for a name), `jkernel rm` removes one, `jkernel list` lists them. It uses the Neovim host's `jupyter` so the list matches what Molten sees. Full workflow in [`docs/molten.md`](docs/molten.md).

**Images / terminal:** inline image output (plots) only works in terminals speaking the Kitty graphics protocol (Kitty/WezTerm/Ghostty). `lua/plugins/molten.lua` detects the terminal at startup: in a capable terminal it uses `image.nvim` (loaded via `cond`); otherwise (e.g. **Alacritty**, the current terminal) it sets `molten_image_provider = "none"` and relies on virtual-text output. View plots externally with `<leader>oi` (`:MoltenImagePopup`) or `<localleader>mx` (`:MoltenOpenInBrowser`).

**Quarto / R:** `.qmd` files get per-language LSP-in-chunks via `quarto-nvim` + `otter.nvim` (`lua/plugins/quarto.lua`, `ft = "quarto"`, `codeRunner.enabled = false`); `.qmd` is registered as filetype `quarto` defensively in `lua/defaults/init.lua`. Execution does **not** go through quarto-nvim's own runner — it reuses Molten exactly like Python: register R as a Jupyter kernel via IRkernel (`install.packages("IRkernel"); IRkernel::installspec()`, a one-time machine-wide step, unlike per-project `jkernel` venvs), then pick it from `<leader>mi`. `molten_cells()` in `lua/defaults/keymaps.lua` matches both plain jupytext fences (` ```python `) and Quarto's curly-brace chunk headers (` ```{r} `, ` ```{python} `), so `<leader>rc`/`ra`/`rk`/`rj` work unchanged in `.qmd`. `<leader>tR` opens a persistent R REPL terminal (same `named_term` pattern as `<leader>tp`/`<leader>tN`). `<leader>op`/`<leader>oP` (`:QuartoPreview`/`:QuartoClosePreview`) run a live-reload document preview in a browser. Full workflow in [`docs/molten.md`](docs/molten.md#r--quarto).

### LaTeX
Four layers, all of which hang off VimTeX initialising correctly:
- **`lua/plugins/vimtex.lua`** — VimTeX itself, `lazy = false` (its ftplugin must register before the first `.tex` buffer). **Pinned to `tag = "v2.18"`**: VimTeX HEAD raised its floor to Neovim 0.12.4 on 2026-07-22, and on an older Neovim the version gate `finish`es `ftplugin/tex.vim` *before* `vimtex#init()` — killing every mapping, the latexmk compiler, and `vimtex#syntax#in_mathzone()`. Drop the pin once Neovim is 0.12.4+.
- **Viewer: Skim** (`vimtex_view_method = "skim"`, sync/activate/reading-bar on). Not sioyek — sioyek ships unsigned, so Gatekeeper kills it, and Homebrew deprecated the cask (disabled 2026-09-01). VimTeX drives Skim over AppleScript/JXA, so macOS may prompt for automation permission on first use.
- **LSP/format** — `texlab` (mason `ensure_installed`) and `latexindent` for `tex` in conform.
- **Snippets** — `lua/snippets/tex.lua`, a Castel-style set loaded by LuaSnip's `from_lua` loader. Math-mode autosnippets gate on `vimtex#syntax#in_mathzone()`, so **they die silently whenever VimTeX fails to init** — check VimTeX first if snippets stop firing.

Treesitter highlighting is deliberately `disable`d for `latex` (`lua/plugins/treesitter.lua`) so VimTeX owns syntax + conceal; the parser stays installed for folding/textobjects/context.

Debugging tip: VimTeX starts viewers **detached**, so viewer failures are invisible inside Neovim (`<leader>lv` just does nothing). Run `<leader>li` (`:VimtexInfo`) and reproduce the printed viewer command in a shell, where stderr is visible.

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
| `<leader>ub` / `<leader>uB` | Toggle transparent ↔ solid background / dark ↔ light (persisted) |
| `<leader>uc` | Cycle cursorline style: number / underline / band |
| `<leader>n` | Toggle Neo-tree |
| `<C-\>` / `<leader>tt` | Toggle last used terminal (`2<C-\>` = shell #2; no bare `<leader>t`, it's a prefix) |
| `<leader>tn` / `<leader>t.` / `<leader>tg` | New shell in cwd / file's dir / project root |
| `<leader>ts` / `<leader>te` | Terminal picker (Telescope, scrollback preview) / neo-tree Terminals tab |
| `<leader>tf` / `<leader>th` | Current terminal as float / bottom panel |
| `<leader>tl` | Send line / visual selection to the last used terminal |
| `<leader>tr` / `<leader>tq` | Re-run last command / last output → quickfix |
| `<leader>tk` / `<leader>tm` | Kill / rename current terminal |
| `<leader>tp` / `<leader>tN` / `<leader>tR` | Python / Node / R REPL terminal |
| `<leader>ac` | Toggle ClaudeCode |
| `<leader>an` / `<leader>aR` / `<leader>al` | New / resume Claude chat in a buffer / chat list (neo-tree Claude tab) |
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
| `<leader>op` / `<leader>oP` | Quarto: start / stop live-reload preview |
| `<leader>ll` / `<leader>lo` | LaTeX: compile continuous / once |
| `<leader>lv` / `<leader>lk` | LaTeX: view PDF / stop compile |
| `<leader>lc` / `<leader>lC` | LaTeX: clean aux / aux + PDF |
| `<leader>le` / `<leader>lt` | LaTeX: error list / table of contents |
| `<leader>li` | LaTeX: project info (first stop when debugging) |
| `<Tab>` / `<S-Tab>` | Next / previous buffer (bufferline) |
| `<leader>x` / `:q` | Close buffer, keep the window (next buffer, else dashboard; `:q` on the dashboard quits) |
| `<leader>qq` | Quit Neovim (`<leader>q` is the persistence session group, so not bound alone) |
| `gd` / `gD` / `gr` / `gi` / `gy` | LSP definition / declaration / references / implementation / type def |
| `K` | Peek fold, else hover docs (ufo → hover.nvim) |
| `<leader>rn` / `<leader>ca` | LSP rename / code action |
| `[d` / `]d` | Previous / next diagnostic |
| `<leader>uh` / `<leader>uf` / `<leader>us` | Toggle inlay hints / format-on-save / spell-check |
| `af`/`if`, `ac`/`ic`, `aa`/`ia` | Treesitter text objects: function / class / parameter |
| `<leader>db` / `<leader>dc` / `<leader>du` | DAP breakpoint / continue / toggle UI (Python + C/C++) |
| `<C-h/j/k/l>` | Move between windows |
| `<leader>up` | Toggle precognition motion hints |
| `<leader>fml` | Make it rain (cellular-automaton, fun) |
| `<leader>ty` / `<leader>tY` | Typing practice / stats (typr) |

## External dependencies

- `lazygit` binary (for lazygit.nvim)
- `gh` CLI, authenticated (`gh auth login`) — optional; powers the dashboard's GitHub stats line (PRs, issues, contributions, streak). Without it the line simply doesn't render.
- `make` (for telescope-fzf-native)
- An `nvim()` zsh wrapper in `~/.zshrc` (not in this repo) — optional; sets `$NVIM_CWD_FILE` so `lua/defaults/shell_cwd.lua` can write Neovim's final cwd on exit and the shell `cd`s there (cd-on-quit, e.g. after the dashboard's `d` directory picker). The module unsets the var so `:terminal` shells don't inherit it.
- `~/.virtualenvs/neovim` venv with `pynvim`, `jupyter_client`, `jupytext` (Neovim Python host / Molten / jupytext.nvim)
- `~/.local/bin/jkernel` helper script for registering/removing per-project Jupyter kernels (see [`docs/molten.md`](docs/molten.md)). Not part of this repo — lives in `~/.local/bin`.
- A Kitty-graphics terminal (Kitty/WezTerm/Ghostty) is only needed for inline Molten images; Alacritty works for everything else
- `r` and `quarto` (both via Homebrew: `brew install r quarto`) for R/Quarto (`.qmd`) support
- R package `languageserver` for the `r_language_server` LSP (Mason's `r-languageserver` installs its own bootstrapped R environment, so a system-wide `install.packages("languageserver")` isn't strictly required, but is a fallback if Mason's bootstrap fails)
- R package `IRkernel` (`install.packages("IRkernel"); IRkernel::installspec()`) registers R as a Jupyter kernel for Molten — a one-time, machine-wide step, unlike Python's per-project `jkernel` venv registration; `jkernel` itself is Python-venv-specific and does not handle R
