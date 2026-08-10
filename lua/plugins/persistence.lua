return {
  "folke/persistence.nvim",
  event = "BufReadPre",
  opts = {},
  -- Runs at startup regardless of lazy-loading: tune what the session file stores.
  init = function()
    -- Plugin-managed terminals (toggleterm, Claude-via-snacks) don't round-trip
    -- through :mksession — they restore as dead buffers with stale output. Drop
    -- `terminal` so we don't get those, and instead re-launch the panels fresh on
    -- restore (see the autocmds below). `globals` lets the session file carry the
    -- small markers we set to remember which panels were open.
    vim.opt.sessionoptions:remove("terminal")
    vim.opt.sessionoptions:append("globals")
  end,
  config = function(_, opts)
    require("persistence").setup(opts)

    -- Before the session is written, record which auxiliary panels are open.
    -- Marker names start uppercase + contain a lowercase letter so the `globals`
    -- sessionoption actually persists them (that's the rule mksession applies).
    vim.api.nvim_create_autocmd("User", {
      pattern = "PersistenceSavePre",
      callback = function()
        local claude_open, term_open = false, false
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "terminal" then
            local name = vim.api.nvim_buf_get_name(buf)
            -- only count panels that are actually visible in a window
            local visible = #vim.fn.win_findbuf(buf) > 0
            if visible and name:lower():match("claude") then
              claude_open = true
            elseif visible and name:match("toggleterm") then
              term_open = true
            end
          end
        end
        vim.g.Session_claude_open = claude_open and 1 or 0
        vim.g.Session_term_open = term_open and 1 or 0
      end,
    })

    -- After a session loads, re-launch the panels that were open. These spawn
    -- fresh processes; `--continue` makes Claude resume its prior conversation in
    -- this directory, which is the closest thing to "restoring" the session.
    vim.api.nvim_create_autocmd("User", {
      pattern = "PersistenceLoadPost",
      callback = function()
        vim.defer_fn(function()
          if vim.g.Session_term_open == 1 then
            pcall(vim.cmd, "ToggleTerm direction=vertical size=80")
          end
          if vim.g.Session_claude_open == 1 then
            pcall(vim.cmd, "ClaudeCode --continue")
          end
        end, 100) -- let the restored layout settle first
      end,
    })
  end,
  keys = {
    { "<leader>qs", function() require("persistence").load() end, desc = "Session: restore (cwd)" },
    { "<leader>ql", function() require("persistence").load({ last = true }) end, desc = "Session: restore last" },
    { "<leader>qS", function() require("persistence").select() end, desc = "Session: select" },
    { "<leader>qd", function() require("persistence").stop() end, desc = "Session: don't save on exit" },
  },
}
