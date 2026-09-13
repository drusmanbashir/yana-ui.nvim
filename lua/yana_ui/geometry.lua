local M = {}

local function info(win)
  local row = vim.fn.getwininfo(win)[1]
  if not row then return nil end
  local config = vim.api.nvim_win_get_config(win)
  return {
    win = win,
    buf = vim.api.nvim_win_get_buf(win),
    row = row.winrow,
    col = row.wincol,
    width = row.width,
    height = row.height,
    relative = config.relative,
    config = config,
  }
end

--- Return comparable geometry for every window in a tabpage.
function M.list(tabpage)
  tabpage = tabpage or 0
  local out = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    local item = info(win)
    if item then out[#out + 1] = item end
  end
  table.sort(out, function(a, b)
    if a.col ~= b.col then return a.col < b.col end
    return a.row < b.row
  end)
  return out
end

--- Return one window's geometry, or nil when it no longer exists.
function M.get(win)
  return info(win)
end

--- Resolve a 1-based screen cell to local window coordinates.
function M.cell(win, screen_row, screen_col)
  local item = info(win)
  if not item then return nil end
  if screen_row < item.row or screen_row >= item.row + item.height then return nil end
  if screen_col < item.col or screen_col >= item.col + item.width then return nil end
  return {
    win = win,
    buf = item.buf,
    screen_row = screen_row,
    screen_col = screen_col,
    row = screen_row - item.row + 1,
    col = screen_col - item.col + 1,
  }
end

--- Resolve a 1-based buffer position to its painted screen position.
function M.screenpos(win, line, column)
  if not info(win) then return nil end
  local pos = vim.fn.screenpos(win, line, column)
  if not pos or pos.row == 0 or pos.col == 0 then return nil end
  return { win = win, line = line, column = column, row = pos.row, col = pos.col }
end

return M
