-- i18n_goto/init.lua
local config     = require("i18n_goto.config")
local fs         = require("i18n_goto.fs")
local json_scan  = require("i18n_goto.json_scan")
local flat_insert= require("i18n_goto.flat_insert")
local key_helpers= require("i18n_goto.keys")
local diagnostics= require("i18n_goto.diagnostics")

local M = {}

-- Jump to definition; create if missing (smart placement in flat JSON; nested fallback).
function M.goto_definition()
  local key = key_helpers.key_under_cursor(config.patterns)
  if not key then
    return vim.lsp.buf.definition()
  end

  local files = fs.scan_files(config)
  if #files == 0 then
    return vim.lsp.buf.definition()
  end

  -- Jump if key exists in any locale file
  for _, file in ipairs(files) do
    local line = select(1, json_scan.find_in_file(file, key))
    if line then
      vim.cmd("edit " .. vim.fn.fnameescape(file))
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      vim.cmd("normal! zz")
      return
    end
  end

  -- Otherwise, create new entry: prefer "en", then "sv", else prompt.
  local target_file
  for _, preferred in ipairs({ "en", "sv" }) do
    for _, file in ipairs(files) do
      if (file:match("([^/\\]+)$") or file):gsub("%.json$", "") == preferred then
        target_file = file
        break
      end
    end
    if target_file then break end
  end
  if not target_file then
    local choices = {}
    for _, file in ipairs(files) do
      choices[#choices+1] = (file:match("([^/\\]+)$") or file)
    end
    local picked
    vim.ui.select(choices, { prompt = "Create missing key in locale file…" }, function(c) picked = c end)
    if not picked then return end
    for _, file in ipairs(files) do
      if (file:match("([^/\\]+)$") or file) == picked then target_file = file; break end
    end
  end
  if not target_file then return end

  -- Choose insertion strategy based on detected style
  local root_table = fs.read_json_file(target_file)
  local is_flat = (type(root_table) == "table") and fs.table_has_dotted_keys(root_table)

  local inserted_line
  if is_flat then
    inserted_line = flat_insert.insert_flat_key_line(target_file, key, "")
  else
    fs.upsert_key_in_file(target_file, key, "")
    inserted_line = select(1, json_scan.find_in_file(target_file, key)) or 1
  end

  vim.cmd("edit " .. vim.fn.fnameescape(target_file))
  vim.api.nvim_win_set_cursor(0, { inserted_line, 0 })
  vim.cmd("normal! zz")
  vim.notify(string.format("[i18n_goto] Created '%s' in %s", key, (target_file:match("([^/\\]+)$") or target_file)), vim.log.levels.INFO)
end

-- Peek translation values across locales in a simple floating window.
function M.peek_translation()
  local key = key_helpers.key_under_cursor(config.patterns)
  if not key then return end

  local files = fs.scan_files(config)
  local matches = json_scan.all_locale_values(files, key)
  if #matches == 0 then return end

  local lines = { "🔤 " .. key, "" }
  for _, m in ipairs(matches) do
    lines[#lines+1] = string.format("%s: %s", m.locale, m.value or "")
  end

  local max_width = 0
  for _, l in ipairs(lines) do max_width = math.max(max_width, vim.fn.strdisplaywidth(l)) end
  local width  = math.min(math.max(30, max_width + 2), vim.o.columns - 4)
  local height = math.min(#lines, math.max(3, vim.o.lines - 4))
  local row    = math.floor((vim.o.lines - height) / 2)
  local col    = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden  = "wipe"

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width, height = height, row = row, col = col,
    style = "minimal", border = "rounded", noautocmd = true,
  })

  vim.defer_fn(function()
    local grp = vim.api.nvim_create_augroup("i18n_goto_peek_close", { clear = true })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave" }, {
      group = grp, once = true,
      callback = function()
        pcall(vim.api.nvim_win_close, win, true)
        if vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
      end,
    })
  end, 50)
end

-- Optional: explicit create flow via UI (kept as a public command).
function M.create_missing_translation()
  local key = key_helpers.key_under_cursor(config.patterns)
  if not key then
    vim.notify("[i18n_goto] No i18n key detected on this line.", vim.log.levels.WARN)
    return
  end

  local files = fs.scan_files(config)
  if #files == 0 then
    vim.notify("[i18n_goto] No translation files found (check scan_dirs).", vim.log.levels.WARN)
    return
  end

  local missing = {}
  for _, f in ipairs(files) do
    local has_line = select(1, json_scan.find_in_file(f, key)) ~= nil
    if not has_line then
      table.insert(missing, { locale = (f:match("([^/\\]+)$") or f):gsub("%.json$", ""), file = f })
    end
  end
  if #missing == 0 then
    vim.notify("[i18n_goto] Key already exists in all locales.", vim.log.levels.INFO)
    return
  end

  local items = {}
  for _, m in ipairs(missing) do items[#items+1] = m.locale .. "  (" .. m.file .. ")" end
  vim.ui.select(items, { prompt = "Create translation in locale…" }, function(choice)
    if not choice then return end
    local selection
    for _, m in ipairs(missing) do
      if choice:find("^" .. vim.pesc(m.locale) .. "%s") then selection = m; break end
    end
    if not selection then return end
    vim.ui.input({ prompt = "Value for " .. key .. " (" .. selection.locale .. "): " }, function(val)
      if val == nil then return end
      local root_table = fs.read_json_file(selection.file)
      local is_flat = (type(root_table) == "table") and fs.table_has_dotted_keys(root_table)
      if is_flat then
        local line = require("i18n_goto.flat_insert").insert_flat_key_line(selection.file, key, val or "")
        vim.cmd("edit " .. vim.fn.fnameescape(selection.file))
        vim.api.nvim_win_set_cursor(0, { line, 0 })
      else
        fs.upsert_key_in_file(selection.file, key, val or "")
        local line = select(1, json_scan.find_in_file(selection.file, key)) or 1
        vim.cmd("edit " .. vim.fn.fnameescape(selection.file))
        vim.api.nvim_win_set_cursor(0, { line, 0 })
      end
      vim.cmd("normal! zz")
      vim.notify("[i18n_goto] Created '" .. key .. "' in " .. selection.locale, vim.log.levels.INFO)
    end)
  end)
end

function M.setup(user_opts)
  user_opts = user_opts or {}
  if user_opts.scan_dirs then config.scan_dirs = user_opts.scan_dirs end
  if user_opts.scan_glob then config.scan_glob = user_opts.scan_glob end

  -- Commands
  vim.api.nvim_create_user_command("I18nGoto",   function() M.goto_definition() end, {})
  vim.api.nvim_create_user_command("I18nPeek",   function() M.peek_translation() end, {})
  vim.api.nvim_create_user_command("I18nCreate", function() M.create_missing_translation() end, {})
  vim.api.nvim_create_user_command("I18nGotoDebug", function()
    local key = (function() local ok, k = pcall(key_helpers.key_under_cursor, config.patterns); return ok and k or nil end)()
    local files = (function() local ok, list = pcall(fs.scan_files, config); return ok and list or {} end)()
    local hits = {}
    if key then
      for _, f in ipairs(files) do
        local lnum, prev = json_scan.find_in_file(f, key)
        if lnum then hits[#hits+1] = { file = f, lnum = lnum, preview = prev } end
      end
    end
    local out = {
      "i18n_goto debug",
      "  key: " .. (key or "<none>"),
      "  files scanned: " .. tostring(#files),
    }
    for _, f in ipairs(files) do out[#out+1] = "    - " .. f end
    out[#out+1] = "  matches: " .. tostring(#hits)
    for _, h in ipairs(hits) do out[#out+1] = string.format("    - %s:%d  %s", h.file, h.lnum, h.preview or "") end
    for _, line in ipairs(out) do vim.notify(line) end
  end, {})

  -- Inline underline hint (diagnostics)
  diagnostics.setup_autocmds()
end

return M
