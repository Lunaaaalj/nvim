// pandoc typst template for lua/pdfview/markdown.lua -- GitHub's README look
// (github-markdown-css, light theme) on pages shaped like the preview window:
// $$pagewidth$$ x $$pageheight$$, so "fit page" fills the split exactly and j/k
// flow screen to screen. The width follows the split's columns, so text keeps
// its size and reflows on resize. The viewer recolours white paper / dark ink to the
// colorscheme, so stick to light-theme colours here.

#let fg = rgb("#1f2328")
#let muted = rgb("#59636e")
#let border = rgb("#d1d9e0")
#let canvas = rgb("#f6f8fa")

// pandoc emits #divider() for `---`
#let divider() = block(above: 1.5em, below: 1.5em, line(length: 100%, stroke: 0.25em + border))
#let horizontalRule = divider()

$if(highlighting-definitions)$
$highlighting-definitions$
$endif$

#set page(
  width: $pagewidth$,
  height: $pageheight$,
  margin: (x: 22pt, y: 20pt),
  numbering: none,
  fill: white,
)
#set text(
  font: ("SF NS", "Helvetica Neue", "Helvetica", "Apple Color Emoji", "Apple Symbols"), // Symbols: task-list boxes
  size: 11pt,
  fill: fg,
  hyphenate: false,
)
#set par(leading: 0.62em, spacing: 1.15em, justify: false)
#set smartquote(enabled: false)
#set list(indent: 0.6em, body-indent: 0.5em, spacing: 0.55em)
#set enum(indent: 0.6em, body-indent: 0.5em, spacing: 0.55em)
#set terms(hanging-indent: 1.5em)

#show link: set text(fill: rgb("#0969da"))

// headings: 600 weight; h1/h2 get GitHub's bottom rule
#show heading: set text(weight: 600)
#show heading: set block(above: 1.6em, below: 0.9em)
#show heading.where(level: 1): it => block(width: 100%, above: 1.2em, below: 1em,
  stroke: (bottom: 0.5pt + border), inset: (bottom: 0.3em), text(size: 2em, it.body))
#show heading.where(level: 2): it => block(width: 100%, above: 1.6em, below: 1em,
  stroke: (bottom: 0.5pt + border), inset: (bottom: 0.3em), text(size: 1.5em, it.body))
#show heading.where(level: 3): set text(size: 1.25em)
#show heading.where(level: 5): set text(size: 0.875em)
#show heading.where(level: 6): set text(size: 0.85em, fill: muted)

// code: SF Mono, grey box inline, rounded panel for blocks
#show raw: set text(font: ("SF NS Mono", "Menlo"), size: 0.86em)
#show raw.where(block: false): it => box(fill: rgb("#818b981f"), inset: (x: 0.35em),
  outset: (y: 0.3em), radius: 4pt, it)
#show raw.where(block: true): it => block(width: 100%, fill: canvas, inset: 12pt,
  radius: 6pt, above: 1em, below: 1.15em, it)

// > quotes: grey left rule, muted text
#show quote.where(block: true): it => block(stroke: (left: 0.25em + border),
  inset: (left: 1em, y: 0.15em), above: 1em, below: 1.15em, text(fill: muted, it.body))

// tables: full grid, zebra rows (header cells are made bold by the filter --
// only real Markdown headers, not the first row of HTML card tables). pandoc
// wraps tables in a centred figure; GitHub keeps them left.
#set table(stroke: 0.5pt + border, inset: (x: 9pt, y: 5pt),
  fill: (_, y) => if calc.even(y) and y > 0 { canvas })
#show figure.where(kind: table): set align(left)
// cells with no alignment of their own would inherit pandoc's align(center)
#show table: set align(left)
#show figure: set block(above: 1em, below: 1.15em)

$body$
