-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- WIDGETS CM-01..08: checked invocation data; input and focus own lifetimes.
local geometry = require("yana_ui.geometry")
local M = {}
local records = setmetatable({}, {__mode="k"})
local function source(binding)
  if not binding.active or binding.dispatcher:is_destroyed() then return end
  local win, buf, generation = binding.target()
  if buf ~= binding.buf or type(win) ~= "number" or not vim.api.nvim_win_is_valid(win)
    or not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_win_get_buf(win) ~= buf
    or vim.api.nvim_win_get_tabpage(win) ~= vim.api.nvim_get_current_tabpage()
    or not (type(generation) == "string" or type(generation) == "number") then return end
  return win, buf, generation
end
function M.capture(binding, pos)
  local win, buf, generation = source(binding)
  if not win then return end
  local cursor = vim.api.nvim_win_get_cursor(win)
  local line, byte_col = cursor[1], cursor[2]
  if pos then
    if pos.winid ~= win or not pos.content then return end
    line, byte_col = pos.line, pos.column-1
  elseif vim.api.nvim_get_current_win() ~= win then return end
  local point = geometry.screenpos(win,line,byte_col+1)
  if not point or not geometry.cell(win,point.row,point.col) then return end
  local invocation = {reason=pos and "pointer" or "keyboard", win=win, buf=buf,
    generation=generation, line=line, byte_col=byte_col}
  local row, col = point.row, point.col
  if pos then row, col = pos.screenrow, pos.screencol end
  records[invocation] = {binding=binding, fields=vim.deepcopy(invocation),
    cursor=cursor, point=point, row=row, col=col}
  return invocation
end
function M.source_valid(invocation, dispatcher)
  local record = records[invocation]
  if not record or record.binding.dispatcher ~= dispatcher
    or not vim.deep_equal(invocation,record.fields) then return false end
  local win, buf, generation = source(record.binding)
  return win == invocation.win and buf == invocation.buf and generation == invocation.generation
end
function M.valid(invocation, dispatcher)
  if not M.source_valid(invocation,dispatcher) then return false end
  local record = records[invocation]
  local win = invocation.win
  local point = geometry.screenpos(win,invocation.line,invocation.byte_col+1)
  return point ~= nil and point.row == record.point.row and point.col == record.point.col
    and geometry.cell(win,record.row,record.col) ~= nil
end
function M.rectangle(invocation, dispatcher)
  if not M.valid(invocation,dispatcher) then return end
  local record = records[invocation]
  local top = record.row-1
  return {top=top,left=record.col-1,bottom=invocation.reason == "keyboard" and top+1 or top}
end
function M.opener(invocation, dispatcher)
  local record = records[invocation]
  return {win=invocation.win,buf=invocation.buf,cursor=record.cursor,valid=true,
    eligible=function() return M.source_valid(invocation,dispatcher) end}
end
return M
