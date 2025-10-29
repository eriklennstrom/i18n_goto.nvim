local M = {}

local function rtrim(s) return (s:gsub("%s+$", "")) end
local function split_dot(s) local t = {}; for seg in s:gmatch("[^%.]+") do t[#t+1]=seg end; return t end
local function shared_prefix_len(a, b)
  local A, B = split_dot(a), split_dot(b)
  local n, k = math.min(#A, #B), 0
  for i = 1, n do if A[i] == B[i] then k = k + 1 else break end end
  return k
end

local function parse_flat_keys(lines)
  local out = {}
  for i, ln in ipairs(lines) do
    local indent, key = ln:match('^(%s*)"%s*([^"]+)%s*"%s*:')
    if key then out[#out+1] = { key = key, idx = i, indent = indent or "" } end
  end
  return out
end

local function find_best_insert_index(lines, newkey)
  local props = parse_flat_keys(lines)
  if #props == 0 then
    for i = #lines, 1, -1 do if lines[i]:find("}") then return i, "  " end end
    return #lines + 1, "  "
  end

  local best_idx, best_len = nil, -1
  for _, p in ipairs(props) do
    local sp = shared_prefix_len(newkey, p.key)
    if sp > best_len or (sp == best_len and p.idx > (best_idx or -1)) then
      best_len, best_idx = sp, p.idx
    end
  end

  if best_len > 0 and best_idx then
    local kpos = 1
    for j, p in ipairs(props) do if p.idx == best_idx then kpos = j; break end end
    local last_idx = props[kpos].idx
    for j = kpos + 1, #props do
      if shared_prefix_len(newkey, props[j].key) == best_len then last_idx = props[j].idx else break end
    end
    return last_idx + 1, props[kpos].indent
  end

  local last_less_idx, indent = nil, props[1].indent
  for _, p in ipairs(props) do
    if p.key <= newkey then last_less_idx = p.idx; indent = p.indent end
  end
  if last_less_idx then return last_less_idx + 1, indent end
  return props[1].idx, props[1].indent
end

function M.insert_flat_key_line(file, key, value)
  local lines = vim.fn.readfile(file)
  if not lines or #lines == 0 then lines = { "{", "}" } end

  local insert_idx, indent = find_best_insert_index(lines, key)

  -- Ensure previous property (if any) ends with comma (unless it’s an opening brace)
  local prev_idx = insert_idx - 1
  if prev_idx >= 1 and lines[prev_idx]:match("%S") and not lines[prev_idx]:find("{%s*$") then
    local t = rtrim(lines[prev_idx])
    if not t:match(",$") then
      lines[prev_idx] = t .. ","
    end
  end

  -- Decide if the NEW line should end with a comma:
  -- If the next non-empty line is NOT a closing brace, we need a trailing comma.
  local need_trailing_comma = false
  do
    local next_idx = insert_idx
    while next_idx <= #lines and not lines[next_idx]:match("%S") do
      next_idx = next_idx + 1
    end
    local next_line = lines[next_idx]
    if next_line and not next_line:find("^%s*}") then
      need_trailing_comma = true
    end
  end

  local new_line = string.format('%s"%s": "%s"%s',
    indent, key, value or "", need_trailing_comma and "," or "")

  table.insert(lines, insert_idx, new_line)

  vim.fn.writefile(lines, file)
  return insert_idx
end

return M
