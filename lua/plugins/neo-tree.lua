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
      -- Every tree colour is derived from the active scheme (defaults/colors.lua),
      -- never hardcoded. Hierarchy comes from weight and recession, not hue:
      -- directories bold, files plain, guides/dotfiles/ignored faint, and the
      -- accent reserved for the file open in an editor. Set on every
      -- ColorScheme; neo-tree's own defaults only fill groups that are still
      -- undefined, so these win. The ui_toggle toggles reload the scheme, so
      -- they recompute on dark/light and transparent/solid flips too.
      local function highlights()
        local colors = require("defaults.colors")
        local set = function(name, def) vim.api.nvim_set_hl(0, name, def) end
        local normal = colors.fg("Normal") or 0xc0c0c0
        local muted = colors.fg("Comment") or normal
        local accent = colors.accent() or normal
        local faint = colors.fg("NonText", "Comment") or muted

        -- What the faint tints are blended toward: the colour actually behind
        -- the tree (the terminal's in transparent mode, Normal's in solid).
        local base
        if vim.o.background == "light" then
          base = 0xffffff
        elseif vim.g.ui_transparent then
          base = tonumber(colors.terminal_bg:sub(2), 16)
        else
          base = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg or tonumber(colors.terminal_bg:sub(2), 16)
        end

        -- Source tabs: no bg, muted inactive icons, accent + underline on the active one.
        set("NeoTreeTabInactive", { fg = muted })
        set("NeoTreeTabActive", { fg = accent, bold = true, underline = true, sp = accent })
        set("NeoTreeTabSeparatorInactive", { fg = muted })
        set("NeoTreeTabSeparatorActive", { fg = muted })

        -- Names and icons.
        set("NeoTreeDirectoryName", { fg = normal, bold = true })
        set("NeoTreeFileName", { fg = normal })
        set("NeoTreeDirectoryIcon", { fg = colors.blend(accent, base, 0.75) })
        set("NeoTreeRootName", { fg = muted, bold = true })
        set("NeoTreeFileNameOpened", { fg = accent })
        set("NeoTreeModified", { fg = accent })
        set("NeoTreeFilterTerm", { fg = accent, bold = true })

        -- Things that recede.
        set("NeoTreeIndentMarker", { fg = colors.blend(normal, base, 0.18) })
        set("NeoTreeExpander", { fg = muted })
        for _, name in ipairs({ "NeoTreeDotfile", "NeoTreeHiddenByName", "NeoTreeDimText", "NeoTreeMessage" }) do
          set(name, { fg = muted })
        end
        set("NeoTreeIgnored", { fg = faint })
        set("NeoTreeGitIgnored", { fg = faint })

        -- Git: the scheme's own add/change/delete colours, so the tree agrees
        -- with gitsigns and diffs. First defined foreground wins.
        local added = colors.fg("GitSignsAdd", "Added", "DiagnosticOk")
        local changed = colors.fg("GitSignsChange", "Changed", "DiagnosticWarn")
        local removed = colors.fg("GitSignsDelete", "Removed", "DiagnosticError")
        set("NeoTreeGitAdded", { fg = added })
        set("NeoTreeGitStaged", { fg = added })
        set("NeoTreeGitUntracked", { fg = added, italic = true })
        set("NeoTreeGitModified", { fg = changed })
        set("NeoTreeGitUnstaged", { fg = changed })
        set("NeoTreeGitDeleted", { fg = removed })
        set("NeoTreeGitRenamed", { fg = colors.fg("Special") or accent })
        set("NeoTreeGitConflict", { fg = colors.fg("DiagnosticError") or removed, bold = true })

        -- Selection. cursorline.lua blanks CursorLine in transparent mode
        -- (number-only style), which left the tree with no visible selection,
        -- so the tree gets its own faint band. Solid mode keeps the scheme's.
        local band
        if vim.g.ui_transparent then
          band = colors.blend(normal, base, 0.08)
        else
          band = vim.api.nvim_get_hl(0, { name = "CursorLine", link = false }).bg or colors.blend(normal, base, 0.08)
        end
        set("NeoTreeCursorLine", { bg = band, bold = true })
      end
      highlights()
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("NeoTreeTabs", { clear = true }),
        callback = highlights,
      })

      -- Directories first, then natural order of the lowercased basename
      -- (file2 < file10). The `o*` order-by commands still override this.
      local function natural_lt(x, y)
        local i, j = 1, 1
        while i <= #x and j <= #y do
          local dx, dy = x:match("^%d+", i), y:match("^%d+", j)
          if dx and dy then
            local nx, ny = tonumber(dx), tonumber(dy)
            if nx ~= ny then return nx < ny end
            if #dx ~= #dy then return #dx < #dy end
            i, j = i + #dx, j + #dy
          else
            local cx, cy = x:sub(i, i), y:sub(j, j)
            if cx ~= cy then return cx < cy end
            i, j = i + 1, j + 1
          end
        end
        return (#x - i) < (#y - j)
      end
      local function natural_sort(a, b)
        if a.type ~= b.type then return a.type == "directory" end
        local x, y = vim.fs.basename(a.path):lower(), vim.fs.basename(b.path):lower()
        if x == y then return a.path < b.path end
        return natural_lt(x, y)
      end

      -- The directory a node stands for: itself if it is one, else its parent.
      local function node_dir(state)
        local node = state.tree:get_node()
        return node.type == "directory" and node.path or vim.fn.fnamemodify(node.path, ":h")
      end

      -- Telescope scoped to the node's directory. Step back to the previous
      -- window first so the chosen file opens in the editor, not in the tree.
      local function scoped_picker(builtin, title)
        return function(state)
          local dir = node_dir(state)
          vim.cmd("wincmd p")
          require("telescope.builtin")[builtin]({
            cwd = dir,
            prompt_title = title .. vim.fn.fnamemodify(dir, ":~:."),
          })
        end
      end

      require("neo-tree").setup({
        close_if_last_window = true,
        popup_border_style = "rounded",
        enable_git_status = true,
        enable_diagnostics = true,
        sort_case_insensitive = true,
        sort_function = natural_sort,

        -- The window inherits 'cursorlineopt' from the editor window it was
        -- split from, and cursorline.lua sets "number" there in transparent
        -- mode, which would hide the selection band entirely (cursorline.lua
        -- leaves neo-tree alone, so the tree pins its own).
        event_handlers = {
          {
            event = "neo_tree_buffer_enter",
            handler = function() vim.opt_local.cursorlineopt = "line" end,
          },
        },

        -- Local custom sources: "claude_chats.neotree" (lua/claude_chats/) lists
        -- running + recent Claude Code chats for the cwd; "terminals.neotree"
        -- (lua/terminals/) lists shells and REPLs with their live state.
        sources = { "filesystem", "buffers", "git_status", "claude_chats.neotree", "terminals.neotree" },

        -- Icon-only tabs at the top of the tree (filesystem / buffers / git /
        -- claude / terminals), evenly spread over the 34 cols; the active source's name is
        -- shown in the bufferline offset instead. Defined in lua/neotree_tabs.lua.
        source_selector = {
          winbar = true,
          statusline = false,
          tabs_layout = "equal",
          content_layout = "center",
          separator = { left = "", right = "" }, -- no ▏▕ chrome; spacing does the work
          sources = require("neotree_tabs").selector(),
        },

        -- Glyphs are \u{} escapes on purpose (literal Nerd Font glyphs were
        -- silently stripped to "" in this file once, leaving no expander
        -- arrows and no diagnostic icons) and BMP-only: neo-tree's default
        -- folder_empty* icons are nf-md (U+F0001+), which render as tofu in
        -- this terminal's font.
        default_component_configs = {
          -- Indent guides + expander chevrons.
          indent = {
            with_markers = true,
            indent_marker = "│",
            last_indent_marker = "└",
            with_expanders = true,
            expander_collapsed = "\u{f460}", -- nf-oct-chevron_right
            expander_expanded = "\u{f47c}",  -- nf-oct-chevron_down
          },
          icon = {
            folder_closed = "\u{f07b}",      -- nf-fa-folder
            folder_open = "\u{f07c}",        -- nf-fa-folder_open
            folder_empty = "\u{f114}",       -- nf-fa-folder_o
            folder_empty_open = "\u{f115}",  -- nf-fa-folder_open_o
          },
          -- Colour the file that is open in an editor (needs enable_opened_markers, on by default).
          name = { highlight_opened_files = true },
          -- Inline LSP diagnostics on files/folders.
          diagnostics = {
            symbols = {
              hint = "\u{f0eb}",  -- nf-fa-lightbulb_o
              info = "\u{f05a}",  -- nf-fa-info_circle
              warn = "\u{f071}",  -- nf-fa-warning
              error = "\u{f057}", -- nf-fa-times_circle
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
          -- Collapse single-child chains (lua/foo/bar) into one row. Needs the
          -- deep scan to know a folder has exactly one child up front.
          group_empty_dirs = true,
          scan_mode = "deep",
          -- Git state in the Files tab is the name's colour, not a letter; a
          -- collapsed folder gets one dot in the colour of its worst state.
          -- (The Git and Buffers tabs keep the letters: there staged vs
          -- unstaged is the point.) These are neo-tree's default renderers
          -- minus the file-level git_status component.
          renderers = {
            directory = {
              { "indent" },
              { "icon" },
              { "current_filter" },
              {
                "container",
                content = {
                  { "name", zindex = 10 },
                  { "symlink_target", zindex = 10, highlight = "NeoTreeSymbolicLinkTarget" },
                  { "clipboard", zindex = 10 },
                  { "diagnostics", errors_only = true, zindex = 20, align = "right", hide_when_expanded = true },
                  {
                    "git_status",
                    zindex = 10,
                    align = "right",
                    hide_when_expanded = true,
                    symbols = {
                      added = "•", modified = "•", deleted = "•", renamed = "•", untracked = "•",
                      ignored = "", unstaged = "•", staged = "•", conflict = "•",
                    },
                  },
                  { "file_size", zindex = 10, align = "right" },
                  { "type", zindex = 10, align = "right" },
                  { "last_modified", zindex = 10, align = "right" },
                  { "created", zindex = 10, align = "right" },
                },
              },
            },
            file = {
              { "indent" },
              { "icon" },
              {
                "container",
                content = {
                  { "name", zindex = 10 },
                  { "symlink_target", zindex = 10, highlight = "NeoTreeSymbolicLinkTarget" },
                  { "clipboard", zindex = 10 },
                  { "bufnr", zindex = 10 },
                  { "modified", zindex = 20, align = "right" },
                  { "diagnostics", zindex = 20, align = "right" },
                  { "file_size", zindex = 10, align = "right" },
                  { "type", zindex = 10, align = "right" },
                  { "last_modified", zindex = 10, align = "right" },
                  { "created", zindex = 10, align = "right" },
                },
              },
            },
          },
          window = {
            mappings = {
              ["/"] = "fuzzy_finder",
              ["<bs>"] = "navigate_up",
              ["H"] = "toggle_hidden",
              ["O"] = "system_open",       -- open with default app
              ["gO"] = "reveal_in_finder", -- show in Finder
              ["Y"] = "copy_path_menu",    -- pick which form of the path to copy
              ["F"] = "find_in_dir",       -- Telescope files inside this node's directory
              ["g/"] = "grep_in_dir",      -- Telescope live grep inside it
            },
          },
          commands = {
            -- Open the node with the OS default application (macOS `open`).
            system_open = function(state)
              local node = state.tree:get_node()
              vim.fn.jobstart({ "open", node.path }, { detach = true })
            end,
            -- Reveal the node in Finder (selected, rather than opened).
            reveal_in_finder = function(state)
              local node = state.tree:get_node()
              vim.fn.jobstart({ "open", "-R", node.path }, { detach = true })
            end,
            -- Copy the node's path in the form you pick. Neo-tree has no
            -- built-in command of this name, so define our own.
            copy_path_menu = function(state)
              local path = state.tree:get_node().path
              local forms = {
                { "Filename", vim.fn.fnamemodify(path, ":t") },
                { "Relative to cwd", vim.fn.fnamemodify(path, ":.") },
                { "Relative to ~", vim.fn.fnamemodify(path, ":~") },
                { "Absolute", path },
                { "Parent directory", vim.fn.fnamemodify(path, ":h") },
              }
              vim.ui.select(forms, {
                prompt = "Copy path",
                format_item = function(f) return string.format("%-16s %s", f[1], f[2]) end,
              }, function(choice)
                if not choice then return end
                vim.fn.setreg("+", choice[2])
                vim.notify("Copied: " .. choice[2])
              end)
            end,
            find_in_dir = scoped_picker("find_files", "Files in "),
            grep_in_dir = scoped_picker("live_grep", "Grep in "),
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
