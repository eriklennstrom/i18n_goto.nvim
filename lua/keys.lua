local M = {}

function M.key_under_cursor(patterns)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()

  for _, pat in ipairs(patterns) do
    local s, e, cap = line:find(pat)
    if s and e and cap and col >= (s - 1) and col <= (e - 1) then return cap end
  end
  for _, pat in ipairs(patterns) do
    local _, _, cap = line:find(pat)
    if cap then return cap end
  end

  local before, after = line:sub(1, col + 1), line:sub(col + 2)
  local lb, rb = before:find("['\"][^'\"]*$"), after:find("[\"']")
  if lb and rb then
    local s, e = lb + 1, col + rb
    local cand = line:sub(s, e - 1)
    if cand:match("^[%w%._%-]+$") then return cand end
  end
end

return M
