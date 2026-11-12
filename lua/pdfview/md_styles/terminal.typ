// pandoc typst template for lua/pdfview/markdown.lua (style "terminal", picked with
// <leader>ps / :MarkdownStyle). Pages are $$pagewidth$$ x $$pageheight$$, shaped like the
// split; the viewer recolours ink and paper, so keep to light-theme colours.
// Terminal: everything in Iosevka Term Slab, headings keep their # marks,
// box-drawn code panels, > on quotes -- the source, typeset.
#let fg = rgb("#1a1a1a")
#let muted = rgb("#8a8a8a")
#let border = rgb("#b5b5b5")
#let divider() = block(above: 1.2em, below: 1.2em, text(fill: muted, repeat[─]))
#let horizontalRule = divider()
$if(highlighting-definitions)$
$highlighting-definitions$
$endif$
#set page(width: $pagewidth$, height: $pageheight$, numbering: none, fill: white, margin: (x: 26pt, y: 24pt))
#set smartquote(enabled: false)
#set text(font: ("IosevkaTermSlab NF", "Menlo", "Apple Symbols"), size: 10.5pt, fill: fg, hyphenate: false)
#set par(leading: 0.62em, spacing: 1.1em)
#set list(indent: 0em, body-indent: 0.6em, spacing: 0.5em, marker: (text(fill: muted)[-], text(fill: muted)[\*]))
#set enum(indent: 0em, body-indent: 0.6em, spacing: 0.5em, numbering: n => text(fill: muted, str(n) + "."))
#show link: it => [#text(fill: muted)[\[]#it.body#text(fill: muted)[\]]]
#show strong: set text(weight: "extrabold")
#show emph: set text(style: "italic")
#show heading: set text(size: 1em, weight: "extrabold")
#show heading: it => block(above: 1.6em, below: 0.8em, [#text(fill: muted, weight: "regular", "#" * it.level + " ")#it.body])
#show heading.where(level: 1): it => block(above: 0.3em, below: 1em, width: 100%, stroke: (bottom: 0.6pt + border), inset: (bottom: 0.5em),
  [#text(fill: muted, weight: "regular", "# ")#upper(it.body)])
#show raw: set text(font: ("IosevkaTermSlab NF", "Menlo"), size: 1.25em)
#show raw.where(block: false): it => text(fill: muted, "`") + it + text(fill: muted, "`")
#show raw.where(block: true): it => block(width: 100%, stroke: 0.6pt + border, inset: (x: 10pt, y: 9pt), above: 1em, below: 1.1em, it)
#show quote.where(block: true): it => grid(columns: (1.6em, 1fr), text(fill: muted)[>], it.body)
#set table(stroke: 0.6pt + border, inset: (x: 8pt, y: 4pt))
#show figure.where(kind: table): set align(left)
#show table: set align(left)
$body$
