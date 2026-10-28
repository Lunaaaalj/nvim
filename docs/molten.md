# Molten workflow

How to run code in Jupyter kernels from Neovim with
[`molten-nvim`](https://github.com/benlubas/molten-nvim): picking a kernel,
the day-to-day flow, plots, and R / Quarto.

## Picking a kernel: interpreters, like VS Code

You pick a **Python interpreter or environment**, not a pre-registered Jupyter
kernel. There is no `jkernel add` step. `lua/molten_kernels.lua` sits between
you and `:MoltenInit`:

- **You usually don't pick at all.** The first `<leader>rc` / `<leader>ra` /
  `<leader>e` in a notebook starts a kernel by itself, from the first of
  these that applies:
  1. the interpreter this file used last time;
  2. the one this project used last (the default for new notebooks in it);
  3. the project's only venv (`.venv/`, `venv/`, any dir with a `pyvenv.cfg`
     from the file's folder up to the project root, or a poetry / pipenv env
     named after the project);
  4. for an R-only `.qmd`, the only registered R kernel.

  If it still can't tell, it opens the picker.
- **`<leader>mi` (or `:Kernel`) opens the picker** to switch. It lists the
  active `$VIRTUAL_ENV` / `$CONDA_PREFIX`, project envs (★), `~/.virtualenvs/*`,
  conda envs, pyenv versions, uv-managed Pythons and the system Pythons, then
  every registered kernel (IRkernel, old `jkernel` ones). The current choice is
  marked ●. It also offers **+ Create .venv** (uv if installed, with pip seeded
  so `%pip` works) when the project has none, and **Enter interpreter path…**.
  `:Kernel /path/to/python` (or to an env dir) skips the picker.
- **ipykernel is installed for you.** If the chosen env doesn't have it, you
  get one confirmation, then `uv pip install` (uv + venv) or
  `python -m pip install`. Interpreters that refuse installs (Homebrew, uv's
  own Pythons: PEP 668) offer to create a project `.venv` from them instead.
- **The kernel runs in the notebook's folder**, so relative paths
  (`pd.read_csv("data.csv")`) and local imports behave as in Jupyter or
  VS Code. The env's `bin` is first on the kernel's `PATH`, so `!pip install x`
  and subprocesses use that env.
- The statusline shows the attached kernel.

### How it works

Molten can only start *kernelspecs*. So for the interpreter you pick, the
module writes one to `stdpath("data")/molten/kernels/nvim-<env>-<hash>/`
(one per interpreter + notebook folder) and runs `:MoltenInit` with it. That
directory is put on `$JUPYTER_PATH` before Neovim's Python host starts. The
specs don't touch `~/Library/Jupyter`, so `jupyter kernelspec list`, VS Code
and JupyterLab never see them. Specs whose interpreter is gone, or that went
unused for 30 days, are pruned when the picker opens. Choices are remembered
in `stdpath("state")/molten_kernels.json`.

`<leader>mI` is the raw `:MoltenInit`, which lists registered kernels only.
Use it to attach a *second* kernel to a buffer (e.g. Python and R in one
`.qmd`). Switching with `<leader>mi` replaces the attached kernel instead.

### Registering a kernel by hand (optional)

You only need this for kernels that aren't a Python env, such as R (below),
or to share a kernel with other Jupyter frontends. `jkernel add` (in
`~/.local/bin`) registers the current directory's venv under
`~/Library/Jupyter/kernels/`; `jkernel rm` / `jkernel list` manage them. By
hand:

```bash
.venv/bin/python -m pip install ipykernel
.venv/bin/python -m ipykernel install --user --name my-project --display-name "My Project"
```

## Daily flow

1. Open your `.ipynb` or `.py` in Neovim. (`.ipynb` is converted to markdown on
   the fly by `jupytext.nvim`.)
2. Run a cell (`<leader>rc`). The kernel starts by itself (see above). Use
   `<leader>mi` to switch to another one.
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

   These evaluate each cell in the kernel's language, in order: a
   ```` ```bash ```` example inside a Markdown cell is skipped, not sent to
   the Python kernel. The kernel queues the
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
is a **one-time, machine-wide** step:

```r
install.packages("IRkernel")
IRkernel::installspec()
```

After that, the R kernel shows up in `<leader>mi` after the Python
interpreters, and an R-only `.qmd` picks it by itself. `<leader>tR` also opens a plain,
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

- **"Molten isn't registered"** — run `:UpdateRemotePlugins` and restart
  Neovim (required after installing/updating molten-nvim).
- **An env is missing from the picker** — it is found by looking for a
  `pyvenv.cfg` (venvs), `conda-meta/` (conda) or the usual install dirs. Use
  **Enter interpreter path…** or `:Kernel /path/to/env` for anything else.
- **Installing ipykernel failed** — the error is in the notification. Behind a
  proxy or offline, install it yourself (`.venv/bin/python -m pip install
  ipykernel`) and pick the env again.
- **`jupytext` / `pynvim` not found** — the Neovim Python host venv
  `~/.virtualenvs/neovim` is missing deps. It needs `pynvim`, `jupyter_client`
  and `jupytext`, plus `pillow` for `:MoltenImagePopup`, `nbformat` for
  `:MoltenImportOutput`/`:MoltenExportOutput`, and `cairosvg` for SVG plots:
  `~/.virtualenvs/neovim/bin/pip install pillow nbformat cairosvg`.
- **Wrong packages at runtime** — check the statusline: the kernel runs the
  env shown there. `%pip install x` in a cell installs into that env.
