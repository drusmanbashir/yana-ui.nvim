-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
---@alias PaintRange {id: integer, line: integer, byte_col: integer, end_line: integer, end_byte_col: integer, hl_group: string|string[], priority: integer, hl_mode: string|nil}
--
---@class paint
---@doc brief Inspect native buffer highlight ranges without changing them.
---@doc qt QPainter inspection. You read Neovim extmarks; this helper does not draw or own buffers.
---@doc inherits none; this module has no properties or signals.
---@doc errors Native Neovim API errors propagate for invalid buffer or namespace handles. Lines are one-based; byte columns are zero-based, with an exclusive end column. There is no destruction error or object lifetime.
---@doc context lua/yana_ui/paint.lua|paint
---@doc setup Copy the Lua comments between the DOCS markers, remove their leading --, and run them in Neovim with yana-ui on runtimepath. You create and delete only the scratch buffer used below; the namespace is shared by name.
---@doc example local ui = require("yana_ui")
---@doc example local buf = vim.api.nvim_create_buf(false, true)
---@doc example local ns = vim.api.nvim_create_namespace("YanaPaintExample")
---@doc example vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Ready" })
---@doc example vim.api.nvim_buf_set_extmark(buf, ns, 0, 0,
---@doc example   { end_col = 5, hl_group = "Title" })
---@doc example print(ui.paint.at(buf, ns, 1, 0))
---@doc example vim.api.nvim_buf_delete(buf, { force = true })
---@doc see |YPaintWriter|, |nvim_buf_get_extmarks()|.
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
---Read the highest-priority covering highlight. Equal priorities use the last
---matching mark in native enumeration order; an uncovered byte returns nil.
---@param buf integer Buffer handle; 0 selects the current buffer.
---@param ns integer Namespace handle; -1 searches all namespaces.
---@param line integer One-based line.
---@param byte_col integer Zero-based byte column.
---@return string|string[]|nil group # Native highlight group value, or nil if uncovered.
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
---Check every byte in the range against at(); start and end lines are included
---and the final byte column is excluded. Empty or reversed ranges return false;
---intermediate lines with no bytes impose no coverage requirement.
---@param buf integer Buffer handle; 0 selects the current buffer.
---@param ns integer Namespace handle; -1 searches all namespaces.
---@param start_line integer One-based first line.
---@param start_byte_col integer Zero-based inclusive first byte.
---@param end_line integer One-based last line.
---@param end_byte_col integer Zero-based exclusive final byte.
---@param group string|string[] Expected native highlight group value; compared with Lua equality.
---@return boolean covered # True when every inspected byte has that group.
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
---Read normalized ranges for exactly one highlight group, sorted by line,
---byte column and mark id. Native positions are converted to one-based lines.
---@param buf integer Buffer handle; 0 selects the current buffer.
---@param ns integer Namespace handle; -1 searches all namespaces.
---@param group string|string[] Native highlight group value; compared with Lua equality.
---@return PaintRange[] ranges # Matching ranges; an empty array when none match.
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
-- DOCS: paint example start
-- local ui = require("yana_ui")
-- local buf = vim.api.nvim_create_buf(false, true)
-- local ns = vim.api.nvim_create_namespace("YanaPaintExample")
-- vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Ready" })
-- vim.api.nvim_buf_set_extmark(buf, ns, 0, 0,
--   { end_col = 5, hl_group = "Title" })
-- print(ui.paint.at(buf, ns, 1, 0))
-- vim.api.nvim_buf_delete(buf, { force = true })
-- DOCS: paint example end
