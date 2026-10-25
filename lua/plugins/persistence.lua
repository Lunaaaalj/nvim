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
    -- sessionoption actually persists them (that's the rule mksession applies),
    -- and must be strings/numbers — hence the terminal list as JSON.
    vim.api.nvim_create_autocmd("User", {
      pattern = "PersistenceSavePre",
      callback = function()
        local claude_open = false
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "terminal" then
            -- only count panels that are actually visible in a window
            if #vim.fn.win_findbuf(buf) > 0 and vim.api.nvim_buf_get_name(buf):lower():match("claude") then
              claude_open = true
            end
          end
        end
        vim.g.Session_claude_open = claude_open and 1 or 0
        vim.g.Session_terminals = vim.json.encode(require("terminals").session_state())
      end,
    })

    -- After a session loads, re-launch the panels that were open. These spawn
    -- fresh processes: every terminal comes back in its last directory with its
    -- name, and `--continue` makes Claude resume its prior conversation in this
    -- directory, which is the closest thing to "restoring" the session.
    vim.api.nvim_create_autocmd("User", {
      pattern = "PersistenceLoadPost",
      callback = function()
        vim.defer_fn(function()
          local ok, list = pcall(vim.json.decode, vim.g.Session_terminals or "[]")
          if ok and type(list) == "table" then
            require("terminals").session_restore(list)
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
