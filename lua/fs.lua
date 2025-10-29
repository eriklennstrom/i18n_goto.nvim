local M = {}

function M.project_root()
  local start = vim.fn.expand("%:p:h")
  local found = vim.fs.find({ ".git", "package.json" }, { upward = true, path = start, type = "file" })
  if #found > 0 then return vim.fn.fnamemodify(found[1], ":p:h") end
  return vim.loop.cwd()
end

function M.scan_files(cfg)
  local root = M.project_root()
  local files, seen = {}, {}
  for _, rel in ipairs(cfg.scan_dirs) do
    local list = vim.fn.glob(root .. "/" .. rel .. "/" .. (cfg.scan_glob or "**/*.json"), false, true)
    for _, f in ipairs(list) do
      if vim.fn.filereadable(f) == 1 and not seen[f] then seen[f] = true; table.insert(files, f) end
    end
  end
  table.sort(files)
  return files
end

function M.read_json_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines or #lines == 0 then return {}, "" end
  local txt = table.concat(lines, "\n")
  local ok1, obj = pcall(function() return vim.json and vim.json.decode(txt) end)
  if ok1 and obj then return obj, txt end
  local ok2, obj2 = pcall(vim.fn.json_decode, txt)
  if ok2 and obj2 then return obj2, txt end
  return {}, txt
end

function M.write_json_file(path, tbl)
  local encoded
  if vim.json and vim.json.encode then encoded = vim.json.encode(tbl) else encoded = vim.fn.json_encode(tbl) end
  vim.fn.writefile(vim.split(encoded, "\n"), path)
end

function M.table_has_dotted_keys(t)
  for k, _ in pairs(t) do
    if type(k) == "string" and k:find("%.") then return true end
  end
  return false
end

function M.set_nested(tbl, parts, value)
  local cur = tbl
  for i = 1, #parts - 1 do
    local seg = parts[i]
    if type(cur[seg]) ~= "table" then cur[seg] = {} end
    cur = cur[seg]
  end
  cur[parts[#parts]] = value
end

function M.upsert_key_in_file(file, keypath, value)
  local obj = M.read_json_file(file)
  local data = obj
  if type(obj) == "table" and obj[1] ~= nil then data = {} end
  local flat_style = M.table_has_dotted_keys(data)
  if flat_style then
    data[keypath] = value
  else
    local parts = {}
    for seg in keypath:gmatch("[^%.]+") do table.insert(parts, seg) end
    M.set_nested(data, parts, value)
  end
  M.write_json_file(file, data)
end

return M
