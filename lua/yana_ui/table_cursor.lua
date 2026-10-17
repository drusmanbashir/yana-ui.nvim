-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- TV-S10/ST-03: capture before row/column replacement; restore after checked paint.
local Metrics=require('yana_ui.text_metrics')
local Geometry=require('yana_ui.geometry')
local Cursor={}
function Cursor.capture(view)
  local m=view._mount
  if not view:_valid(m)then return end
  local native=vim.api.nvim_win_call(m.win,vim.fn.winsaveview)
  local row=view._rows[native.lnum-2]
  if not row then return end
  local line=vim.api.nvim_buf_get_lines(m.buf,native.lnum-1,native.lnum,false)[1]or''
  local cell=Metrics.cell_at_byte(line,native.col)-1+(native.coladd or 0)
  local start,column,offset=0,nil,0
  for _,c in ipairs(view._columns)do
    local edge=start+view._widths[c.id]
    if cell>=start and cell<=edge then column,offset=c.id,cell-start;break end
    start=edge+1
  end
  return {mount=m,row_id=row.id,column_id=column,offset=offset,cell=cell,relative=native.lnum-native.topline,topline=native.topline,leftcol=native.leftcol}
end
function Cursor.restore(view,m,anchor,native)
  if not anchor or anchor.mount~=m then return false end
  local index
  for i,row in ipairs(view._rows)do if row.id==anchor.row_id then index=i;break end end
  if not index then return false end
  -- Past the last column (column_id nil): keep the display cell, not cell 0.
  local cell,start=anchor.column_id==nil and anchor.cell or 0,0
  for _,column in ipairs(view._columns)do
    if column.id==anchor.column_id then cell=start+math.min(anchor.offset,view._widths[column.id]-1);break end
    start=start+view._widths[column.id]+1
  end
  native.lnum=index+2
  local height=Geometry.get(m.win).height
  local last_top=math.max(1,vim.api.nvim_buf_line_count(m.buf)-height+1)
  -- ST-03: hold topline while the record stays visible; else keep its viewport row.
  local top=anchor.topline
  if native.lnum<top or native.lnum>=top+height then top=native.lnum-anchor.relative end
  native.topline=math.min(last_top,math.max(1,top))
  native.leftcol=anchor.leftcol
  local line=vim.api.nvim_buf_get_lines(m.buf,native.lnum-1,native.lnum,false)[1]or''
  native.col,native.coladd=Metrics.byte_at_display(line,cell+1),0
  return true
end
return Cursor
