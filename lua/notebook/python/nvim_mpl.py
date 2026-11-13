# pyright: reportMissingImports=false
"""Matplotlib backend for Python REPLs inside Neovim (lua/notebook/repl.lua).

A Neovim :terminal can't draw kitty graphics, so `plt.show()` saves each open
figure as a PNG and asks the parent Neovim ($NVIM) to show it in its image
split. Under IPython, open figures are also shown after every input, as in a
notebook. Selected with MPLBACKEND=module://nvim_mpl (set for the pinned
REPL only). Colours come from $MATPLOTLIBRC (the plot paper).
"""

import os
import subprocess
import tempfile
import time

from matplotlib._pylab_helpers import Gcf
from matplotlib.backend_bases import FigureManagerBase
from matplotlib.backends.backend_agg import FigureCanvasAgg

FigureCanvas = FigureCanvasAgg
FigureManager = FigureManagerBase

_dir = os.path.join(tempfile.gettempdir(), "nvim-plots")
os.makedirs(_dir, exist_ok=True)


def _notify(path: str) -> None:
    server = os.environ.get("NVIM")
    if not server:
        print(f"plot saved to {path}")
        return
    expr = f"v:lua.require'notebook.plots'.show_file('{path}')"
    subprocess.Popen(
        [os.environ.get("NVIM_PROG", "nvim"), "--server", server, "--remote-expr", expr],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def show(*args, **kwargs):
    for manager in Gcf.get_all_fig_managers():
        path = os.path.join(_dir, f"plot-{os.getpid()}-{time.time_ns()}.png")
        manager.canvas.figure.savefig(path)
        _notify(path)
    Gcf.destroy_all()


def _register_ipython() -> None:
    try:
        from IPython import get_ipython
    except ImportError:
        return
    ip = get_ipython()
    if ip is None:
        return

    def after(*_):
        if Gcf.get_all_fig_managers():
            show()

    ip.events.register("post_run_cell", after)


_register_ipython()
