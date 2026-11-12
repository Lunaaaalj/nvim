// pandoc typst template for lua/pdfview/markdown.lua (style "article", picked with
// <leader>ps / :MarkdownStyle). Pages are $$pagewidth$$ x $$pageheight$$, shaped like the
// split; the viewer recolours ink and paper, so keep to light-theme colours.
// Article: the LaTeX `article` look. Libertinus, numbered sections,
// justified, bold serif headings, booktabs tables, code without boxes.
#let fg = rgb("#000000")
#let muted = rgb("#555555")
#let divider() = align(center, block(above: 1.2em, below: 1.2em, line(length: 30%, stroke: 0.4pt + fg)))
#let horizontalRule = divider()
$if(highlighting-definitions)$
$highlighting-definitions$
$endif$
#set page(width: $pagewidth$, height: $pageheight$, numbering: none, fill: white, margin: (x: 26pt, y: 24pt))
#set smartquote(enabled: false)
#set page(margin: (x: 30pt, y: 26pt))
#set text(font: ("Libertinus Serif", "Apple Symbols"), size: 11.5pt, fill: fg, hyphenate: true, lang: "en")
#set par(justify: true, leading: 0.6em, spacing: 0.6em, first-line-indent: 1.5em)
#set list(indent: 1em, body-indent: 0.6em, spacing: 0.45em, marker: ([•], [–]))
#set enum(indent: 1em, body-indent: 0.6em, spacing: 0.45em)
#show link: set text(fill: fg)
#set heading(numbering: (..n) => { let p = n.pos(); if p.len() > 1 { numbering("1.1", ..p.slice(1)) } })
#show heading: set block(above: 1.5em, below: 0.8em)
#show heading.where(level: 1): it => align(center, block(above: 0.4em, below: 1.5em, text(size: 1.7em, weight: "regular", it.body)))
#show heading.where(level: 2): set text(size: 1.2em)
#show heading.where(level: 3): set text(size: 1.05em)
#show raw: set text(font: ("Source Code Pro", "Menlo"), size: 0.82em)
#show raw.where(block: true): it => block(inset: (left: 1.5em), above: 1.1em, below: 1.2em, it)
#show quote.where(block: true): it => block(inset: (x: 2em), above: 1.2em, below: 1.2em, it.body)
#set table(stroke: none, inset: (x: 7pt, y: 4pt))
#show table: it => block(stroke: (top: 0.8pt + fg, bottom: 0.8pt + fg), it)
#show table.cell.where(y: 0): it => block(stroke: (bottom: 0.4pt + fg), width: 100%, it)
#show figure.where(kind: table): set align(center)
#show table: set align(left)
$body$
