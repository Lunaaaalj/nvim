-- A docked output pane for Molten -- the RStudio console/plot pane, roughly.
--
-- Molten's own output is a floating window, which has two problems here: it
-- hovers over the code you're reading, and it inherits this config's global
-- transparency (`transparent_groups` strips NormalFloat, `winblend = 10`
-- blends it), so text bleeds through plots. Rather than styling the float into
-- submission, this puts the output somewhere it can simply live: a normal
-- window in the right-hand column, stacked above the REPL terminal when one is
-- open.
--
-- How it gets the content
--
--   Text: Molten only materialises a cell's output buffer when it renders its
--   float, so `refresh()` briefly shows the float, copies the buffer Molten
--   built, and closes it again. All three happen inside one callback, so
--   Neovim never redraws in between and the float is never visible.
--
--   Plots: Molten writes each figure to a temp PNG and hands the path to
--   image.nvim, binding the image to the *float's* window (see
--   `outputchunks.py:161` -- `add_image(..., bufnr, winnr)`). That binding is
--   why the plots don't follow the buffer into another window. So we ask
--   image.nvim for those image objects, take their `.path`, and render our own
--   copies bound to the pane's window instead. Those PNGs are flattened onto a
--   solid background first -- see `flatten()`.
--
-- Nothing here runs on a hot path: no autocmds on cursor movement, no timers
-- except a short, self-terminating one after an evaluation (output arrives
-- asynchronously, so the pane has to look again a few times before it settles).

local M = {}

local state = {
    buf = nil,
    win = nil,
    images = {},
    timer = nil,
    drawn = nil, -- what render_images last drew, so a resize can redraw it
    src = nil, -- window holding the notebook, so grabs run in the right context
}

local function has_image_nvim()
    return package.loaded["image"] ~= nil or pcall(require, "image")
end

--------------------------------------------------------------------------------
-- Buffer / window
--------------------------------------------------------------------------------

local function ensure_buf()
    if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
        return state.buf
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "molten_pane"
    pcall(vim.api.nvim_buf_set_name, buf, "molten://output")
    state.buf = buf
    return buf
end

-- The REPL terminals (<leader>tR / <leader>tp / <leader>tN) open as vertical
-- toggleterm splits on the right. If one is up, the pane joins that column
-- above it, so code | (output / REPL) reads like an IDE. Otherwise the pane
-- opens its own right-hand column.
local function repl_win()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
            return win
        end
    end
end

function M.is_open()
    return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

-- MoltenShowOutput reads the *current* window's buffer and cursor, so a refresh
-- that runs from the pane (or from the REPL terminal, once you click into it)
-- finds no cell and fails. Remember the window the code is in and do the grab
-- from there instead.
local function remember_source()
    local win = vim.api.nvim_get_current_win()
    if win == state.win then
        return
    end
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype ~= "" then
        return -- terminal, quickfix, another scratch pane: not a notebook
    end
    state.src = win
end

function M.open(focus)
    remember_source()
    local buf = ensure_buf()
    if not M.is_open() then
        local prev = vim.api.nvim_get_current_win()
        local term = repl_win()
        if term then
            vim.api.nvim_set_current_win(term)
            vim.cmd("aboveleft split")
            vim.cmd("resize " .. math.max(10, math.floor(vim.o.lines * 0.5)))
        else
            vim.cmd("botright vsplit")
            vim.cmd("vertical resize " .. math.max(40, math.floor(vim.o.columns * 0.42)))
        end
        state.win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(state.win, buf)
        local wo = vim.wo[state.win]
        wo.number = false
        wo.relativenumber = false
        wo.signcolumn = "no"
        wo.wrap = true
        wo.winfixwidth = true
        wo.cursorline = false
        -- The pane blends with the rest of the editor: MoltenPaneNormal links
        -- to Normal, which this config keeps background-less so the terminal's
        -- colour and opacity show through. Plots get their own background baked
        -- into the PNG instead (see `flatten()`), so the window doesn't need
        -- one. Mapping NormalNC too keeps it from dimming when unfocused;
        -- override the group to give the pane a distinct surface.
        wo.winhighlight = "Normal:MoltenPaneNormal,NormalNC:MoltenPaneNormal"
        if not focus then
            vim.api.nvim_set_current_win(prev)
        end
    elseif focus then
        vim.api.nvim_set_current_win(state.win)
    end
    return state.win
end

function M.close()
    M.clear_images()
    if M.is_open() then
        vim.api.nvim_win_close(state.win, true)
    end
    state.win = nil
end

function M.toggle()
    if M.is_open() then
        M.close()
    else
        M.open(false)
        M.refresh()
    end
end

--------------------------------------------------------------------------------
-- Images
--------------------------------------------------------------------------------

function M.clear_images()
    for _, img in ipairs(state.images) do
        pcall(function()
            img:clear()
        end)
    end
    state.images = {}
end

-- Matplotlib's Jupyter backend saves figures with a transparent facecolor
-- (ipykernel sets `figure.facecolor` to (1,1,1,0)), and the Kitty graphics
-- protocol composites over whatever is already on screen -- so a plot drawn on
-- a transparent terminal is dark axes on your wallpaper. Flatten the PNG onto
-- a solid background first.
--
-- ImageMagick does this in ~20ms and is already a hard dependency of
-- image.nvim's default `magick_cli` processor, so there is nothing new to
-- install. If it is missing we render the original and the plot is merely as
-- unreadable as before, never broken.
M.plot_background = "#ffffff"

local flat = {} -- original PNG -> flattened PNG (or itself, if flattening is unavailable)

local function flatten(path, cb)
    if flat[path] then
        return cb(flat[path])
    end
    if vim.fn.executable("magick") == 0 then
        flat[path] = path
        return cb(path)
    end
    local dir = vim.fn.stdpath("cache") .. "/molten_pane"
    vim.fn.mkdir(dir, "p")
    -- Molten writes one uniquely-named temp file per figure, so the basename is
    -- already a safe cache key.
    local dst = ("%s/%s-%s.png"):format(dir, vim.fn.fnamemodify(path, ":t:r"), M.plot_background:gsub("#", ""))
    if vim.uv.fs_stat(dst) then
        flat[path] = dst
        return cb(dst)
    end
    local ok = pcall(
        vim.system,
        { "magick", path, "-background", M.plot_background, "-alpha", "remove", "-alpha", "off", dst },
        {},
        function(res)
            local out = (res.code == 0 and vim.uv.fs_stat(dst)) and dst or path
            flat[path] = out
            vim.schedule(function()
                cb(out)
            end)
        end
    )
    if not ok then
        flat[path] = path
        cb(path)
    end
end

-- image.nvim only honours `width`/`height` per image -- the `max_width` /
-- `max_height` options it takes at setup are global and apply to every image
-- (`renderer.lua:203`), which is why plots came out capped at 12 rows. So opt
-- out of the global caps and compute the fit against the pane ourselves.
local function fit(img, avail_cols, avail_rows)
    local ok, u = pcall(require, "image/utils")
    local size = ok and u.term and u.term.get_size and u.term.get_size() or nil
    if not (size and size.cell_width and size.cell_width > 0 and size.cell_height > 0) then
        return avail_cols, nil -- width only; image.nvim infers height from the aspect ratio
    end
    local cols = img.image_width / size.cell_width
    local rows = img.image_height / size.cell_height
    -- Scale to fill the pane, up as well as down: a 640x480 figure in a narrow
    -- column is unreadable at its natural size.
    local scale = math.min(avail_cols / cols, avail_rows / rows)
    return math.max(1, math.floor(cols * scale)), math.max(1, math.floor(rows * scale))
end

-- Make our own image.nvim objects for Molten's figures so they belong to this
-- window rather than the float's.
local function draw(paths, first_row)
    local ok, image = pcall(require, "image")
    if not ok or not M.is_open() then
        return
    end
    M.clear_images()
    local win = state.win
    local avail_cols = math.max(10, vim.api.nvim_win_get_width(win) - 1)
    local avail_rows = math.max(5, vim.api.nvim_win_get_height(win) - 2)
    local row = first_row
    for _, path in ipairs(paths) do
        local made, img = pcall(image.from_file, flat[path] or path, {
            window = win,
            buffer = state.buf,
            with_virtual_padding = true,
            x = 0,
            y = row,
        })
        if made and img then
            img.ignore_global_max_size = true -- set here: from_file drops it
            local w, h = fit(img, avail_cols, avail_rows)
            pcall(function()
                img:render({ x = 0, y = row, width = w, height = h })
            end)
            state.images[#state.images + 1] = img
            local drawn = 0
            pcall(function()
                drawn = img.rendered_geometry and img.rendered_geometry.height or 0
            end)
            row = row + math.max(drawn, 1) + 1
        end
    end
    state.drawn = { paths = paths, row = first_row, w = avail_cols, h = avail_rows }
end

-- Flattening is async, so a refresh that arrives while one is in flight must
-- not have its result drawn over. `generation` makes the stale callback a no-op.
local generation = 0

local function render_images(paths, first_row)
    generation = generation + 1
    state.drawn = nil
    if #paths == 0 or not has_image_nvim() then
        return
    end
    local gen = generation
    local pending = 0
    for _, path in ipairs(paths) do
        if flat[path] == nil then
            pending = pending + 1
        end
    end
    if pending == 0 then
        return draw(paths, first_row)
    end
    for _, path in ipairs(paths) do
        if flat[path] == nil then
            flatten(path, function()
                pending = pending - 1
                if pending == 0 and gen == generation then
                    draw(paths, first_row)
                end
            end)
        end
    end
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

-- Ask Molten to build the current cell's output, and read what it built.
-- Returns lines, image paths. The float is opened and closed within this
-- function; because no redraw happens in between, it never becomes visible.
local function grab_here()
    if vim.fn.exists(":MoltenShowOutput") ~= 2 then
        return nil
    end
    if not pcall(vim.cmd, "noautocmd MoltenShowOutput") then
        return nil
    end

    local obuf
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local b = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(b) and vim.bo[b].filetype == "molten_output" then
            obuf = b
            break
        end
    end

    local lines, paths = {}, {}
    if obuf then
        lines = vim.api.nvim_buf_get_lines(obuf, 0, -1, false)
        if has_image_nvim() then
            local ok, image = pcall(require, "image")
            if ok then
                local got, imgs = pcall(image.get_images, { buffer = obuf })
                if got and imgs then
                    for _, img in ipairs(imgs) do
                        if img.path then
                            paths[#paths + 1] = img.path
                        end
                    end
                end
            end
        end
    end

    pcall(vim.cmd, "noautocmd MoltenHideOutput")
    return lines, paths
end

-- Same, but evaluated in the notebook's window (see `remember_source`), so the
-- pane keeps updating while you sit in the REPL below it.
local function grab()
    local src = state.src
    if src and src ~= state.win and vim.api.nvim_win_is_valid(src) then
        local ok, res = pcall(vim.api.nvim_win_call, src, function()
            local lines, paths = grab_here()
            return { lines, paths }
        end)
        if ok and res then
            return res[1], res[2]
        end
        return nil
    end
    return grab_here()
end

-- Molten writes the cell's state into the output header (outputbuffer.py:50):
-- "* On Hold", "... Running", "✓ Done", "✗ Failed". That is a far better
-- signal than guessing when output has settled, so `follow()` polls on it.
local function is_pending(lines)
    for _, line in ipairs(lines) do
        if line:find("On Hold", 1, true) or line:find("Running", 1, true) then
            return true
        end
        if line:find("Done", 1, true) or line:find("Failed", 1, true) then
            return false
        end
    end
    -- No header yet: the cell hasn't produced anything, so keep looking.
    return #lines == 0
end

-- Returns whether the cell is still pending, so `follow()` knows to look again.
function M.refresh()
    if not M.is_open() then
        return nil
    end
    local lines, paths = grab()
    if lines == nil then
        return nil
    end
    local pending = is_pending(lines)

    -- Drop trailing blanks so the plots sit right under the text.
    while #lines > 0 and lines[#lines]:match("^%s*$") do
        table.remove(lines)
    end

    M.clear_images()
    local body = vim.list_extend({}, lines)
    if #body == 0 then
        body = { "-- no output --" }
    end
    -- image.nvim needs real lines under the images to hang virtual padding on.
    local image_row = #body + 1
    if #paths > 0 then
        body[#body + 1] = ""
        for _ = 1, #paths do
            body[#body + 1] = ""
        end
    end

    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, body)
    vim.bo[state.buf].modifiable = false

    render_images(paths, image_row)
    return pending
end

local function stop_timer()
    if state.timer then
        state.timer:stop()
        if not state.timer:is_closing() then
            state.timer:close()
        end
        state.timer = nil
    end
end

-- Cell output arrives asynchronously, so one refresh right after an evaluation
-- would only ever catch "On Hold". Poll until Molten reports the cell Done or
-- Failed, then stop.
--
-- This is the only repeating work in the file, and it exists only while a cell
-- is actually pending: it stops on the first settled reading, if the pane is
-- closed, or at a hard cap (a kernel that never becomes ready would otherwise
-- leave it polling forever).
local POLL_MS = 500
local POLL_CAP = 240 -- 2 minutes

function M.follow()
    stop_timer()
    remember_source()
    M.open(false)
    -- Only `true` means "pending". `false` is settled and `nil` means Molten
    -- has nothing to show (no kernel attached, command unavailable) -- neither
    -- is worth polling for.
    if M.refresh() ~= true then
        return
    end

    local ticks = 0
    state.timer = vim.uv.new_timer()
    state.timer:start(POLL_MS, POLL_MS, function()
        vim.schedule(function()
            ticks = ticks + 1
            if not M.is_open() or ticks > POLL_CAP or M.refresh() ~= true then
                stop_timer()
            end
        end)
    end)
end

--------------------------------------------------------------------------------
-- Highlight
--------------------------------------------------------------------------------

-- Defined as its own group, but transparent by default: the pane should look
-- like every other window in this config. Re-applied on ColorScheme because
-- schemes clear user groups.
local function sync_hl()
    vim.api.nvim_set_hl(0, "MoltenPaneNormal", { link = "Normal" })
end

vim.api.nvim_create_autocmd("ColorScheme", { callback = sync_hl })
sync_hl()

--------------------------------------------------------------------------------
-- Keeping the right-hand column a single column
--------------------------------------------------------------------------------

-- The REPL terminals are toggleterm vertical splits, so opening one while the
-- pane is up gives three side-by-side columns instead of stacking. Move the
-- terminal under the pane instead -- `win_splitmove()` relocates the window
-- without closing it, so toggleterm's handle stays valid.
--
-- Full-width terminals are left alone: <leader>th asks for a horizontal panel
-- and should get one.
local function dock_terminal(win)
    if not M.is_open() or win == state.win or not vim.api.nvim_win_is_valid(win) then
        return
    end
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative ~= nil and cfg.relative ~= "" then
        return -- floating terminal (<leader>tf)
    end
    if vim.api.nvim_win_get_width(win) >= vim.o.columns then
        return
    end
    local pane_pos = vim.api.nvim_win_get_position(state.win)
    local term_pos = vim.api.nvim_win_get_position(win)
    if term_pos[2] == pane_pos[2] and term_pos[1] > pane_pos[1] then
        return -- already stacked below the pane
    end
    if pcall(vim.fn.win_splitmove, win, state.win, { vertical = false, rightbelow = true }) then
        pcall(vim.api.nvim_win_set_height, state.win, math.max(8, math.floor(vim.o.lines * 0.5)))
    end
end

-- Both events are needed: toggleterm puts a plain scratch buffer in the window
-- and only then calls termopen(), so at BufWinEnter the buffer is not a
-- terminal yet (TermOpen catches the first open). Re-showing an existing
-- terminal buffer skips TermOpen entirely (BufWinEnter catches the toggles).
vim.api.nvim_create_autocmd({ "TermOpen", "BufWinEnter" }, {
    callback = function(ev)
        if ev.event == "BufWinEnter" and vim.bo[ev.buf].buftype ~= "terminal" then
            return
        end
        local win = vim.api.nvim_get_current_win()
        if vim.api.nvim_win_get_buf(win) ~= ev.buf then
            win = nil
            for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                if vim.api.nvim_win_get_buf(w) == ev.buf then
                    win = w
                    break
                end
            end
        end
        -- Deferred: toggleterm is still sizing and positioning the window.
        if win then
            vim.schedule(function()
                dock_terminal(win)
            end)
        end
    end,
})

-- Images are sized to the pane, so a resize needs a redraw -- but only when the
-- pane's own dimensions actually changed, since WinResized fires for any split.
vim.api.nvim_create_autocmd("WinResized", {
    callback = function()
        local drawn = state.drawn
        if not drawn or not M.is_open() then
            return
        end
        local w = math.max(10, vim.api.nvim_win_get_width(state.win) - 1)
        local h = math.max(5, vim.api.nvim_win_get_height(state.win) - 2)
        if w ~= drawn.w or h ~= drawn.h then
            draw(drawn.paths, drawn.row)
        end
    end,
})

return M
