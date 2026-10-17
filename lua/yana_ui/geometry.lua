-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
---@class YWindowGeometry
---@field win integer Native window handle.
---@field buf integer Displayed buffer handle.
---@field row integer One-based top screen row of the text area.
---@field col integer One-based left screen column of the text area.
---@field width integer Text-area width in cells.
---@field height integer Text-area height in cells.
---@field relative string Native floating-window relative mode; empty for a split.
---@field config table Native nvim_win_get_config result.
---@class YWindowCell
---@field win integer Window handle.
---@field buf integer Buffer handle.
---@field screen_row integer One-based input screen row.
---@field screen_col integer One-based input screen column.
---@field row integer One-based row within the text area.
---@field col integer One-based column within the text area.
---@class YScreenPosition
---@field win integer Window handle.
---@field line integer One-based buffer line.
---@field column integer One-based byte column in the buffer.
---@field row integer One-based painted screen row.
---@field col integer One-based painted screen column.
---@class geometry
---@doc brief Read native window geometry and convert screen and buffer positions.
---@doc qt QWidget geometry helpers. Neovim owns the windows; you read current text-area coordinates instead of storing an arrangement. Screen cells are one-based, unlike YLayout rectangles.
---@doc inherits none; this module has no constructor options, properties or signals.
---@doc errors Neovim argument errors propagate. get(), cell() and screenpos() return nil when getwininfo has no entry; cell() also returns nil outside the text area and screenpos() returns nil for an unpainted position.
---@doc context lua/yana_ui/geometry.lua|geometry
---@doc setup With your checkout on runtimepath, run this excerpt in Neovim. It reads the current window and owns no resources.
---@doc example local geometry = require("yana_ui").geometry
---@doc example local win = vim.api.nvim_get_current_win()
---@doc example local bounds = assert(geometry.get(win))
---@doc example local cell = assert(geometry.cell(win, bounds.row, bounds.col))
---@doc example assert(cell.row == 1 and cell.col == 1)
---@doc see |YLayout|, |YPanelHost|, |YTextMetrics|.
local M = {}
local metrics = require("yana_ui.text_metrics")

local function edge(border, index)
  if type(border) ~= "table" then return 0 end
  local value = border[index]
  if type(value) == "table" then value = value[1] end
  return value and value ~= "" and 1 or 0
end

local function info(win)
  local row = vim.fn.getwininfo(win)[1]
  if not row then return nil end
  local config = vim.api.nvim_win_get_config(win)
  return {
    win = win,
    buf = vim.api.nvim_win_get_buf(win),
    row = row.winrow + edge(config.border, 2) + row.winbar,
    col = row.wincol + edge(config.border, 8) + row.textoff,
    width = row.width - row.textoff,
    height = row.height,
    relative = config.relative,
    config = config,
  }
end

--- Return comparable geometry for every window in a tabpage.
---Read windows in a tabpage, sorted by screen column and then screen row.
---@param tabpage? integer [default: 0] Native tabpage handle; zero selects the current tab.
---@return YWindowGeometry[] windows # Current geometries; absent entries are skipped.
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
---Read one window without retaining its geometry.
---@param win integer Native window handle.
---@return YWindowGeometry|nil geometry # Current geometry, or nil when absent.
function M.get(win)
  return info(win)
end

--- Resolve a 1-based screen cell to local window coordinates.
---Convert a screen cell into text-area coordinates; borders and cells outside are excluded.
---@param win integer Native window handle.
---@param screen_row integer One-based screen row.
---@param screen_col integer One-based screen column.
---@return YWindowCell|nil cell # Local cell, or nil when absent or outside.
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

---Resolve a native pointer to content and convert its byte column once.
---Border, winbar, footer and foreign-window positions return nil.
---@param win integer Owned native window.
---@param pos table Native getmousepos() event.
---@return YWindowCell|nil cell # Content cell with buffer line and one-based display_col.
function M.pointer(win, pos)
  if pos.winid ~= win then return nil end
  local cell = M.cell(win, pos.screenrow, pos.screencol)
  if not cell or pos.line <= 0 or pos.column <= 0 then return nil end
  local text = vim.api.nvim_buf_get_lines(cell.buf, pos.line - 1, pos.line, false)[1]
  if not text then return nil end
  local point = M.screenpos(win,pos.line,pos.column)
  if not point or point.row ~= pos.screenrow then return nil end
  cell.line = pos.line
  cell.display_col = metrics.cell_at_byte(text, pos.column - 1) + (pos.coladd or 0)
  return cell
end

--- Resolve a 1-based buffer position to its painted screen position.
---Resolve a buffer position through Neovim screenpos(); offscreen positions return nil.
---@param win integer Native window handle.
---@param line integer One-based buffer line.
---@param column integer One-based byte column.
---@return YScreenPosition|nil position # Painted position, or nil when unpainted or absent.
function M.screenpos(win, line, column)
  if not info(win) then return nil end
  local pos = vim.fn.screenpos(win, line, column)
  if not pos or pos.row == 0 or pos.col == 0 then return nil end
  return { win = win, line = line, column = column, row = pos.row, col = pos.col }
end

-- DOCS: geometry example start
-- local geometry = require("yana_ui").geometry
-- local win = vim.api.nvim_get_current_win()
-- local bounds = assert(geometry.get(win))
-- local cell = assert(geometry.cell(win, bounds.row, bounds.col))
-- assert(cell.row == 1 and cell.col == 1)
-- DOCS: geometry example end
return M
