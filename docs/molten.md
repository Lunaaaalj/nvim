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
   - `<leader>os` — open the output pane (see below)
   - `<leader>ot` / `<leader>oh` — toggle / close the pane
   - `<leader>md` — delete the cell

## Output pane

Output does not appear in a floating window. It goes to a docked pane in the
right-hand column — stacked *above* the REPL terminal when one is open
(`<leader>tR` / `<leader>tp`), so the layout reads like RStudio:

```
┌──────────────────────┬───────────┐
│                      │ ─ output ─│
│   report.qmd         │  <plot>   │
│                      │ mean:4.21 │
│                      ├───────────┤
│                      │ R REPL    │
└──────────────────────┴───────────┘
```

| Key | Action |
|-----|--------|
| `<leader>os` | Open the pane and focus it (refreshes to the current cell) |
| `<leader>ot` | Toggle the pane |
| `<leader>oh` | Close the pane |

The pane refreshes itself after every evaluation — `<leader>rc`, `<leader>ra`,
`<leader>rk`, `<leader>rj`, `<leader>rr` and visual `<leader>r` all update it.

Text results still appear inline under the cell as virtual text; plots do not
(`molten_image_location = "float"`), so figures show up only in the pane
instead of pushing your code around.

Opening a REPL terminal (`<leader>tR` / `<leader>tp` / `<leader>tN`) while the
pane is up moves it *under* the pane rather than adding a third column, so the
layout above holds whichever you open first. `<leader>th` (horizontal panel)
and `<leader>tf` (float) are left where you asked for them.

The pane itself is transparent like every other window, so it picks up your
terminal's colour and opacity. Plots get a solid **white** background baked
into the image instead — otherwise matplotlib's transparent PNGs composite
straight onto the terminal background and the axes are unreadable. To change
it, set `require("defaults.molten_pane").plot_background` (any ImageMagick
colour, e.g. `"#eeeeee"`); to give the pane a surface of its own, override the
`MoltenPaneNormal` highlight group.

### How it works

Implemented in `lua/defaults/molten_pane.lua`. Two things about Molten shape it:

- **Text.** Molten only builds a cell's output buffer while it renders its
  float. So a refresh runs `MoltenShowOutput`, copies the buffer Molten built,
  and runs `MoltenHideOutput` — all inside a single callback. Neovim doesn't
  redraw in between, so the float is never actually visible.
- **Plots.** Molten writes each figure to a temp PNG and binds the image to the
  *float's* window (`add_image(..., bufnr, winnr)`). That binding is why the
  plots don't follow the buffer into another window. The pane asks image.nvim
  for those image objects, takes their `.path`, and renders its own copies
  bound to the pane's window — which is the "show the figure file in the output
  buffer" approach. Each PNG is first flattened onto the background colour with
  ImageMagick (`magick … -alpha remove`), cached under
  `stdpath("cache")/molten_pane/`. ImageMagick is already required by
  image.nvim's default processor, so this adds no new dependency; without it
  the plot simply renders untouched.
- **Size.** image.nvim's `max_width`/`max_height` are *global* options — there
  is no per-image version — so every pane plot was being capped at the
  `max_height = 12` set for inline output. The pane opts out
  (`ignore_global_max_size`) and computes explicit cell dimensions from the
  terminal's cell size, scaling the figure to fill the pane in whichever
  direction runs out first.

Because output arrives asynchronously, a refresh after a run polls on Molten's
own status header (`On Hold` / `Running` → `Done` / `Failed`) every 500ms and
stops the moment the cell settles. That polling is the only repeating work, and
it only runs while a cell is actually pending (hard cap: 2 minutes).

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
