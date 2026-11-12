-- Telescope picker for the Markdown preview's page style (<leader>ps,
-- :MarkdownStyle). Moving the selection re-renders the open preview with that
-- style (nothing saved); <CR> keeps it for this file, <C-d> makes it the
-- default for every Markdown file, <Esc> puts the old style back. If no
-- preview is open for the buffer, choosing one opens it.

local M = {}

local SOURCE = {
  file = "set for this file",
  default = "the default for Markdown files",
  config = "config.markdown.style",
  trial = "being tried",
}

function M.pick(src)
  local ok = pcall(require, "telescope")
  if not ok then return vim.notify("Markdown style picker needs Telescope", vim.log.levels.ERROR) end
  local pickers, finders = require("telescope.pickers"), require("telescope.finders")
  local previewers, conf = require("telescope.previewers"), require("telescope.config").values
  local actions, action_state = require("telescope.actions"), require("telescope.actions.state")
  local md = require("pdfview.markdown")

  src = src or vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local original, origin = md.style(src)
  local prior_trial = origin == "trial" and original or nil
  local showing = md.current() and md.src == src

  local by_name, width = {}, 0
  for _, s in ipairs(md.styles) do
    by_name[s.name] = s
    width = math.max(width, #s.name)
  end

  -- The preview pane describes the style; selecting it also renders it in the
  -- open preview split, which is the real preview.
  local previewer = previewers.new_buffer_previewer({
    title = "Style",
    define_preview = function(self, entry)
      local s = by_name[entry.value]
      local lines = { s.name, "", s.desc, "" }
      if entry.value == original then lines[#lines + 1] = "Current: " .. SOURCE[origin] .. "." end
      lines[#lines + 1] = showing and "The preview split shows this style while it's selected."
        or "No preview is open for this buffer: choosing a style opens one."
      vim.list_extend(lines, { "", "<CR>   use for this file", "<C-d>  make the default for all Markdown files",
        "<Esc>  keep " .. original })
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      vim.bo[self.state.bufnr].filetype = "markdown"
      if showing then md.try_style(src, entry.value) end
    end,
  })

  local chosen = false
  local function choose(bufnr, scope)
    local entry = action_state.get_selected_entry()
    chosen = true
    actions.close(bufnr)
    if not entry then return md.try_style(src, prior_trial) end
    md.set_style(src, entry.value, scope)
    vim.notify(("Markdown style: %s%s"):format(entry.value, scope == "default" and " (default)" or ""))
    if not showing and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == src then
      vim.schedule(function()
        vim.api.nvim_set_current_win(win)
        md.view()
      end)
    end
  end

  local results = vim.tbl_map(function(s) return s.name end, md.styles)
  local start
  for i, name in ipairs(results) do
    if name == original then start = i end
  end

  pickers
    .new({}, {
      prompt_title = "Markdown style",
      default_selection_index = start,
      finder = finders.new_table({
        results = results,
        entry_maker = function(name)
          local mark = name == original and "●" or " "
          return {
            value = name,
            ordinal = name .. " " .. by_name[name].desc,
            display = ("%s %-" .. width .. "s  %s"):format(mark, name, by_name[name].desc),
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = previewer,
      attach_mappings = function(bufnr, map)
        actions.select_default:replace(function() choose(bufnr, "file") end)
        map({ "i", "n" }, "<C-d>", function() choose(bufnr, "default") end)
        actions.close:enhance({
          post = function()
            if not chosen then md.try_style(src, prior_trial) end
          end,
        })
        return true
      end,
    })
    :find()
end

return M
