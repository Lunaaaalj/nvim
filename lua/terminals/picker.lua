-- Telescope picker over live terminals, previewing each one's scrollback.
--   <CR> open/focus   <C-r> rename   <C-x> kill   <C-n> new shell
local terms = require("terminals")

local M = {}

function M.pick(opts)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local previewers = require("telescope.previewers")
  local actions = require("telescope.actions")
  local state = require("telescope.actions.state")
  local conf = require("telescope.config").values

  local function finder()
    return finders.new_table({
      results = terms.list(),
      entry_maker = function(t)
        local label = ("%2d %s %s"):format(t.id, terms.glyphs[terms.state(t.id)], terms.label(t.id))
        local display = label .. "  " .. terms.detail(t.id)
        return { value = t, ordinal = display, display = display }
      end,
    })
  end

  local function selected(fn)
    return function(bufnr)
      local e = state.get_selected_entry()
      if e then fn(e.value, bufnr) end
    end
  end

  -- Re-open after an action that changes the list (rename/kill), keeping the
  -- prompt text.
  local function reopen(bufnr)
    local prompt = state.get_current_line()
    actions.close(bufnr)
    vim.schedule(function() M.pick({ default_text = prompt }) end)
  end

  pickers
    .new(opts or {}, {
      prompt_title = "Terminals",
      finder = finder(),
      sorter = conf.generic_sorter({}),
      previewer = previewers.new_buffer_previewer({
        title = "Output",
        define_preview = function(self, entry)
          local lines = vim.api.nvim_buf_get_lines(entry.value.bufnr, 0, -1, false)
          while #lines > 0 and lines[#lines]:match("^%s*$") do
            lines[#lines] = nil
          end
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
          if #lines > 0 then
            pcall(vim.api.nvim_win_set_cursor, self.state.winid, { #lines, 0 })
          end
        end,
      }),
      attach_mappings = function(bufnr, map)
        actions.select_default:replace(selected(function(t)
          actions.close(bufnr)
          terms.open(t.id)
        end))
        map({ "i", "n" }, "<C-r>", selected(function(t, b)
          actions.close(b)
          terms.rename(t.id)
        end))
        map({ "i", "n" }, "<C-x>", selected(function(t, b)
          terms.kill(t.id)
          reopen(b)
        end))
        map({ "i", "n" }, "<C-n>", function(b)
          actions.close(b)
          terms.new()
        end)
        return true
      end,
    })
    :find()
end

return M
