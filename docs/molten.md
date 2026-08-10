# Molten workflow

How to run code in Jupyter kernels from Neovim with
[`molten-nvim`](https://github.com/benlubas/molten-nvim). Covers the one
concept that trips people up — **kernels vs. venvs** — plus the day-to-day flow
and the `jkernel` helper.

## The key idea: kernels, not venvs

`:MoltenInit` does **not** browse for virtual environments. It lists the
**Jupyter kernels** that are registered on your machine. A venv is *not*
automatically a kernel — you register it once, and from then on it appears in
the `:MoltenInit` picker.

So the model is:

```
project venv  --(register once)-->  Jupyter kernel  --(:MoltenInit)-->  Molten
```

Molten reads the kernel list through `jupyter_client` (in the Neovim host venv
`~/.virtualenvs/neovim`), so anything `jupyter kernelspec list` shows, Molten
sees too.

## Registering a venv as a kernel

Use the `jkernel` helper (`~/.local/bin/jkernel`, already on `PATH`).

```bash
cd /path/to/project
source .venv/bin/activate     # or just have .venv/ , venv/ , or env/ present
jkernel add
```

`jkernel add`:

1. Finds the venv — an activated `$VIRTUAL_ENV` first, else `.venv/`, `venv/`,
   or `env/` in the current directory.
2. Prompts for a **kernel name** (defaults to the folder name) and a display
   name.
3. Installs `ipykernel` into the venv if it's missing.
4. Registers the kernel under `~/Library/Jupyter/kernels/`.

After that the name shows up in `:MoltenInit`. This is a **one-time** step per
project — the kernelspec just stores the absolute path to that venv's Python, so
everything you `pip install` in the venv is available when you run cells.

### Doing it manually (no helper)

```bash
source .venv/bin/activate
pip install ipykernel
python -m ipykernel install --user --name my-project --display-name "My Project"
```

## Managing kernels with `jkernel`

| Command | What it does |
|---------|--------------|
| `jkernel add` | Register the current directory's venv (prompts for name) |
| `jkernel rm` | Remove a kernel — interactive numbered picker |
| `jkernel rm <name>` | Remove a kernel by name directly |
| `jkernel list` | List registered kernels |

Notes:

- `jkernel` uses the Neovim host's `jupyter` (`~/.virtualenvs/neovim/bin/jupyter`)
  so its list always matches what Molten sees. Override with
  `NVIM_JUPYTER=/path/to/jupyter jkernel ...`.
- The `Native kernel (python3) is not available` warning from
  `jupyter kernelspec list` is harmless — the host venv has no kernel of its own.

## Daily flow

1. Open your `.ipynb` or `.py` in Neovim. (`.ipynb` is converted to markdown on
   the fly by `jupytext.nvim`.)
2. `<leader>mi` → `:MoltenInit`, then pick the kernel for this project.
3. Evaluate code:
   - **`<leader>rc` — run the whole cell the cursor is in** (the fast path: it
     auto-selects the enclosing ```` ```python ```` fence and evaluates it)
   - `<leader>rr` — re-evaluate the current cell
   - `<leader>r` — evaluate an arbitrary visual selection
   - `<leader>e` — evaluate operator (e.g. `<leader>e` then a motion)

   Bulk execution (like VSCode's run-all / run-above / run-below):
   - `<leader>ra` — run **all** cells, top to bottom
   - `<leader>rk` — run every cell **above** the current one (`k` = up)
   - `<leader>rj` — run the current cell **and everything below** (`j` = down)

   These evaluate each ```` ```python ```` cell in order. The kernel queues the
   evaluations, so they run sequentially and outputs land in the right cells —
   even though all the requests are fired at once. If the cursor is between
   cells (in prose), the split falls on the cursor line: `rk` runs cells fully
   above it, `rj` runs cells at or below it.
4. Manage output:
   - `<leader>os` — open the output window
   - `<leader>oh` — hide output
   - `<leader>md` — delete the cell

Cells without inline images show their results as virtual text in Alacritty.

## Plots / images

Inline images only work in terminals that speak the Kitty graphics protocol
(Kitty / WezTerm / Ghostty). `lua/plugins/molten.lua` detects the terminal at
startup:

- **Capable terminal** → uses `image.nvim`, plots render inline.
- **Alacritty** (the usual setup here) → `molten_image_provider = "none"`,
  output is virtual text. View plots externally:
  - `<leader>oi` — `:MoltenImagePopup` (external image viewer)
  - `<localleader>mx` — `:MoltenOpenInBrowser`

## R / Quarto

`.qmd` (Quarto) documents get two things, from two different plugins:

- **LSP-in-chunks** — `quarto-nvim` + `otter.nvim` (`lua/plugins/quarto.lua`)
  give you diagnostics/completion/hover *per language* inside each chunk
  (an `{r}` chunk gets R's LSP, a `{python}` chunk gets Python's). This is
  editing support only — it does not run anything.
- **Execution** — still goes through Molten, exactly like `.ipynb`/`.py`.
  `molten_cells()` in `lua/defaults/keymaps.lua` recognizes both plain
  jupytext fences (```` ```python ````) and Quarto's curly-brace chunk
  headers (```` ```{r} ````, ```` ```{python} ````), so `<leader>rc` /
  `<leader>ra` / `<leader>rk` / `<leader>rj` work unchanged in `.qmd` files.

### Registering R as a kernel

Unlike Python, R has no per-project venv concept here — IRkernel registration
is a **one-time, machine-wide** step, not something `jkernel` handles:

```r
install.packages("IRkernel")
IRkernel::installspec()
```

After that, the R kernel shows up in `<leader>mi` (`:MoltenInit`) alongside
any Python kernels — pick it the same way. `<leader>tR` also opens a plain,
persistent R REPL terminal (same pattern as `<leader>tp`/`<leader>tN`) for
work outside Molten cells.

### Preview

`<leader>op` — `:QuartoPreview`, runs `quarto preview` and opens/refreshes a
browser tab with live reload as you save. `<leader>oP` — `:QuartoClosePreview`
stops it. This renders the whole document (all chunks, any language), unlike
per-cell Molten output.

### Plots

The Alacritty-vs-Kitty-protocol image handling described above is generic —
it applies to R plots exactly like Python ones, no separate mechanism.

## Troubleshooting

- **Kernel not in `:MoltenInit`** — it isn't registered. Run `jkernel add` in the
  project, or check `jkernel list`.
- **`:MoltenInit` errors about remote plugins** — run `:UpdateRemotePlugins` and
  restart Neovim (required after installing/updating molten-nvim).
- **`jupytext` / `pynvim` not found** — the Neovim Python host venv
  `~/.virtualenvs/neovim` is missing deps; it needs `pynvim`, `jupyter_client`,
  `jupytext`. See the Molten section of `CLAUDE.md`.
- **Wrong packages at runtime** — the kernel points at a specific venv. If you
  `pip install`ed into a different environment, install into the venv the kernel
  was registered from (or re-register).
