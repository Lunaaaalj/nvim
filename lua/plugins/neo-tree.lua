return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-tree/nvim-web-devicons",
      -- Powers `open_with_window_picker` (`w`): letters pop up over each window
      -- and you press one to open the file there. Without this plugin neo-tree
      -- silently falls back to a plain open.
      {
        "s1n7ax/nvim-window-picker",
        version = "2.*",
        opts = {
          hint = "floating-big-letter",
          filter_rules = {
            include_current_win = false,
            autoselect_one = true, -- only one candidate → open there, no prompt
            bo = {
              filetype = { "neo-tree", "neo-tree-popup", "notify", "noice" },
              buftype = { "terminal", "quickfix" },
            },
          },
        },
      },
    },
    lazy = false,

    config = function()
      require("neo-tree").setup({
        close_if_last_window = true,
        popup_border_style = "rounded",
        enable_git_status = true,
        enable_diagnostics = true,

        -- "claude_chats.neotree" is a local custom source (lua/claude_chats/)
        -- listing running + recent Claude Code chats for the cwd.
        sources = { "filesystem", "buffers", "git_status", "claude_chats.neotree" },

        -- Tabs at the top of the tree to switch filesystem / buffers / git / claude views.
        source_selector = {
          winbar = true,
          statusline = false,
          content_layout = "center",
          sources = {
            { source = "filesystem", display_name = "  Files" },
            { source = "buffers", display_name = "  Bufs" },
            { source = "git_status", display_name = "  Git" },
            { source = "claude", display_name = " \u{f086} Claude" },
          },
        },

        default_component_configs = {
          -- Indent guides + fancy expander arrows.
          indent = {
            with_markers = true,
            indent_marker = "│",
            last_indent_marker = "└",
            with_expanders = true,
            expander_collapsed = "",
            expander_expanded = "",
          },
          -- Inline LSP diagnostics on files/folders.
          diagnostics = {
            symbols = {
              hint = "",
              info = "",
              warn = "",
              error = "",
            },
          },
          modified = { symbol = "●" },
          -- VSCode-style letter markers for git state. Plain letters are
          -- self-documenting (no guessing what a glyph means) and render in any
          -- font — unlike the nerd-font nf-md glyphs, which showed up as tofu
          -- boxes (the mysterious "red square") in this terminal's font variant.
          --   A added · M modified · D deleted · R renamed · U untracked
          --   I ignored · ✗ unstaged · ✓ staged · ! conflict
          git_status = {
            symbols = {
              added     = "A",
              modified  = "M",
              deleted   = "D",
              renamed   = "R",
              untracked = "U",
              ignored   = "I",
              unstaged  = "✗",
              staged    = "✓",
              conflict  = "!",
            },
          },
        },

        -- Global maps apply to ALL sources (filesystem/buffers/git_status), so only
        -- list commands that exist in every source here. Filesystem-only commands
        -- (toggle_hidden, system_open, copy_path_to_clipboard) live under
        -- `filesystem.window.mappings` below — mapping them globally warns for the
        -- Bufs/Git sources where those commands aren't defined.
        window = {
          width = 34,
          mappings = {
            ["P"] = { "toggle_preview", config = { use_float = true } },
            ["h"] = "close_node",
            ["l"] = "open",
            ["."] = "set_root",               -- make node the new tree root
            -- Open in another window. Neo-tree has these by default; listed
            -- here so they're discoverable and survive upstream default changes.
            ["w"] = "open_with_window_picker", -- pick an existing window by letter
            ["s"] = "open_vsplit",
            ["S"] = "open_split",
            ["t"] = "open_tabnew",
          },
        },

        filesystem = {
          -- Auto-reveal and highlight the file you're editing as you switch buffers.
          follow_current_file = { enabled = true, leave_dirs_open = false },
          use_libuv_file_watcher = true, -- live-refresh on external file changes
          hijack_netrw_behavior = "open_default",
          filtered_items = {
            visible = false, -- toggle with `H`
            hide_dotfiles = false,
            hide_gitignored = true,
            hide_by_name = { ".DS_Store", "thumbs.db", ".git" },
          },
          window = {
            mappings = {
              ["/"] = "fuzzy_finder",
              ["<bs>"] = "navigate_up",
              ["H"] = "toggle_hidden",
              ["O"] = "system_open",            -- open with default app (defined below)
              ["Y"] = "copy_path_to_clipboard", -- relative path (defined below)
            },
          },
          commands = {
            -- Open the node with the OS default application (macOS `open`).
            system_open = function(state)
              local node = state.tree:get_node()
              vim.fn.jobstart({ "open", node.path }, { detach = true })
            end,
            -- Copy the node's path (relative to cwd) to the system clipboard.
            -- Neo-tree has no built-in command of this name, so define our own.
            copy_path_to_clipboard = function(state)
              local node = state.tree:get_node()
              local path = vim.fn.fnamemodify(node.path, ":.")
              vim.fn.setreg("+", path)
              vim.notify("Copied: " .. path)
            end,
          },
        },

        buffers = {
          follow_current_file = { enabled = true },
        },

        -- git_status source view + a floating quick git-status popup (`gs`).
        git_status = {
          window = {
            mappings = {
              ["A"]  = "git_add_all",
              ["gu"] = "git_unstage_file",
              ["ga"] = "git_add_file",
              ["gr"] = "git_revert_file",
              ["gc"] = "git_commit",
              ["gp"] = "git_push",
              ["gg"] = "git_commit_and_push",
            },
          },
        },
      })
    end,
  },
}
