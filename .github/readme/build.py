# /// script
# requires-python = ">=3.9"
# dependencies = ["fonttools"]
# ///
"""Draws the README's images.

    uv run .github/readme/build.py            # everything
    uv run .github/readme/build.py --schemes  # also re-read colours from nvim

All text is outlined from Maple Mono NF (the kitty font), so the SVGs look the
same in every browser and Nerd Font icons render without the font installed.
Screenshots go in shots/<name>.png (a kitty window, no macOS shadow); each is
framed with an editor-style tab and written to frames/<name>.webp. Missing
shots get a placeholder frame that says what to capture.

Needs: uv, rsvg-convert and cwebp (brew install librsvg webp).
"""

import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
FONT_DIR = Path(os.environ.get("README_FONT_DIR", "~/Library/Fonts")).expanduser()

# The kitty palette (kitty.conf): warm brown glass, everforest inks.
K = {
    "bg": "#261e1c", "bar": "#1c1611", "surface": "#30261d", "line": "#3d3125",
    "fg": "#d3c6aa", "muted": "#a29279", "accent": "#a7c080", "on_accent": "#16181a",
    "yellow": "#dbbc7f", "aqua": "#83c092", "blue": "#7fbbb3", "red": "#e67e80",
    "purple": "#d699b6", "orange": "#e69875",
}
# Same roles for a white GitHub page.
L = {
    "fg": "#3a2f28", "muted": "#6f5f4c", "accent": "#56732f", "on_accent": "#fbf8f2",
    "surface": "#f1ebe1", "line": "#ddd3c3", "blue": "#3f7a72", "yellow": "#8a6a1f",
    "aqua": "#3f7f55",
}


# ── text → paths ──────────────────────────────────────────────────────────────

def num(v):
    s = f"{v:.1f}"
    return s[:-2] if s.endswith(".0") else s


class Face:
    def __init__(self, key, file):
        tt = TTFont(FONT_DIR / file)
        self.key = key
        self.gs = tt.getGlyphSet()
        self.cmap = tt.getBestCmap()
        self.upm = tt["head"].unitsPerEm

    def glyph(self, ch):
        """Id of `ch`'s outline in the current document's <defs> (None for blanks)."""
        gid = f"{self.key[0]}{ord(ch):x}"
        if gid not in DEFS:
            name = self.cmap.get(ord(ch)) or self.cmap[ord("?")]
            pen = SVGPathPen(self.gs, ntos=lambda v: str(round(v)))
            self.gs[name].draw(pen)
            DEFS[gid] = pen.getCommands()
        return gid if DEFS[gid] else None


DEFS = {}  # glyph id → path data, collected per document and emitted by svg()


FACES = {}


def face(w):
    if w not in FACES:
        FACES[w] = Face(w, {"light": "MapleMono-NF-Light.ttf", "bold": "MapleMono-NF-Bold.ttf",
                         "italic": "MapleMono-NF-LightItalic.ttf",
                         "medium": "MapleMono-NF-Medium.ttf"}[w])
    return FACES[w]


def width(text, size):
    return len(text) * 0.6 * size  # Maple Mono: 600/1000, icons included


def paint(fill):
    """`fill` is a colour, or `.class` for theme-aware SVGs."""
    return f'class="{fill[1:]}"' if fill.startswith(".") else f'fill="{fill}"'


def text(s, x, y, size, fill, w="light", anchor="start", opacity=None):
    if anchor == "middle":
        x -= width(s, size) / 2
    elif anchor == "end":
        x -= width(s, size)
    f = face(w)
    uses = []
    for i, ch in enumerate(s):
        gid = f.glyph(ch) if ch != " " else None
        if gid:
            uses.append(f'<use href="#{gid}" x="{i * 600}"/>' if i else f'<use href="#{gid}"/>')
    if not uses:
        return ""
    op = f' opacity="{opacity}"' if opacity is not None else ""
    sc = f"{size / f.upm:.5f}".rstrip("0")
    return (f'<g {paint(fill)}{op} transform="translate({num(x)} {num(y)}) scale({sc} -{sc})">'
            + "".join(uses) + "</g>")


def spans(parts, x, y, size, anchor="start"):
    """parts: [(text, fill, weight?)] laid out on one line."""
    total = sum(width(p[0], size) for p in parts)
    if anchor == "middle":
        x -= total / 2
    out = []
    for p in parts:
        out.append(text(p[0], x, y, size, p[1], p[2] if len(p) > 2 else "light"))
        x += width(p[0], size)
    return "".join(out)


def svg(w, h, body, style=""):
    st = f"<style>{style}</style>" if style else ""
    defs = "".join(f'<path id="{k}" d="{d}"/>' for k, d in DEFS.items() if d)
    DEFS.clear()
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {num(w)} {num(h)}" '
            f'width="{num(w)}" height="{num(h)}">{st}<defs>{defs}</defs>{body}</svg>\n')


def themed_style(roles):
    """Light by default, kitty colours when the reader's system is dark."""
    rules = lambda pal, prop: "".join(f".{r}{{{prop}:{pal[r]}}}" for r in roles)
    light = rules(L, "fill") + "".join(f".s-{r}{{stroke:{L[r]}}}" for r in roles)
    dark = rules(K, "fill") + "".join(f".s-{r}{{stroke:{K[r]}}}" for r in roles)
    return light + "@media (prefers-color-scheme: dark){" + dark + "}"


def write(name, content):
    (HERE / name).parent.mkdir(parents=True, exist_ok=True)
    (HERE / name).write_text(content)
    print("wrote", name)


# ── contrast guard ────────────────────────────────────────────────────────────

def lum(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    c = [v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4 for v in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


for fg, bg, what in [(K["muted"], K["bg"], "muted/window"), (K["fg"], K["bg"], "fg/window"),
                     (K["muted"], "#0d1117", "muted/gh-dark"), (L["muted"], "#ffffff", "muted/gh-light"),
                     (L["muted"], L["surface"], "muted/light-tab"), (K["muted"], K["surface"], "muted/dark-tab"),
                     (L["accent"], "#ffffff", "accent/gh-light"), (K["on_accent"], K["accent"], "pill")]:
    assert contrast(fg, bg) >= 4.5, f"{what}: {contrast(fg, bg):.2f}"


# ── hero: the dashboard ───────────────────────────────────────────────────────

def braille_dots(lines, x0, y0, cw, ch, r, fill):
    # bit → (col, row) of the 2×4 braille cell
    bits = [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (0, 3), (1, 3)]
    out = []
    for row, line in enumerate(lines):
        for col, c in enumerate(line):
            n = ord(c) - 0x2800
            if not 0 < n < 256:
                continue
            for b, (dx, dy) in enumerate(bits):
                if n >> b & 1:
                    cx = x0 + col * cw + (dx + 0.5) * cw / 2
                    cy = y0 + row * ch + (dy + 0.5) * ch / 4
                    out.append(f"M{num(cx)} {num(cy)}h0")
    return f'<path stroke="{fill}" stroke-width="{num(2 * r)}" stroke-linecap="round" d="{"".join(out)}"/>'


def thousands(n):
    return f"{n:,}"


CLOCK = "14:32"  # a still image can't tick; the date is the build date


def hero():
    W, H = 1280, 820
    wx, wy, ww, wh = 28, 20, W - 56, H - 64
    cx = W / 2
    art = (ROOT / "dashboard-header.txt").read_text().rstrip("\n").split("\n")
    cols = max(len(l) for l in art)
    cw, ch = 9.0, 18.5
    ax, ay = cx - cols * cw / 2, wy + 64

    stats = {"prs": 0, "issues": 0, "contributions": 0, "streak": 0}
    cache = Path("~/.cache/nvim/dashboard/stats.json").expanduser()
    if cache.exists():
        stats.update(json.loads(cache.read_text()))
    plural = lambda n, one, many: one if n == 1 else many
    sp = [(thousands(stats["prs"]), K["accent"], "medium"), (" " + plural(stats["prs"], "open PR", "open PRs"), K["muted"]),
          ("   ·   ", K["muted"]),
          (thousands(stats["issues"]), K["accent"], "medium"), (" " + plural(stats["issues"], "issue", "issues"), K["muted"]),
          ("   ·   ", K["muted"]),
          (thousands(stats["contributions"]), K["accent"], "medium"), (" contributions", K["muted"])]
    if stats["streak"]:
        sp += [("   ·   ", K["muted"]), (str(stats["streak"]), K["accent"], "medium"), (" day streak", K["muted"])]

    hints = [("f", "find"), ("r", "recent"), ("d", "cd"), ("s", "session"), ("c", "config"), ("q", "quit")]
    hp = []
    for i, (k, h) in enumerate(hints):
        if i:
            hp.append(("  ·  ", K["muted"]))
        hp += [(k, K["accent"], "bold"), (" " + h, K["muted"])]

    today = date.today()
    y_art_end = ay + len(art) * ch
    sl_y, sl_h = wy + wh - 16 - 30, 30  # statusline, inside kitty's padding

    body = f"""
<defs>
  <filter id="shadow" x="-10%" y="-10%" width="120%" height="130%">
    <feDropShadow dx="0" dy="18" stdDeviation="20" flood-color="#000" flood-opacity=".38"/>
  </filter>
  <linearGradient id="glass" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#2a221f"/><stop offset="1" stop-color="#231c1a"/>
  </linearGradient>
  <radialGradient id="moss" cx=".18" cy=".1" r=".55"><stop offset="0" stop-color="#a7c080" stop-opacity=".07"/><stop offset="1" stop-color="#a7c080" stop-opacity="0"/></radialGradient>
  <radialGradient id="ochre" cx=".9" cy=".95" r=".5"><stop offset="0" stop-color="#dbbc7f" stop-opacity=".05"/><stop offset="1" stop-color="#dbbc7f" stop-opacity="0"/></radialGradient>
  <clipPath id="win"><rect x="{wx}" y="{wy}" width="{ww}" height="{wh}" rx="14"/></clipPath>
</defs>
<rect x="{wx}" y="{wy}" width="{ww}" height="{wh}" rx="14" fill="url(#glass)" filter="url(#shadow)"/>
<g clip-path="url(#win)">
  <rect x="{wx}" y="{wy}" width="{ww}" height="{wh}" fill="url(#moss)"/>
  <rect x="{wx}" y="{wy}" width="{ww}" height="{wh}" fill="url(#ochre)"/>
</g>
<rect x="{wx + .5}" y="{wy + .5}" width="{ww - 1}" height="{wh - 1}" rx="13.5" fill="none" stroke="{K['line']}"/>
{braille_dots(art, ax, ay, cw, ch, 1.45, K['fg'])}
{text(" ".join(CLOCK), cx, y_art_end + 66, 34, K['accent'], 'bold', 'middle')}
{text(today.strftime('%A · %d %B %Y'), cx, y_art_end + 98, 17, K['muted'], 'light', 'middle')}
{spans(sp, cx, y_art_end + 150, 17, 'middle')}
{spans(hp, cx, y_art_end + 192, 17, 'middle')}
{statusline(wx + 18, sl_y, ww - 36, sl_h, K, mid_left=[("  main", K['fg'])],
            mid_right=[("snacks_dashboard", K['muted']), ("UTF-8", K['muted']), ("1:1", K['fg'])],
            mode="NORMAL", tail="Top", size=15)}
"""
    write("hero.svg", svg(W, H, body))


def statusline(x, y, w, h, P, mid_left, mid_right, mode, tail, size):
    """lualine as configured: coloured a/z blocks, transparent middle."""
    pad = size * 0.9
    base = y + h / 2 + size * 0.36
    acc, on = P["accent"], P["on_accent"]
    a_w = width(mode, size) + 2 * pad
    z_w = width(tail, size) + 2 * pad
    out = [f'<rect {paint(acc)} x="{num(x)}" y="{num(y)}" width="{num(a_w)}" height="{h}" rx="4"/>',
           text(mode, x + pad, base, size, on, "bold"),
           f'<rect {paint(acc)} x="{num(x + w - z_w)}" y="{num(y)}" width="{num(z_w)}" height="{h}" rx="4"/>',
           text(tail, x + w - z_w + pad, base, size, on, "bold")]
    cx = x + a_w + pad
    for t, fill in mid_left:
        out.append(text(t, cx, base, size, fill))
        cx += width(t, size) + 2 * pad
    cx = x + w - z_w - pad
    for t, fill in reversed(mid_right):
        out.append(text(t, cx, base, size, fill, anchor="end"))
        cx -= width(t, size) + 2 * pad
    return "".join(out)


# ── tabline nav ───────────────────────────────────────────────────────────────

TABS = [("", "PDF", "pdf"), ("", "Claude", "claude"), ("", "Terminals", "terminals"),
        ("", "Notebooks", "notebooks"), ("", "Themes", "themes"), ("", "Anatomy", "anatomy"),
        ("", "Keys", "keys"), ("", "Install", "install")]


def tabs():
    size, h, pad = 15, 40, 18
    style = themed_style(["fg", "muted", "accent", "surface", "line"])
    for i, (icon, label, slug) in enumerate(TABS):
        w = pad + width(icon + "  " + label, size) + pad
        first, last = i == 0, i == len(TABS) - 1
        r = 8
        # bufferline-ish: the bar is one strip; ends are rounded, joins are hairlines
        path = (f"M{r if first else 0} 0H{num(w - (r if last else 0))}"
                + (f"a{r} {r} 0 0 1 {r} {r}V{h - r}a{r} {r} 0 0 1 -{r} {r}" if last else f"V{h}")
                + f"H{r if first else 0}"
                + (f"a{r} {r} 0 0 1 -{r} -{r}V{r}a{r} {r} 0 0 1 {r} -{r}" if first else "V0")
                + "Z")
        sep = "" if last else f'<rect class="line" x="{num(w - 1)}" y="10" width="1" height="{h - 20}"/>'
        body = (f'<path class="surface" d="{path}"/>{sep}'
                + spans([(icon, ".accent"), ("  " + label, ".fg")], pad, h / 2 + size * 0.36, size))
        write(f"tabs/{slug}.svg", svg(w, h, body, style))


# ── theme specimen ────────────────────────────────────────────────────────────

SCHEMES = ["kanso", "evergarden", "melange", "everforest", "gruvbox-material", "kanagawa",
           "kanagawa-paper", "rose-pine", "bamboo", "flexoki", "vesper", "catppuccin", "nightfox",
           "lackluster", "zenbones", "forestbones", "neobones", "kanagawabones", "seoulbones", "kanso:light"]


def read_schemes():
    with tempfile.TemporaryDirectory() as state:
        (Path(state) / "nvim").mkdir()
        (Path(state) / "nvim" / "ui.json").write_text('{"transparent":false,"restore_transparent":false,"background":"dark"}')
        out = HERE / "schemes.json"
        env = dict(os.environ, XDG_STATE_HOME=state, SCHEMES=",".join(SCHEMES), OUT=str(out))
        subprocess.run(["nvim", "--headless", "-c", f"luafile {HERE / 'schemes.lua'}"], env=env, cwd=ROOT,
                       check=True, stderr=subprocess.DEVNULL)
        print("wrote schemes.json")


def specimen():
    data = json.loads((HERE / "schemes.json").read_text())
    cols, cw, chh, gap, size = 4, 290, 112, 18, 15
    rows = -(-len(data) // cols)
    W, H = cols * cw + (cols - 1) * gap, rows * chh + (rows - 1) * gap
    out = []
    lh = size * 1.55
    for i, s in enumerate(data):
        hl = s["hl"]
        g = lambda grp, k="fg", fb=None: hl.get(grp, {}).get(k) or fb
        bg, fg = g("Normal", "bg"), g("Normal")
        kw = g("Keyword") if g("Keyword") not in (None, fg) else g("Statement", fb=fg)
        fn, st, cn, cm = g("Function", fb=fg), g("String", fb=fg), g("Constant", fb=fg), g("Comment", fb=fg)
        cl = g("CursorLine", "bg", bg)
        x, y = (i % cols) * (cw + gap), (i // cols) * (chh + gap)
        name = s["spec"].replace(":light", " light")
        tx, ty = x + 20, y + 22 + size * 0.95
        out.append(f'<rect x="{x}" y="{y}" width="{cw}" height="{chh}" rx="10" fill="{bg}"/>')
        out.append(f'<rect x="{x}" y="{num(ty + lh - size * 1.05)}" width="{cw}" height="{num(lh)}" fill="{cl}"/>')
        out.append(spans([("local ", kw, "italic"), ("function ", kw, "italic"), ("bloom", fn), ("(n)", fg)], tx, ty, size))
        out.append(spans([("  return ", kw, "italic"), ('"moss"', st), (", ", fg), ("42", cn)], tx, ty + lh, size))
        out.append(spans([("end ", kw, "italic"), ("-- " + name, cm, "italic")], tx, ty + 2 * lh, size))
        out.append(f'<rect x="{x + .5}" y="{y + .5}" width="{cw - 1}" height="{chh - 1}" rx="9.5" fill="none" stroke="#ffffff" stroke-opacity=".06"/>')
    write("themes.svg", svg(W, H, "".join(out)))


# ── anatomy: the config as a neo-tree ─────────────────────────────────────────

TREE = [
    (0, "", "nvim", ".accent", ""),
    (1, "", "init.lua", ".blue", "options → keymaps → lazy.nvim → plugins"),
    (1, "", "lua/defaults", ".yellow", "the editor itself, no plugins"),
    (2, "", "ui_toggle.lua", ".blue", "transparent ↔ solid, dark ↔ light, persisted"),
    (2, "", "cursorline.lua", ".blue", "only in the focused file window, three styles"),
    (2, "", "bufclose.lua", ".blue", ":q closes the buffer, not Neovim"),
    (2, "", "lsp.lua", ".blue", "one LspAttach for every server"),
    (2, "", "dashboard_data.lua", ".blue", "one gh graphql call, cached 30 min"),
    (1, "", "lua/plugins", ".yellow", "70 lazy.nvim specs, one per file"),
    (1, "", "lua/pdfview", ".yellow", "PDF viewer on kitty graphics"),
    (1, "", "lua/claude_chats", ".yellow", "Claude sessions as ordinary buffers"),
    (1, "", "lua/terminals", ".yellow", "shells that report cwd, command and exit"),
    (1, "", "shell/zsh", ".yellow", "ZDOTDIR wrapper that emits the OSC marks"),
    (1, "", "doc", ".yellow", ":help nvim-config"),
]


def anatomy():
    size, row, indent, W = 16, 34, 30, 1000
    x0, y0, desc_x = 16, 30, 420
    H = y0 + len(TREE) * row - 8
    out = []
    # indent guides; the open lua/defaults scope is drawn in the accent (mini.indentscope)
    for depth, scope in [(0, ".line"), (1, ".accent")]:
        rows = [i for i, t in enumerate(TREE) if t[0] > depth] if depth == 0 else [i for i, t in enumerate(TREE) if t[0] == 2]
        top, bot = y0 + (rows[0] - 1) * row + 10, y0 + rows[-1] * row + 6
        out.append(f'<rect class="{scope[1:]}" x="{num(x0 + depth * indent + 6)}" y="{num(top)}" width="1.5" height="{num(bot - top)}"/>')
    for i, (depth, icon, name, tint, desc) in enumerate(TREE):
        y = y0 + i * row
        x = x0 + depth * indent
        out.append(text(icon, x, y, size, tint))
        out.append(text(name, x + width("  ", size) + size * 0.6, y, size, ".fg", "medium" if depth < 2 else "light"))
        if desc:
            out.append(text(desc, desc_x, y, size, ".muted"))
    write("anatomy.svg", svg(W, H, "".join(out), themed_style(["fg", "muted", "accent", "line", "blue", "yellow"])))


# ── footer: lualine on this README ───────────────────────────────────────────

def footer():
    W, H = 1000, 30
    style = themed_style(["fg", "muted", "accent", "on_accent"])
    body = statusline(0, 0, W, H, {"accent": ".accent", "on_accent": ".on_accent"},
                      mid_left=[("  main", ".fg"), ("README.md", ".muted")],
                      mid_right=[("markdown", ".muted"), ("UTF-8", ".muted"), ("EOF", ".fg")],
                      mode="NORMAL", tail="Bot", size=14)
    write("footer.svg", svg(W, H, body, style))


# ── screenshot frames ─────────────────────────────────────────────────────────

SHOTS = [
    ("editing", "\ue61d", "main.cpp", "clangd · neo-tree, bufferline, barbecue, folds",
     "A source file with neo-tree open and a few buffers in the bufferline."),
    ("pdf-tex", "\uf1c1", "integracion_compleja.tex", "lua/pdfview/tex.lua · SyncTeX both ways",
     "A .tex file on the left, <leader>lv preview on the right, cursor on a line so the forward-search highlight shows."),
    ("pdf-md", "\uf1c1", "README.md", "lua/pdfview/markdown.lua · pandoc → typst",
     "A Markdown file (this README works) with <leader>pv open beside it."),
    ("claude", "\uf086", "claude", "lua/claude_chats/ · one buffer per session",
     "neo-tree on the Claude tab listing past sessions, a chat running in the main window."),
    ("terminals", "\uf120", "terminals", "lua/terminals/ · named shells, REPLs, winbar tabs",
     "neo-tree's Terminals tab with 2–3 named shells."),
    ("notebook", "\uf02d", "avance4.ipynb", "molten + jupytext · cells run in real kernels",
     "A notebook open as Markdown, a few cells run."),
]


def frame(name, icon, label, note, todo):
    src = HERE / "shots" / f"{name}.png"
    tab_size, tab_h, pad = 22, 58, 26
    if src.exists():
        w, h = map(int, subprocess.check_output(["magick", "identify", "-format", "%w %h", str(src)]).split())
    else:
        w, h = 2560, 1500
    s = w / 1280  # draw chrome in 1280-wide units, scaled to the shot
    tab_w = pad + width(icon + "  " + label, tab_size) + pad
    th = tab_h * s
    W, H = w, h + th
    r = 14 * s
    R = num(r)
    card = f"M0 {R}a{R} {R} 0 0 1 {R} -{R}H{num(w - r)}a{R} {R} 0 0 1 {R} {R}V{num(H - r)}a{R} {R} 0 0 1 -{R} {R}H{R}a{R} {R} 0 0 1 -{R} -{R}Z"
    # one rounded card: a bufferline-dark bar holding the active tab, the shot below it.
    # The caption sits on the dark bar, so it reads on white and dark GitHub alike.
    body = [f'<defs><clipPath id="c"><path d="{card}"/></clipPath></defs><g clip-path="url(#c)">',
            f'<rect fill="{K["bar"]}" width="{w}" height="{num(th)}"/>',
            f'<rect fill="{K["bg"]}" x="{num(10 * s)}" y="{num(10 * s)}" width="{num(tab_w * s)}" height="{num(th)}" rx="{num(8 * s)}"/>',
            f'<rect fill="{K["accent"]}" x="{num(18 * s)}" y="{num(10 * s)}" width="{num((tab_w - 16) * s)}" height="{num(2.5 * s)}" rx="{num(1.25 * s)}"/>',
            f'<g transform="scale({num(s)})">'
            + spans([(icon, K["accent"]), ("  " + label, K["fg"], "medium")], 10 + pad, tab_h / 2 + 5 + tab_size * 0.36, tab_size)
            + text(note, 10 + tab_w + 22, tab_h / 2 + 5 + 0.36 * 17, 17, K["muted"])
            + "</g>"]
    if src.exists():
        data = base64.b64encode(src.read_bytes()).decode()  # rsvg won't read files outside the SVG's dir
        body.append(f'<image href="data:image/png;base64,{data}" x="0" y="{num(th)}" width="{w}" height="{h}"/>')
    else:
        cx, cy = w / 2, th + h / 2
        body.append(f'<rect fill="{K["bg"]}" y="{num(th)}" width="{w}" height="{h}"/>')
        body.append(f'<g transform="scale({num(s)})">'
                    + text(f"shots/{name}.png", cx / s, cy / s - 14, 26, K["accent"], "medium", "middle")
                    + text(todo, cx / s, cy / s + 26, 15, K["muted"], "light", "middle") + "</g>")
    body.append(f'</g><path fill="none" stroke="{K["line"]}" stroke-width="{num(s)}" d="{card}"/>')
    out = HERE / "frames" / f"{name}.webp"
    to_webp(svg(W, H, "".join(body)), out, W)
    print("wrote", out.relative_to(HERE), "(placeholder)" if not src.exists() else "")


def to_webp(svg_text, out, w):
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as f:
        f.write(svg_text)
    out.parent.mkdir(exist_ok=True)
    png = f.name.replace(".svg", ".png")
    subprocess.run(["rsvg-convert", "-w", str(min(w, 2000)), "-o", png, f.name], check=True)  # 2× GitHub's column
    subprocess.run(["cwebp", "-quiet", "-q", "86", "-alpha_q", "100", png, "-o", str(out)], check=True)
    os.remove(f.name), os.remove(png)


def hero_image():
    """hero.webp: the real dashboard (shots/dashboard.png) on a rounded card, else the drawn hero.svg."""
    src = HERE / "shots" / "dashboard.png"
    if not src.exists():
        to_webp((HERE / "hero.svg").read_text(), HERE / "hero.webp", 2560)
        print("wrote hero.webp (drawn)")
        return
    w, h = map(int, subprocess.check_output(["magick", "identify", "-format", "%w %h", str(src)]).split())
    R = num(14 * w / 1280)
    card = f'<rect width="{w}" height="{h}" rx="{R}"/>'
    data = base64.b64encode(src.read_bytes()).decode()
    body = (f'<defs><clipPath id="c">{card}</clipPath></defs>'
            f'<image href="data:image/png;base64,{data}" width="{w}" height="{h}" clip-path="url(#c)"/>'
            f'<rect width="{w}" height="{h}" rx="{R}" fill="none" stroke="{K["line"]}" stroke-width="{num(w / 1280)}"/>')
    to_webp(svg(w, h, body), HERE / "hero.webp", w)
    print("wrote hero.webp")


if __name__ == "__main__":
    for tool in ("rsvg-convert", "cwebp", "magick"):
        if not shutil.which(tool):
            sys.exit(f"missing {tool}")
    if "--schemes" in sys.argv or not (HERE / "schemes.json").exists():
        read_schemes()
    hero()
    hero_image()
    tabs()
    specimen()
    anatomy()
    footer()
    for shot in SHOTS:
        frame(*shot)
