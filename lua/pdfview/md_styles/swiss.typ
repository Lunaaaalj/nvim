// pandoc typst template for lua/pdfview/markdown.lua (style "swiss", picked with
// <leader>ps / :MarkdownStyle). Pages are $$pagewidth$$ x $$pageheight$$, shaped like the
// split; the viewer recolours ink and paper, so keep to light-theme colours.
// Swiss: Avenir Next, big tight titles, h2 under a heavy rule above it,
// flat square code panels, horizontal-only tables.
#let fg = rgb("#111111")
#let muted = rgb("#5c5c5c")
#let tint = rgb("#efefef")
#let divider() = block(above: 1.6em, below: 1.6em, line(length: 100%, stroke: 1.5pt + fg))
#let horizontalRule = divider()
$if(highlighting-definitions)$
$highlighting-definitions$
$endif$
#set page(width: $pagewidth$, height: $pageheight$, numbering: none, fill: white, margin: (x: 26pt, y: 24pt))
#set smartquote(enabled: false)
#set text(font: ("Avenir Next", "Helvetica Neue", "Apple Symbols"), size: 10.5pt, fill: fg, hyphenate: false)
#set par(leading: 0.68em, spacing: 1.1em)
#set list(indent: 0em, body-indent: 0.7em, spacing: 0.55em, marker: ([–], [–]))
#set enum(indent: 0em, body-indent: 0.7em, spacing: 0.55em)
#show link: it => underline(stroke: 1pt + fg, offset: 2.5pt, text(weight: "medium", it))
#show strong: set text(weight: "bold")
#show heading: set text(weight: "bold")
#show heading.where(level: 1): it => block(above: 0.2em, below: 1.1em, text(size: 2.5em, weight: "bold", tracking: -0.03em, it.body))
#show heading.where(level: 2): it => block(width: 100%, above: 2em, below: 1em, stroke: (top: 1.5pt + fg),
  inset: (top: 0.55em), text(size: 1.3em, tracking: -0.01em, it.body))
#show heading.where(level: 3): it => block(above: 1.6em, below: 0.7em, text(size: 1em, it.body))
#show raw: set text(font: ("SF NS Mono", "Menlo"), size: 0.84em)
#show raw.where(block: false): it => box(fill: tint, inset: (x: 0.3em), outset: (y: 0.25em), it)
#show raw.where(block: true): it => block(width: 100%, fill: tint, inset: (x: 12pt, y: 11pt), above: 1em, below: 1.2em, it)
#show quote.where(block: true): it => block(inset: (left: 0em, right: 2em), above: 1.3em, below: 1.3em,
  text(size: 1.2em, weight: "medium", tracking: -0.01em, it.body))
#set table(stroke: (_, y) => (bottom: if y == 0 { 1.5pt + fg } else { 0.5pt + rgb("#bdbdbd") }), inset: (x: 0pt, y: 6pt))
#show table.cell: set block(inset: (right: 14pt))
#show figure.where(kind: table): set align(left)
#show table: set align(left)
#show figure: set block(above: 1.1em, below: 1.3em)
$body$
