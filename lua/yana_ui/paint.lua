local M = {}

local function marks(buf, ns)
  return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
end

local function normalize(buf, mark)
  local details = mark[4] or {}
  local row = mark[2]
  local end_row = details.end_row or row
  local end_col = details.end_col
  if not end_col then
    local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    end_col = details.hl_eol and #line or (mark[3] + 1)
  end
  return {
    id = mark[1],
    line = row + 1,
    byte_col = mark[3],
    end_line = end_row + 1,
    end_byte_col = end_col,
    hl_group = details.hl_group,
    priority = details.priority or 0,
    hl_mode = details.hl_mode,
  }
end

local function contains(mark, line, byte_col)
  if line < mark.line or line > mark.end_line then return false end
  if line == mark.line and byte_col < mark.byte_col then return false end
  if line == mark.end_line and byte_col >= mark.end_byte_col then return false end
  return true
end

--- Return the highest-priority highlight covering a 1-based line and 0-based byte column.
function M.at(buf, ns, line, byte_col)
  local best, best_priority = nil, -math.huge
  for _, raw in ipairs(marks(buf, ns)) do
    local mark = normalize(buf, raw)
    if mark.hl_group and contains(mark, line, byte_col) and mark.priority >= best_priority then
      best, best_priority = mark.hl_group, mark.priority
    end
  end
  return best
end

--- Return whether one highlight group covers every byte cell in an inclusive line range.
function M.range(buf, ns, start_line, start_byte_col, end_line, end_byte_col, group)
  if end_line < start_line or (end_line == start_line and end_byte_col <= start_byte_col) then
    return false
  end
  for line = start_line, end_line do
    local first = line == start_line and start_byte_col or 0
    local last = line == end_line and end_byte_col or #vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
    for byte_col = first, last - 1 do
      if M.at(buf, ns, line, byte_col) ~= group then return false end
    end
  end
  return true
end

--- Return normalized extmark ranges carrying `group`, sorted by position.
function M.ranges(buf, ns, group)
  local out = {}
  for _, raw in ipairs(marks(buf, ns)) do
    local mark = normalize(buf, raw)
    if mark.hl_group == group then out[#out + 1] = mark end
  end
  table.sort(out, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    if a.byte_col ~= b.byte_col then return a.byte_col < b.byte_col end
    return a.id < b.id
  end)
  return out
end

return M
