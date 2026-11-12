// pandoc typst template for lua/pdfview/markdown.lua (style "book", picked with
// <leader>ps / :MarkdownStyle). Pages are $$pagewidth$$ x $$pageheight$$, shaped like the
// split; the viewer recolours ink and paper, so keep to light-theme colours.
// Book: Iowan Old Style, justified + hyphenated, indented paragraphs,
// small-caps titles, booktabs tables, spaced asterisks for ---.
#let fg = rgb("#1b1b1b")
#let muted = rgb("#6b6b6b")
#let rule = rgb("#9a9a9a")
#let divider() = align(center, block(above: 1.4em, below: 1.4em, text(fill: muted, size: 1.1em, tracking: 0.6em, "* * *")))
#let horizontalRule = divider()
$if(highlighting-definitions)$
$highlighting-definitions$
$endif$
#set page(width: $pagewidth$, height: $pageheight$, numbering: none, fill: white, margin: (x: 26pt, y: 24pt))
#set smartquote(enabled: false)
#set text(font: ("Iowan Old Style", "Palatino", "Apple Symbols"), size: 11.5pt, fill: fg, hyphenate: true, lang: "en", number-type: "old-style")
#set par(justify: true, leading: 0.72em, spacing: 0.72em, first-line-indent: 1.3em)
#set list(indent: 1.3em, body-indent: 0.55em, spacing: 0.5em, marker: ([–], [·]))
#set enum(indent: 1.3em, body-indent: 0.55em, spacing: 0.5em)
#show link: it => underline(stroke: 0.4pt + rule, offset: 2pt, it)
#show strong: set text(weight: 600)
#show heading: set text(weight: "regular")
#show heading.where(level: 1): it => align(center, block(above: 0.6em, below: 1.6em,
  text(size: 1.75em, tracking: 0.08em, smallcaps(it.body))))
#show heading.where(level: 2): it => block(above: 1.8em, below: 0.9em, text(size: 1.3em, style: "italic", it.body))
#show heading.where(level: 3): it => block(above: 1.5em, below: 0.7em, text(tracking: 0.06em, smallcaps(it.body)))
#show raw: set text(font: ("SF NS Mono", "Menlo"), size: 0.8em)
#show raw.where(block: true): it => block(width: 100%, inset: (x: 1.3em, y: 0.9em), above: 1.1em, below: 1.1em,
  stroke: (top: 0.4pt + rule, bottom: 0.4pt + rule), it)
#show quote.where(block: true): it => block(inset: (x: 2.2em), above: 1.1em, below: 1.1em, text(style: "italic", it.body))
#set table(stroke: none, inset: (x: 8pt, y: 4.5pt))
#show table: it => block(stroke: (top: 0.9pt + fg, bottom: 0.9pt + fg), it)
#show table.cell.where(y: 0): it => block(stroke: (bottom: 0.4pt + fg), width: 100%, it)
#show figure.where(kind: table): set align(center)
#show table: set align(left)
#show figure: set block(above: 1.2em, below: 1.2em)
$body$
