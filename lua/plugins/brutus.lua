-- Brutus ("Cobalt Kinetic"): Neo-Brutalist deep navy with cobalt / neon-cyan
-- accents. `:colorscheme cobalt-kinetic`; the repo is named brutus, the
-- scheme is not. Dark only and it sets 'background' itself, so <leader>uB
-- warns instead of switching. It's an NvChad/base46 theme with a standalone
-- fallback (used here, since base46 isn't installed) that has no options,
-- so transparency comes from the global strip autocmd in lua/defaults/init.lua.
return {
    "mohseenrm/brutus",
    name = "brutus",
    lazy = false,
    priority = 1000,
}
