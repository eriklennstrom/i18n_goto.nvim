local M = {}

-- low-level helpers
local function is_escaped(txt, i)
  local back = 0; i = i - 1
  while i >= 1 and txt:sub(i,i) == "\\" do back = back + 1; i = i - 1 end
  return (back % 2) == 1
end

local function find_matching_brace(txt, open_pos)
  local depth, i, in_str = 0, open_pos, false
  while i <= #txt do
    local ch = txt:sub(i,i)
    if in_str then
      if ch == '"' and not is_escaped(txt, i) then in_str = false end
    else
      if ch == '"' then in_str = true
      elseif ch == '{' then depth = depth + 1
      elseif ch == '}' then depth = depth - 1; if depth == 0 then return i end
      end
    end
    i = i + 1
  end
end

local function skip_ws(txt, i)
  while i <= #txt and txt:sub(i,i):match("[%s]") do i = i + 1 end
  return i
end

local function find_property_at_depth(txt, start_pos, end_pos, key)
  local i, in_str, depth = start_pos, false, 1
  while i <= end_pos do
    local ch = txt:sub(i,i)
    if in_str then
      if ch == '"' and not is_escaped(txt, i) then in_str = false end
      i = i + 1
    else
      if ch == '"' then
        local name_start = i; i = i + 1
        local name_end
        while i <= end_pos do
          local c = txt:sub(i,i)
          if c == '"' and not is_escaped(txt, i) then name_end = i; break end
          i = i + 1
        end
        if not name_end then return nil end
        local name = txt:sub(name_start + 1, name_end)
        i = i + 1
        i = skip_ws(txt, i)
        if txt:sub(i,i) == ":" then
          if depth == 1 and name == key then return name_start, name_end, i end
          i = i + 1
        end
      elseif ch == '{' then depth = depth + 1; i = i + 1
      elseif ch == '}' then depth = depth - 1; if depth == 0 then return nil end; i = i + 1
      else i = i + 1 end
    end
  end
end

local function find_key_path(txt, path)
  local first_brace = txt:find("{")
  local obj_start = first_brace and (first_brace) or 1
  local obj_end   = first_brace and find_matching_brace(txt, obj_start) or #txt
  if not obj_end then obj_end = #txt end

  local key_pos
  for idx, seg in ipairs(path) do
    local name_s, _, colon = find_property_at_depth(txt, obj_start + 1, obj_end - 1, seg)
    if not name_s then return nil end
    key_pos = name_s
    local val = skip_ws(txt, colon + 1)
    if idx == #path then return key_pos, val end
    if txt:sub(val,val) ~= "{" then return nil end
    obj_start, obj_end = val, find_matching_brace(txt, val)
    if not obj_end then return nil end
  end
end

local function pos_to_line(txt, pos)
  local n, i = 1, 1
  while true do
    local nl = txt:find("\n", i, true)
    if not nl or nl >= pos then return n end
    n, i = n + 1, nl + 1
  end
end

local function read_value_preview(txt, pos)
  pos = skip_ws(txt, pos)
  local ch = txt:sub(pos,pos)
  if ch == '"' then
    local i = pos + 1
    local buf = {}
    while i <= #txt do
      local c = txt:sub(i,i)
      if c == '"' and not is_escaped(txt, i) then break end
      table.insert(buf, c)
      i = i + 1
    end
    return table.concat(buf)
  elseif ch == '{' then return "{…}"
  elseif ch == '[' then return "[…}"
  else
    local j = pos
    while j <= #txt and not txt:sub(j,j):match("[,%]%}%n]") do j = j + 1 end
    return vim.trim(txt:sub(pos, j - 1))
  end
end

function M.find_in_file(file, keypath)
  local lines = vim.fn.readfile(file)
  if not lines or #lines == 0 then return end
  local txt = table.concat(lines, "\n")

  -- Fast path: flat `"key": ...`
  local flat_pat = '"' .. keypath:gsub("(%W)", "%%%1") .. '"%s*:'
  for i, ln in ipairs(lines) do
    if ln:find(flat_pat) then
      local pv = ln:match('"%s*:%s*["\'](.-)["\']')
      return i, pv
    end
  end

  -- Fallback: nested
  local parts = {}
  for seg in keypath:gmatch("[^%.]+") do table.insert(parts, seg) end
  local key_pos, val_pos = find_key_path(txt, parts)
  if not key_pos then return end

  local line = pos_to_line(txt, key_pos)
  local preview = read_value_preview(txt, val_pos)
  return line, preview
end

function M.all_locale_values(files, keypath)
  local out = {}
  for _, file in ipairs(files) do
    local lnum, val = M.find_in_file(file, keypath)
    if lnum then
      local base = (file:match("([^/\\]+)$") or file):gsub("%.json$", "")
      table.insert(out, { locale = base, file = file, lnum = lnum, value = val or "" })
    end
  end
  table.sort(out, function(a,b) return a.locale < b.locale end)
  return out
end

return M
