-- Notebook support around Molten (issue #40), kept as a thin layer so Molten
-- stays replaceable:
--   kernel.lua   which kernel a buffer gets; no registration (phase 2)
--   plots.lua    plot paper (theme / paper), flattening, split view (phase 3)
--   ui.lua       themed output windows, full output buffer (phase 3)
local M = {}

function M.setup()
  -- $JUPYTER_PATH must be set before Neovim's Python host (Molten) spawns.
  require("notebook.kernel").setup()
  require("notebook.plots").setup()
  require("notebook.ui").setup()
end

return M
