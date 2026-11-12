// pandoc typst template for lua/pdfview/markdown.lua (style "editorial", picked with
// <leader>ps / :MarkdownStyle). Pages are $$pagewidth$$ x $$pageheight$$, shaped like the
// split; the viewer recolours ink and paper, so keep to light-theme colours.
// Editorial: New York display headings over SF body, airy spacing,
// soft rounded code, quotes as large serif italics.
#let fg = rgb("#1d1d1f")
#let muted = rgb("#6e6e73")
#let tint = rgb("#f2f2f4")
#let line-c = rgb("#d2d2d7")
#let divider() = block(above: 1.8em, below: 1.8em, line(length: 100%, stroke: 0.5pt + line-c))
#let horizontalRule = divider()
$if(highlighting-definitions)$
$highlighting-definitions$
$endif$
#set page(width: $pagewidth$, height: $pageheight$, numbering: none, fill: white, margin: (x: 26pt, y: 24pt))
#set smartquote(enabled: false)
#set page(margin: (x: 28pt, y: 26pt))
#set text(font: ("SF NS", "Helvetica Neue", "Apple Symbols"), size: 11pt, fill: fg, hyphenate: false)
#set par(leading: 0.78em, spacing: 1.25em)
#set list(indent: 0.4em, body-indent: 0.6em, spacing: 0.65em)
#set enum(indent: 0.4em, body-indent: 0.6em, spacing: 0.65em)
#show link: it => underline(stroke: 0.6pt + muted, offset: 2.5pt, it)
#show heading: set text(font: ("New York", "Iowan Old Style"), weight: "semibold")
#show heading.where(level: 1): it => block(above: 0.4em, below: 1.1em, text(size: 2.4em, tracking: -0.015em, it.body))
#show heading.where(level: 2): it => block(above: 2em, below: 0.85em, text(size: 1.55em, it.body))
#show heading.where(level: 3): it => block(above: 1.6em, below: 0.7em, text(size: 1.15em, it.body))
#show raw: set text(font: ("SF NS Mono", "Menlo"), size: 0.85em)
#show raw.where(block: false): it => box(fill: tint, inset: (x: 0.35em), outset: (y: 0.3em), radius: 3pt, it)
#show raw.where(block: true): it => block(width: 100%, fill: tint, inset: 14pt, radius: 10pt, above: 1.2em, below: 1.4em, it)
#show quote.where(block: true): it => block(inset: (x: 1.2em), above: 1.5em, below: 1.5em,
  text(font: ("New York", "Iowan Old Style"), style: "italic", size: 1.3em, it.body))
#set table(stroke: (_, y) => (bottom: 0.5pt + line-c), inset: (x: 10pt, y: 7pt))
#show table.cell.where(y: 0): set text(fill: muted, size: 0.9em)
#show figure.where(kind: table): set align(left)
#show table: set align(left)
#show figure: set block(above: 1.2em, below: 1.4em)
$body$
