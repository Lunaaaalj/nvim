-- Writing companion: Claude (a cheap model, through the `claude` CLI and your
-- Claude Code login) as a copy editor, a developmental editor and a reader.
--
--   <leader>Wg / WG   grammar audit (errors / + style & clarity), walked in the
--                     spell-audit float; issues are also diagnostics
--   <leader>Wp        the same, for the paragraph under the cursor
--   <leader>Wo        reverse outline: summary, role and flags per paragraph
--   <leader>Wa        rigor review: loose arguments, unsupported or overclaimed
--                     statements, fallacies, inconsistencies (report + walk)
--   <leader>Wr        rewrite the selection / paragraph (pick an instruction)
--   <leader>Wq        ask about the selection / paragraph
--   <leader>Wc        companion chat in a split
--   <leader>Wd / Wx   toggle the AI diagnostics / clear the grammar issues
--
-- Nothing runs on its own: text only leaves Neovim when you press one of
-- these. A `.nvim/writing.md` above the file is your style guide (audience,
-- register, conventions, terms to leave alone), sent with every request;
-- words in your spellfile are never "corrected". Results are cached, so
-- repeating a pass only sends what changed. Modules: claude.lua (CLI),
-- prose.lua (paragraphs), issues.lua (quote-anchored findings), grammar.lua,
-- rigor.lua, outline.lua, assist.lua.

local M = {}

local api = vim.api

local function grammar(o)
  return function() require("writing.grammar").audit(o) end
end

function M.toggle_diagnostics()
  local all = { require("writing.grammar").ns_diag, require("writing.outline").ns_diag, require("writing.rigor").ns_diag }
  local on = not vim.diagnostic.is_enabled({ ns_id = all[1] })
  for _, ns in ipairs(all) do vim.diagnostic.enable(on, { ns_id = ns }) end
  vim.notify("Writing diagnostics " .. (on and "on" or "off"), vim.log.levels.INFO, { title = "Writing" })
end

function M.setup()
  require("writing.issues").setup()
  require("writing.outline").setup()
  require("writing.rigor").setup()

  local map = vim.keymap.set
  map("n", "<leader>Wg", grammar({}), { desc = "Writing: grammar audit" })
  map("n", "<leader>WG", grammar({ style = true }), { desc = "Writing: grammar + style audit" })
  map("n", "<leader>Wp", function()
    local row = api.nvim_win_get_cursor(0)[1]
    require("writing.grammar").audit({ range = { row, row } })
  end, { desc = "Writing: grammar audit of this paragraph" })
  map("n", "<leader>Wo", function() require("writing.outline").open() end, { desc = "Writing: reverse outline" })
  map("n", "<leader>Wa", function() require("writing.rigor").review() end,
    { desc = "Writing: rigor review (arguments, claims, evidence)" })
  map("n", "<leader>Wr", function() require("writing.assist").rewrite(false) end, { desc = "Writing: rewrite paragraph" })
  map("x", "<leader>Wr", function()
    vim.cmd("normal! \27") -- leave visual mode so '< '> are set
    require("writing.assist").rewrite(true)
  end, { desc = "Writing: rewrite selection" })
  map("n", "<leader>Wq", function() require("writing.assist").ask(false) end, { desc = "Writing: ask about paragraph" })
  map("x", "<leader>Wq", function()
    vim.cmd("normal! \27")
    require("writing.assist").ask(true)
  end, { desc = "Writing: ask about selection" })
  map("n", "<leader>Wc", function() require("writing.assist").chat() end, { desc = "Writing: companion chat" })
  map("n", "<leader>Wd", M.toggle_diagnostics, { desc = "Writing: toggle AI diagnostics" })
  map("n", "<leader>Wx", function()
    require("writing.grammar").clear()
    require("writing.rigor").store:clear()
    vim.diagnostic.reset(require("writing.outline").ns_diag, 0)
  end, { desc = "Writing: clear AI issues" })

  local subs = {
    grammar = grammar({}), style = grammar({ style = true }),
    outline = function() require("writing.outline").open() end,
    rigor = function() require("writing.rigor").review() end,
    rewrite = function() require("writing.assist").rewrite(false) end,
    ask = function() require("writing.assist").ask(false) end,
    chat = function() require("writing.assist").chat() end,
    clear = function()
      require("writing.grammar").clear()
      require("writing.rigor").store:clear()
    end,
  }
  api.nvim_create_user_command("Writing", function(o)
    local f = subs[o.args ~= "" and o.args or "grammar"]
    if not f then return vim.notify("Unknown :Writing " .. o.args, vim.log.levels.WARN) end
    f()
  end, {
    nargs = "?",
    complete = function() return vim.tbl_keys(subs) end,
    desc = "Writing companion (grammar, style, outline, rigor, rewrite, ask, chat, clear)",
  })
end

return M
