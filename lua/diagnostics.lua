-- i18n_goto/diagnostics.lua
-- Inline underline hint (via diagnostics) when some locales are missing a key.

local config      = require("i18n_goto.config")
local fs          = require("i18n_goto.fs")
local json_scan   = require("i18n_goto.json_scan")
local key_helpers = require("i18n_goto.keys")

local Diagnostics = {}

-- Use a dedicated namespace so we can configure diagnostics only for this plugin.
local NAMESPACE_ID = vim.api.nvim_create_namespace("i18n_goto_diagnostics")

-- Configure diagnostics for our namespace:
-- underline only; no virtual text/signs; avoid updates while typing.
vim.diagnostic.config({
  underline         = true,
  virtual_text      = false,
  signs             = false,
  update_in_insert  = false,
}, NAMESPACE_ID)

-- Filetypes where showing the inline i18n hint makes sense.
local ALLOWED_FILETYPES = {
  vue = true,
  javascript = true,
  typescript = true,
  javascriptreact = true,
  typescriptreact = true,
}

-- Helper: turn a locale file path into a locale label (e.g. "en.json" -> "en")
local function locale_from_path(path)
  local base = (path:match("([^/\\]+)$") or path)
  return base:gsub("%.json$", "")
end

-- Helper: return list of locales that are missing the given key.
local function compute_missing_locales_for_key(all_files, keypath)
  local missing = {}
  for _, file in ipairs(all_files) do
    local line = select(1, json_scan.find_in_file(file, keypath))
    if not line then
      table.insert(missing, locale_from_path(file))
    end
  end
  table.sort(missing)
  return missing
end

-- Helper: find the 0-based [start_col, end_col_exclusive) span of the key on the current line.
-- Tries to underline only the key token inside a t('...') call; falls back to a quoted token span.
local function find_key_span_on_line(patterns, cursor_col0, line_text)
  -- 1) Match a known call pattern and ensure the cursor is within the match
  for _, pattern in ipairs(patterns) do
    local s, e, captured = line_text:find(pattern)
    if s and e and captured and cursor_col0 >= (s - 1) and cursor_col0 <= (e - 1) then
      -- Find the captured text inside the matched slice so we underline only the key
      local slice = line_text:sub(s, e)
      local ks, ke = slice:find(vim.pesc(captured), 1, true)
      if ks and ke then
        local start0 = (s - 1) + (ks - 1)
        local end0   = (s - 1) + ke
        return start0, end0
      end
    end
  end

  -- 2) Best-effort: underline the first matched captured key on the line
  for _, pattern in ipairs(patterns) do
    local s, e, captured = line_text:find(pattern)
    if s and e and captured then
      local slice = line_text:sub(s, e)
      local ks, ke = slice:find(vim.pesc(captured), 1, true)
      if ks and ke then
        local start0 = (s - 1) + (ks - 1)
        local end0   = (s - 1) + ke
        return start0, end0
      end
    end
  end

  -- 3) Fallback: if cursor is inside quotes, underline the quoted token
  local before = line_text:sub(1, cursor_col0 + 1)
  local after  = line_text:sub(cursor_col0 + 2)
  local left_quote = before:find("['\"][^'\"]*$")
  local right_quote = after:find("[\"']")
  if left_quote and right_quote then
    local s = left_quote       -- 1-based index of opening quote
    local e = cursor_col0 + right_quote -- 1-based index of closing quote
    -- Convert to 0-based, exclusive end
    return s - 1, e - 1
  end

  -- If we cannot find a specific token, return nil and the caller can choose a fallback.
  return nil, nil
end

-- Main: recompute and apply the underline diagnostic for the key under cursor, if missing.
local function refresh_inline_diagnostic()
  local bufnr = vim.api.nvim_get_current_buf()
  vim.diagnostic.reset(NAMESPACE_ID, bufnr)

  -- Only run in relevant filetypes
  local ft = vim.bo[bufnr].filetype
  if not ALLOWED_FILETYPES[ft] then
    return
  end

  -- Extract key under cursor (using configured patterns)
  local key = key_helpers.key_under_cursor(config.patterns)
  if not key then
    return
  end

  -- Gather all translation files; if none, nothing to check.
  local all_locale_files = fs.scan_files(config)
  if #all_locale_files == 0 then
    return
  end

  -- If every locale has the key, no diagnostic needed.
  local missing = compute_missing_locales_for_key(all_locale_files, key)
  if #missing == 0 then
    return
  end

  -- Compute underline span on this line
  local cursor_row1, cursor_col0 = unpack(vim.api.nvim_win_get_cursor(0))
  local line_text = vim.api.nvim_get_current_line()
  local start_col0, end_col0 = find_key_span_on_line(config.patterns, cursor_col0, line_text)
  if not start_col0 or not end_col0 or end_col0 <= start_col0 then
    start_col0, end_col0 = 0, #line_text
  end

  -- Create a single WARN diagnostic covering the key token.
  local diagnostic = {
    lnum      = cursor_row1 - 1,
    end_lnum  = cursor_row1 - 1,
    col       = start_col0,
    end_col   = end_col0,
    severity  = vim.diagnostic.severity.WARN,
    source    = "i18n_goto",
    message   = "Missing translations: " .. table.concat(missing, ", "),
  }

  vim.diagnostic.set(NAMESPACE_ID, bufnr, { diagnostic }, {})
end

-- Public API: register autocmds that drive the inline diagnostic.
function Diagnostics.setup_autocmds()
  local group = vim.api.nvim_create_augroup("i18n_goto_inline_diagnostics", { clear = true })

  -- Recompute when entering buffers and when the cursor rests.
  vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "CursorHoldI" }, {
    group = group,
    callback = function()
      pcall(refresh_inline_diagnostic)
    end,
  })

  -- Clear diagnostics on motion/insert/leave (they’ll reappear on next hold).
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave" }, {
    group = group,
    callback = function(args)
      vim.diagnostic.reset(NAMESPACE_ID, args.buf)
    end,
  })
end

return Diagnostics
