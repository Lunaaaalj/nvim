return {
  "coder/claudecode.nvim",
  dependencies = { "folke/snacks.nvim" },
  opts = {
    terminal = {
      split_side = "right",
      split_width_percentage = 0.4,
      provider = "snacks", -- snacks gives a nicer managed terminal than native
      auto_close = true,
    },
    diff_opts = {
      auto_close_on_accept = true,
      vertical_split = true, -- review Claude's edits in a vertical diff
    },
  },
  keys = {
    { "<leader>a", nil, desc = "AI/Claude Code" },
    { "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude" },
    { "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "Focus Claude" },
    { "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "Resume Claude" },
    { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude" },
    -- Chats as regular buffers (lua/claude_chats/): any number at once, in the
    -- current window, still IDE-connected. Listed in neo-tree's Claude tab.
    { "<leader>an", function() require("claude_chats").new() end, desc = "New Claude chat (buffer)" },
    { "<leader>aR", function() require("claude_chats").pick() end, desc = "Resume Claude chat (buffer)" },
    { "<leader>al", "<cmd>Neotree claude<cr>", desc = "List Claude chats (neo-tree)" },
    { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Select Claude model" },
    { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add current buffer to context" },
    { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send selection to Claude" },
    {
      "<leader>as",
      "<cmd>ClaudeCodeTreeAdd<cr>",
      desc = "Add file to context",
      ft = { "neo-tree", "oil", "minifiles" },
    },
    -- Diff review: accept / reject Claude's proposed edits
    { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept Claude diff" },
    { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Reject Claude diff" },
  },
}
