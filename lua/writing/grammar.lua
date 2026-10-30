-- Grammar audit with Claude: the buffer's paragraphs go to a cheap model in a
-- few batched requests, issues come back as verbatim quotes + replacements,
-- and they become extmark-anchored issues you walk with the shared audit
-- walker (and diagnostics, for ]d / Trouble / signs).
--
--   * Results are cached per paragraph (its text, the model, the mode, the
--     language and your style guide), so re-running after an edit only sends
--     the paragraphs that changed.
--   * A quote that isn't in its paragraph is dropped (that's how hallucinated
--     issues die), and so is one overlapping an earlier issue.
--   * Issues are extmarks: they move with your edits, and one whose text no
--     longer matches its quote (you fixed it) disappears.
--   * `d` in the walker dismisses an issue for good (stdpath("state")).

local prose = require("writing.prose")
local claude = require("writing.claude")
local W = require("spellaudit.walker")

local M = {}

M.config = {
  model = "haiku",
  effort = "low",
  chunk_chars = 6000, -- paragraphs per request, by size
}

local api = vim.api
local ns = api.nvim_create_namespace("writing_grammar") -- issue anchors
local ns_diag = api.nvim_create_namespace("writing_grammar_diag")

local B = {} -- buf -> { items = { ... } }

local function bufnr(buf) return (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf end

local CATEGORIES = { "grammar", "spelling", "punctuation", "word-choice", "style", "clarity" }

local SCHEMA = {
  type = "object",
  properties = {
    issues = {
      type = "array",
      items = {
        type = "object",
        properties = {
          p = { type = "integer", description = "paragraph number" },
          quote = { type = "string" },
          suggestions = { type = "array", items = { type = "string" } },
          issue = { type = "string" },
          category = { type = "string", enum = CATEGORIES },
          severity = { type = "string", enum = { "error", "warning", "hint" } },
        },
        required = { "p", "quote", "suggestions", "issue", "category", "severity" },
        additionalProperties = false,
      },
    },
  },
  required = { "issues" },
  additionalProperties = false,
}

local SYSTEM = [[
You are a meticulous copy editor. You find real errors in a writer's prose and propose minimal fixes.

Report: grammar, agreement, verb tense, articles, prepositions, punctuation, homophones and misspellings a spellchecker misses, wrong word choice, missing or doubled words.%s

Rules:
- Do not report text that is correct, even if you would phrase it differently. Preserve the author's voice. Returning no issues is a good answer.
- quote: the shortest exact span that contains the error, copied verbatim from the paragraph (including any markup characters inside it), normally one to six words. Issues must not overlap; one issue per error.
- suggestions: one to three replacements for exactly the quoted span, best first, keeping any markup inside it.
- issue: what is wrong, in under fifteen words, in the paragraph's language.
- p: the paragraph's number.
- The source is LaTeX, Typst or Markdown. Never touch commands, math, code, citations, labels, references or URLs, and never report them.
- Never translate. Suggestions stay in the paragraph's language.]]

local STYLE = "\nAlso report awkward or wordy phrasing and unclear sentences (category style or clarity, severity hint), sparingly."

-- ---------------------------------------------------------------------------
-- persistence

local function json_file(base, name)
  local dir = vim.fn.stdpath(base) .. "/writing"
  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. name
end

local function load(path)
  if vim.fn.filereadable(path) == 0 then return {} end
  local ok, v = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  return ok and type(v) == "table" and v or {}
end

local function save(path, tbl) vim.fn.writefile({ vim.json.encode(tbl) }, path) end

local cache, dismissed
local function get_cache()
  cache = cache or load(json_file("cache", "grammar.json"))
  return cache
end
local function get_dismissed()
  dismissed = dismissed or load(json_file("state", "dismissed.json"))
  return dismissed
end

local function save_cache()
  -- keep the newest 3000 paragraphs
  local keys = vim.tbl_keys(cache)
  if #keys > 3000 then
    table.sort(keys, function(a, b) return (cache[a].t or 0) > (cache[b].t or 0) end)
    for i = 3001, #keys do cache[keys[i]] = nil end
  end
  save(json_file("cache", "grammar.json"), cache)
end

local function dismiss_key(it) return vim.fn.sha256(it.quote .. "\31" .. (it.suggestions[1] or "")) end

-- ---------------------------------------------------------------------------
-- issues

local function norm(s) return vim.trim((s or ""):gsub("%s+", " ")) end

--- Live issues of `buf`: anchored, not dismissed, text still matching.
function M.items(buf)
  buf = bufnr(buf)
  local st = B[buf]
  if not st then return {} end
  local out = {}
  for _, it in ipairs(st.items) do
    local m = api.nvim_buf_get_extmark_by_id(buf, ns, it.mark, { details = true })
    if m[1] and not it.dismissed then
      local r1, c1, r2, c2 = m[1], m[2], m[3].end_row, m[3].end_col
      local ok, text = pcall(api.nvim_buf_get_text, buf, r1, c1, r2, c2, {})
      text = ok and table.concat(text, "\n") or ""
      if norm(text) == norm(it.quote) and norm(text) ~= "" then
        out[#out + 1] = vim.tbl_extend("force", it, {
          row = r1 + 1, col = c1, end_row = r2 + 1, end_col = c2, text = text,
          label = it.category .. " · " .. it.severity, note = it.issue,
        })
      end
    end
  end
  return out
end

local SEV = { error = vim.diagnostic.severity.WARN, warning = vim.diagnostic.severity.INFO, hint = vim.diagnostic.severity.HINT }

function M.refresh(buf)
  buf = bufnr(buf)
  if not api.nvim_buf_is_valid(buf) then return end
  local diags = {}
  for _, it in ipairs(M.items(buf)) do
    diags[#diags + 1] = {
      lnum = it.row - 1, col = it.col, end_lnum = it.end_row - 1, end_col = it.end_col,
      severity = SEV[it.severity] or vim.diagnostic.severity.INFO,
      message = it.issue .. (it.suggestions[1] and (" → " .. it.suggestions[1]) or ""),
      source = "claude", code = it.category,
    }
  end
  vim.diagnostic.set(ns_diag, buf, diags)
end

function M.clear(buf)
  buf = bufnr(buf)
  B[buf] = nil
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.diagnostic.reset(ns_diag, buf)
end

-- Turn cached answers for `paras` into anchored issues (replacing the old ones
-- in those paragraphs).
local function anchor(buf, paras, keys)
  B[buf] = B[buf] or { items = {} }
  local st = B[buf]
  local rows = {}
  for _, p in ipairs(paras) do rows[#rows + 1] = { p.srow, p.erow } end
  local function in_scope(row)
    for _, r in ipairs(rows) do
      if row >= r[1] and row <= r[2] then return true end
    end
  end
  -- drop old issues in these paragraphs
  local keep = {}
  for _, it in ipairs(st.items) do
    local m = api.nvim_buf_get_extmark_by_id(buf, ns, it.mark, {})
    if m[1] and not in_scope(m[1] + 1) then
      keep[#keep + 1] = it
    else
      pcall(api.nvim_buf_del_extmark, buf, ns, it.mark)
    end
  end
  st.items = keep

  local dis, n = get_dismissed(), 0
  for _, p in ipairs(paras) do
    local entry = cache[keys[p.id]]
    local taken = {} -- byte ranges used in this paragraph
    local last = {} -- quote -> offset of its previous occurrence
    for _, iss in ipairs(entry and entry.issues or {}) do
      if type(iss.suggestions) ~= "table" then iss.suggestions = {} end
      local r1, c1, r2, c2, be = prose.locate(p, iss.quote, last[iss.quote])
      if r1 then
        last[iss.quote] = be
        local overlap = false
        for _, t in ipairs(taken) do
          if not (r2 < t[1] or (r2 == t[1] and c2 <= t[2]) or r1 > t[3] or (r1 == t[3] and c1 >= t[4])) then
            overlap = true
            break
          end
        end
        -- a suggestion identical to the quote fixes nothing
        local useful = vim.tbl_filter(function(s) return norm(s) ~= norm(iss.quote) end, iss.suggestions)
        if not overlap and #useful > 0 and not dis[dismiss_key({ quote = iss.quote, suggestions = useful })] then
          taken[#taken + 1] = { r1, c1, r2, c2 }
          local mark = api.nvim_buf_set_extmark(buf, ns, r1 - 1, c1, {
            end_row = r2 - 1, end_col = c2, right_gravity = false, end_right_gravity = true,
          })
          st.items[#st.items + 1] = {
            mark = mark, quote = iss.quote, suggestions = vim.list_slice(useful, 1, 3),
            issue = iss.issue or "", category = iss.category or "grammar", severity = iss.severity or "warning",
          }
          n = n + 1
        end
      end
    end
  end
  M.refresh(buf)
  return n
end

-- ---------------------------------------------------------------------------
-- checking

local function para_key(p, ctx)
  return vim.fn.sha256(table.concat({ M.config.model, M.config.effort, ctx.style and "style" or "errors",
    ctx.lang, ctx.profile or "", table.concat(ctx.glossary, ","), p.text }, "\31"))
end

local function prompt_for(batch, ctx)
  local parts = {
    "Language: " .. ctx.lang .. ".",
  }
  if ctx.profile then parts[#parts + 1] = "\nThe author's style guide:\n<style_guide>\n" .. ctx.profile .. "\n</style_guide>" end
  if #ctx.glossary > 0 then
    parts[#parts + 1] = "\nCorrect as written, never report: " .. table.concat(ctx.glossary, ", ")
  end
  parts[#parts + 1] = "\nParagraphs:\n"
  for _, p in ipairs(batch) do parts[#parts + 1] = ("[p%d]\n%s\n"):format(p.id, p.text) end
  return table.concat(parts, "\n")
end

--- Check `buf` (all paragraphs, or those touching rows `range` = {s, e}).
--- `o.style` adds style/clarity hints; cb(n_issues) when done.
function M.check(buf, o, cb)
  buf, o = bufnr(buf), o or {}
  local paras = prose.paragraphs(buf)
  if o.range then
    paras = vim.tbl_filter(function(p) return p.erow >= o.range[1] and p.srow <= o.range[2] end, paras)
  end
  if #paras == 0 then
    vim.notify("No prose to check here", vim.log.levels.WARN, { title = "Grammar" })
    return
  end
  local profile = prose.profile(buf)
  local ctx = { lang = prose.language(buf), profile = profile, glossary = prose.glossary(buf), style = o.style }
  get_cache()

  local keys, todo = {}, {}
  for _, p in ipairs(paras) do
    keys[p.id] = para_key(p, ctx)
    if not cache[keys[p.id]] then todo[#todo + 1] = p end
  end

  -- batches by size
  local batches, cur, size = {}, {}, 0
  for _, p in ipairs(todo) do
    if size > 0 and size + #p.text > M.config.chunk_chars then
      batches[#batches + 1], cur, size = cur, {}, 0
    end
    cur[#cur + 1] = p
    size = size + #p.text
  end
  if #cur > 0 then batches[#batches + 1] = cur end

  local tick = api.nvim_buf_get_changedtick(buf)
  local function finish(errs)
    if not api.nvim_buf_is_valid(buf) then return end
    -- edits while waiting: re-read the paragraphs; changed ones have no answer
    if api.nvim_buf_get_changedtick(buf) ~= tick then
      paras = vim.tbl_filter(function(p) return cache[para_key(p, ctx)] end, prose.paragraphs(buf))
      for _, p in ipairs(paras) do keys[p.id] = para_key(p, ctx) end
    end
    local n = anchor(buf, paras, keys)
    local msg = ("%d issue%s in %d paragraph%s"):format(n, n == 1 and "" or "s", #paras, #paras == 1 and "" or "s")
    if #batches > 0 then msg = msg .. (" (%d new, %d cached)"):format(#todo, #paras - #todo) end
    if #errs > 0 then msg = msg .. "\n" .. table.concat(errs, "\n") end
    vim.notify(msg, #errs > 0 and vim.log.levels.WARN or vim.log.levels.INFO, { title = "Grammar" })
    if cb then cb(n) end
  end

  if #batches == 0 then return finish({}) end
  vim.notify(("Checking %d paragraph%s with %s…"):format(#todo, #todo == 1 and "" or "s", M.config.model),
    vim.log.levels.INFO, { title = "Grammar" })
  local pending, errs = #batches, {}
  local system = SYSTEM:format(o.style and STYLE or "")
  for _, batch in ipairs(batches) do
    claude.run({
      prompt = prompt_for(batch, ctx), system = system, schema = SCHEMA,
      model = M.config.model, effort = M.config.effort,
    }, function(err, res)
      if err then
        errs[#errs + 1] = err
      else
        local by = {}
        for _, iss in ipairs(res.issues or {}) do
          by[iss.p] = by[iss.p] or {}
          table.insert(by[iss.p], iss)
        end
        local now = os.time()
        for _, p in ipairs(batch) do cache[keys[p.id]] = { issues = by[p.id] or {}, t = now } end
      end
      pending = pending - 1
      if pending == 0 then
        save_cache()
        finish(errs)
      end
    end)
  end
end

-- ---------------------------------------------------------------------------
-- walking

local function dismiss(S, it)
  local k = dismiss_key(it)
  get_dismissed()[k] = true
  save(json_file("state", "dismissed.json"), dismissed)
  for _, x in ipairs(B[S.buf].items) do
    if x.mark == it.mark then x.dismissed = true end
  end
  W.push({
    kind = "dismissed",
    undo = function(s)
      dismissed[k] = nil
      save(json_file("state", "dismissed.json"), dismissed)
      for _, x in ipairs(B[s.buf].items) do
        if x.mark == it.mark then x.dismissed = false end
      end
    end,
  })
  W.step()
end

function M.walk(buf, win)
  buf = bufnr(buf)
  W.start({
    key = "grammar:" .. buf, title = "Grammar", win = win,
    issues = function(S) return M.items(S.buf) end,
    keys = { { "d", "dismiss this issue for good", dismiss } },
    footer = " 1-3 fix · e edit · s skip · d dismiss · u undo · q quit ",
    empty = "No grammar issues", resume_hint = "<leader>Wg",
    on_finish = function(S) M.refresh(S.buf) end,
  })
end

--- Check (cached paragraphs are instant) and walk the issues.
function M.audit(o)
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  local cur = W.current()
  if cur and cur.key == "grammar:" .. buf and cur.paused then return M.walk(buf, win) end
  M.check(buf, o, function(n)
    if n > 0 and api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf then M.walk(buf, win) end
  end)
end

function M.setup()
  local timer = vim.uv.new_timer()
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = api.nvim_create_augroup("writing_grammar", { clear = true }),
    callback = function(ev)
      if not B[ev.buf] then return end
      timer:stop()
      timer:start(300, 0, vim.schedule_wrap(function() M.refresh(ev.buf) end))
    end,
  })
  api.nvim_create_autocmd("BufWipeout", {
    group = "writing_grammar",
    callback = function(ev) B[ev.buf] = nil end,
  })
end

M.ns_diag = ns_diag

return M
