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
local function draw(anchors)
    local ok, image = pcall(require, "image")
    if not ok or not M.is_open() then
        return
    end
    M.clear_images()
    local win = state.win
    local avail_cols = math.max(10, vim.api.nvim_win_get_width(win) - 1)
    local avail_rows = math.max(5, vim.api.nvim_win_get_height(win) - 2)
    for _, anchor in ipairs(anchors) do
        local path = flat[anchor.path] or anchor.path
        local made, img = pcall(image.from_file, path, {
            window = win,
            buffer = state.buf,
            with_virtual_padding = true,
            x = 0,
            y = anchor.row,
        })
        if made and img then
            img.ignore_global_max_size = true -- set here: from_file drops it
            local w, h = fit(img, avail_cols, avail_rows)
            pcall(function()
                img:render({ x = 0, y = anchor.row, width = w, height = h })
            end)
            state.images[#state.images + 1] = img
        end
    end
    state.drawn = { anchors = anchors, w = avail_cols, h = avail_rows }
end

-- Flattening is async, so a refresh that arrives while one is in flight must
-- not have its result drawn over. `generation` makes the stale callback a no-op.
local generation = 0

-- Re-rendering an image is not free (~6ms each) and makes the plot visibly
-- blink, yet most refreshes -- every poll while a cell runs -- only change the
-- elapsed time in one header and leave the plots exactly where they were. Skip
-- the redraw when neither the images nor the buffer under them moved.
--
-- `first_changed` is the first buffer line `set_body` rewrote: images at or
-- below it lost the extmark holding their virtual padding and must be redrawn,
-- images above it are untouched.
local function anchors_match(a, b, first_changed)
    if not b or #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i].path ~= b[i].path or a[i].row ~= b[i].row then
            return false
        end
        if first_changed and a[i].row >= first_changed then
            return false
        end
    end
    return true
end

local function render_images(anchors, first_changed)
    if state.drawn and anchors_match(anchors, state.drawn.anchors, first_changed) then
        return -- nothing moved
    end
    generation = generation + 1
    state.drawn = nil
    if #anchors == 0 or not has_image_nvim() then
        M.clear_images()
        return
    end
    local gen = generation
    local pending = 0
    for _, anchor in ipairs(anchors) do
        if flat[anchor.path] == nil then
            pending = pending + 1
        end
    end
    if pending == 0 then
        return draw(anchors)
    end
    for _, anchor in ipairs(anchors) do
        if flat[anchor.path] == nil then
            flatten(anchor.path, function()
                pending = pending - 1
                if pending == 0 and gen == generation then
                    draw(anchors)
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
    -- Nothing at all. Molten doesn't build the output buffer until a cell has
    -- produced something, so this is a cell that is queued behind another and
    -- hasn't started -- exactly the case worth waiting for. (Under `<leader>ra`
    -- the tail of the notebook reads like this for as long as the kernel takes
    -- to get there.)
    return #lines == 0
end

-- Set to false to show only the cell under the cursor, as this pane originally
-- did.
M.all_cells = true

local MAX_CELLS = 200 -- runaway guard; the walk below is bounded by the wrap anyway
local POLL_READ_BUDGET = 6 -- cells one poll may re-read; see collect_here
local run_token = 0 -- bumped per follow(), so a cell is re-read once per evaluation

-- Collect every cell Molten knows about, in buffer order.
--
-- `MoltenGoto n` jumps to the nth entry of Molten's own sorted cell list and
-- indexes it modulo the list length (`__init__.py:441`), so walking n = 1, 2,
-- ... until the cursor lands back on the first position enumerates exactly the
-- cells that exist. Going through Molten rather than scanning for ```fences
-- also picks up cells created by a visual selection or the evaluate operator,
-- which have no fence to find.
local function walk_positions()
    local view = vim.fn.winsaveview()
    -- The walk drives the cursor through every cell, so put it back exactly:
    -- winrestview alone restores the scroll position but not reliably the
    -- column, and this is the user's cursor.
    local cursor = vim.api.nvim_win_get_cursor(0)
    local pos, first = {}, nil
    for n = 1, MAX_CELLS do
        if not pcall(vim.cmd, "noautocmd silent! MoltenGoto " .. n) then
            break
        end
        local p = vim.api.nvim_win_get_cursor(0)
        local key = p[1] .. ":" .. p[2]
        if first == nil then
            first = key
        elseif key == first then
            break -- wrapped around: we have seen them all
        end
        pos[#pos + 1] = p
    end
    vim.fn.winrestview(view)
    pcall(vim.api.nvim_win_set_cursor, 0, cursor)
    return pos
end

-- Reading one cell costs ~13ms (Molten builds and tears down the float), so
-- re-reading every cell on every poll does not scale: a 40-cell notebook takes
-- 620ms per refresh, which is the kind of synchronous stall that made the
-- editor unusable before. Almost all of that work is wasted -- a cell Molten
-- reports as Done cannot change until it is re-run -- so cache the settled
-- output and re-read only cells that are still pending or that the caller says
-- it just evaluated.
--
-- Positions are cached separately from output, keyed on the buffer's
-- changedtick: editing moves cells (so the walk must be redone) without
-- invalidating anything they printed. Output is keyed on a cell's start line
-- rather than its index, so evaluating a new cell doesn't renumber, and
-- therefore discard, all the others.
local cache = { buf = nil, tick = nil, pos = nil, out = {} }

function M.forget()
    cache.buf, cache.tick, cache.pos, cache.out = nil, nil, nil, {}
end

-- `dirty` is an optional list of {first, last} line ranges that were just
-- evaluated; nil means "assume everything changed". Cell i owns the lines from
-- its own start up to the next cell's start.
local function is_dirty(pos, i, dirty)
    if dirty == nil then
        return true
    end
    local from = pos[i][1]
    local to = pos[i + 1] and pos[i + 1][1] - 1 or math.huge
    for _, range in ipairs(dirty) do
        if range[1] <= to and range[2] >= from then
            return true
        end
    end
    return false
end

local function collect_here(dirty)
    if not M.all_cells or vim.fn.exists(":MoltenGoto") ~= 2 then
        local lines, paths = grab_here()
        if lines == nil then
            return nil
        end
        return { cells = { { lines = lines, paths = paths } }, deferred = false }
    end

    local token = dirty and run_token or nil

    -- Re-walk when the cells may have moved OR when the set of them may have
    -- changed. Editing shifts positions, which changedtick catches -- but
    -- *evaluating* a cell creates one in Molten without touching the buffer at
    -- all, so changedtick alone left the pane working from the cell list as it
    -- was at the first run, and nothing you ran afterwards ever appeared. The
    -- token changes once per evaluation, so this walks once per run, not once
    -- per poll.
    local buf = vim.api.nvim_get_current_buf()
    local tick = vim.api.nvim_buf_get_changedtick(buf)
    if cache.buf ~= buf or cache.tick ~= tick or cache.pos == nil or cache.token ~= token then
        cache.buf, cache.tick, cache.token = buf, tick, token
        cache.pos = walk_positions()
    end
    local pos = cache.pos

    -- Cap how many cells one poll may re-read. Molten's commands are
    -- synchronous RPCs into the same Python host that runs MoltenTick, and the
    -- tick is what pumps messages from the kernel -- so re-reading 40 cells on
    -- every poll starves the kernel and a <leader>ra run simply never
    -- progresses (measured: every cell stuck "On Hold" for a minute, all of
    -- them Done in the same time with the pane's polling disabled).
    --
    -- Cells are re-read in buffer order, which is also execution order, so the
    -- budget is spent on the frontier: the cells that are actually running.
    -- Anything skipped stays uncached and pending, so the next poll picks it
    -- up. An explicit refresh (dirty == nil, i.e. <leader>os) is not a poll and
    -- reads everything.
    local budget = dirty and POLL_READ_BUDGET or math.huge

    -- Choose what to spend the budget on before reading anything. Two
    -- priorities, both in buffer (= execution) order:
    --
    --   1. cells you just evaluated that we have not read yet -- the whole
    --      point of the refresh, so they must not queue behind anything;
    --   2. cells never read or still pending from an earlier run, which is
    --      what makes the log fill in;
    --   3. cells settled and cached but named by `dirty`, i.e. re-evaluated.
    --
    -- Priority matters: under <leader>ra every cell is dirty for the whole run,
    -- so a naive scan would spend the entire budget re-reading the first few
    -- cells on every poll and never reach the rest. The token stops a cell
    -- being re-read over and over for the same evaluation.
    local want, wanted = {}, 0
    for i, p in ipairs(pos) do
        local entry = cache.out[p[1]]
        local unread = entry == nil or entry.pending or entry.recheck
        local evaluated = is_dirty(pos, i, dirty)
        if unread and evaluated then
            want[i] = 1 -- the cell you just ran: read it before anything else
        elseif unread then
            want[i] = 2 -- the frontier of an earlier run, still filling in
        elseif evaluated and entry.token ~= token then
            want[i] = 3 -- settled and cached, but re-run since we last looked
        end
        if want[i] then
            wanted = wanted + 1
        end
    end
    local read, left = {}, budget
    for priority = 1, 3 do
        for i = 1, #pos do
            if want[i] == priority and left > 0 then
                read[i], left = true, left - 1
            end
        end
    end
    -- Anything we wanted but could not afford: come back for it next poll.
    local deferred = wanted > budget

    local view, cursor, moved = vim.fn.winsaveview(), vim.api.nvim_win_get_cursor(0), false
    local cells, fresh = {}, {}
    local ok, err = pcall(function()
        for i, p in ipairs(pos) do
            local entry = cache.out[p[1]]
            if not read[i] then
                -- Not read this time: keep whatever we already had. Replacing
                -- it with a placeholder would throw away output we have already
                -- shown.
                entry = entry or { lines = {}, paths = {}, pending = false }
            else
                if pcall(vim.api.nvim_win_set_cursor, 0, p) then
                    moved = true
                    -- Molten cannot build the output for a cell the window's
                    -- view doesn't cover, and nvim_win_set_cursor alone doesn't
                    -- update the view -- no redraw happens in this loop. Without
                    -- the scroll, cells far from where the cursor started (in
                    -- practice the newest ones, which is where the plot you just
                    -- made lives) silently read back empty.
                    pcall(vim.cmd, "noautocmd normal! zz")
                    local was = entry
                    local lines, paths = grab_here()
                    entry = { lines = lines or {}, paths = paths or {} }
                    entry.pending = is_pending(entry.lines)
                    entry.token = token
                    -- Molten reports a cell Done slightly before it attaches
                    -- the figure to the output buffer, so caching the first
                    -- settled reading loses the plot. Read a newly-settled cell
                    -- once more -- exactly once, since the re-read clears the
                    -- flag -- to pick up an image that landed late.
                    if not entry.pending and (was == nil or was.pending) then
                        entry.recheck = true
                    end
                else
                    entry = entry or { lines = {}, paths = {}, pending = false }
                end
            end
            -- Never cache an empty reading: it means the cell hasn't produced
            -- anything *yet*, so remembering it would permanently hide the
            -- output of every cell still queued when the pane last looked.
            -- It stays pending instead, and the poll picks it up when it lands.
            if #entry.lines > 0 or #entry.paths > 0 then
                fresh[p[1]] = entry -- keyed by line, so cells that moved are dropped
            end
            cells[#cells + 1] = entry
        end
    end)
    cache.out = fresh
    if moved then
        vim.fn.winrestview(view)
        pcall(vim.api.nvim_win_set_cursor, 0, cursor)
    end
    if not ok then
        error(err)
    end
    if #cells == 0 then
        return nil
    end
    return { cells = cells, deferred = deferred }
end

-- Run the collection in the notebook's window (see `remember_source`), so the
-- pane keeps updating while you sit in the REPL below it.
local function collect(dirty)
    local src = state.src
    if src and src ~= state.win and vim.api.nvim_win_is_valid(src) then
        local ok, res = pcall(vim.api.nvim_win_call, src, function()
            return collect_here(dirty)
        end)
        return ok and res or nil
    end
    return collect_here(dirty)
end

-- Rewrite only the lines that actually differ, so extmarks -- and with them the
-- images' virtual padding -- survive elsewhere in the buffer. Returns the first
-- line rewritten, or nil if the buffer already matched.
local function set_body(body)
    local old = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
    local head = 0
    while head < #old and head < #body and old[head + 1] == body[head + 1] do
        head = head + 1
    end
    local tail = 0
    while tail < #old - head and tail < #body - head and old[#old - tail] == body[#body - tail] do
        tail = tail + 1
    end
    if head == #old and head == #body then
        return nil -- identical
    end
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, head, #old - tail, false, vim.list_slice(body, head + 1, #body - tail))
    vim.bo[state.buf].modifiable = false
    return head
end

-- Returns whether any cell is still pending, so `follow()` knows to look again.
-- `dirty` is passed straight to `collect_here` -- see `is_dirty`.
function M.refresh(dirty)
    if not M.is_open() then
        return nil
    end
    local got = collect(dirty)
    if got == nil then
        return nil
    end
    local cells = got.cells

    -- Molten's own header ("Out[3]: ✓ Done 0.4s") already labels each cell, so
    -- the log needs no separator of its own beyond a blank line.
    local pending = got.deferred
    local body, anchors = {}, {}
    for _, cell in ipairs(cells) do
        if cell.pending or cell.recheck then
            pending = true
        end
        local lines = vim.list_extend({}, cell.lines)
        while #lines > 0 and lines[#lines]:match("^%s*$") do
            table.remove(lines)
        end
        if #lines > 0 or #cell.paths > 0 then
            if #body > 0 then
                body[#body + 1] = ""
            end
            vim.list_extend(body, lines)
            -- One real line per image for image.nvim to anchor to: the space
            -- the plot occupies is virtual padding hung below that line, so
            -- consecutive images sit on consecutive lines.
            for _, path in ipairs(cell.paths) do
                body[#body + 1] = ""
                anchors[#anchors + 1] = { path = path, row = #body - 1 }
            end
        end
    end
    if #body == 0 then
        body = { "-- no output --" }
    end

    -- Keep the newest output in view, like a console. This matters more than it
    -- looks: image.nvim does not render an image that is below the window's
    -- viewport, so without this the plot from the cell you just ran silently
    -- fails to appear once the log grows past one screen. Stick to the bottom
    -- only if the pane is unfocused or its cursor was already on the last line,
    -- so scrolling back through the log isn't yanked away from you.
    local was = vim.api.nvim_buf_line_count(state.buf)
    local stick = vim.api.nvim_get_current_win() ~= state.win
        or vim.api.nvim_win_get_cursor(state.win)[1] >= was

    local first_changed = set_body(body)

    if stick then
        -- An image's height is virtual lines hanging *below* its anchor line,
        -- so if the newest output is a plot, parking that line at the bottom of
        -- the window (zb) leaves nowhere to draw it -- image.nvim decides it is
        -- off-screen and skips it. Put the plot at the top instead and let it
        -- have the window; only fall back to the bottom for plain text.
        local last_line = vim.api.nvim_buf_line_count(state.buf)
        local newest = anchors[#anchors]
        local line, where = last_line, "zb"
        if newest and newest.row + 1 >= last_line - 1 then
            line, where = newest.row + 1, "zt"
        end
        pcall(vim.api.nvim_win_set_cursor, state.win, { line, 0 })
        -- Scroll for the same reason as the grab loop: moving the cursor does
        -- not move the view without a redraw, and image.nvim skips any image it
        -- believes is outside the viewport.
        pcall(vim.api.nvim_win_call, state.win, function()
            vim.cmd("noautocmd normal! " .. where)
        end)
    end
    render_images(anchors, first_changed)
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
--
-- A refresh costs one MoltenGoto plus a show/hide pair per cell -- all
-- synchronous RPCs into the Python host, ~3.5ms per cell -- so a long notebook
-- is much more expensive to poll than a short one. Rather than pick an
-- interval that is wrong at one end or the other, spend a fixed *fraction* of
-- wall time on it: each interval is the last refresh's cost divided by the
-- budget, so 40ms polls every 500ms and 300ms backs off to 3s. Molten's own
-- sync tick is what made the editor unusable once before; this cannot.
-- The floor only needs to be low enough to feel immediate: the budget below is
-- what actually protects the UI, scaling the wait with what a refresh costs. A
-- one-cell notebook refreshes in ~13ms and so polls at ~150ms; a 40-cell one
-- costs ~80ms and backs off to ~800ms on its own.
local POLL_MS = 150 -- floor
local POLL_MAX_MS = 3000 -- ceiling
local POLL_BUDGET = 0.1 -- at most ~10% of wall time spent refreshing
-- Long enough for a real run: a 40-cell notebook took over two minutes to work
-- through, and a shorter cap left the pane showing "On Hold" for the last cell
-- forever. The cost of waiting is bounded by the budget above, so this is cheap
-- insurance; it exists only so a kernel that never becomes ready cannot leave
-- the timer running for the rest of the session.
local POLL_CAP_MS = 600000 -- 10 minutes

-- `dirty` is the list of {first, last} line ranges just evaluated, so the
-- refresh can skip re-reading cells that cannot have changed. Omit it and every
-- cell is re-read.
function M.follow(dirty)
    stop_timer()
    run_token = run_token + 1
    remember_source()
    M.open(false)
    -- `nil` means Molten has nothing to show at all (no kernel attached,
    -- command unavailable), which no amount of waiting fixes. Otherwise always
    -- arm one look: output is asynchronous, so a cell can read as settled here
    -- purely because it hasn't started producing anything yet.
    if M.refresh(dirty) == nil then
        return
    end

    local started = vim.uv.now()
    local timer = vim.uv.new_timer()
    state.timer = timer

    local tick
    local function arm(ms)
        if state.timer == timer and not timer:is_closing() then
            timer:start(ms, 0, function()
                vim.schedule(tick)
            end)
        end
    end

    tick = function()
        if state.timer ~= timer then
            return -- superseded by a newer follow()
        end
        if not M.is_open() or vim.uv.now() - started > POLL_CAP_MS then
            return stop_timer()
        end
        local t0 = vim.uv.hrtime()
        -- Same `dirty` every poll: these are the cells being evaluated, so they
        -- are exactly the ones worth re-reading until they settle.
        --
        -- Guarded: an error in here would skip the re-arm below and kill the
        -- poll silently, leaving the pane stuck on whatever it last drew (in
        -- practice "On Hold" for the cell that was running). One bad reading
        -- should cost a tick, not the rest of the run.
        local ok, pending = pcall(M.refresh, dirty)
        local cost_ms = (vim.uv.hrtime() - t0) / 1e6
        if ok and pending ~= true then
            return stop_timer()
        end
        arm(math.min(POLL_MAX_MS, math.max(POLL_MS, math.floor(cost_ms / POLL_BUDGET))))
    end

    arm(POLL_MS)
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
            draw(drawn.anchors)
        end
    end,
})

return M
