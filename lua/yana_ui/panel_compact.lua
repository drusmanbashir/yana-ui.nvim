-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- COLLAPSE: owned content canvas; native placement remains in panel_host.
local Object=require('yana_ui.object')
local Widget=require('yana_ui.widget')
local Metrics=require('yana_ui.text_metrics')
local api=vim.api
local M={}
function M.new()
  local buf=api.nvim_create_buf(false,true)
  vim.bo[buf].buftype='nofile';vim.bo[buf].bufhidden='hide';vim.bo[buf].swapfile=false
  vim.bo[buf].filetype='yana_ui_compact';vim.bo[buf].modifiable=false
  return {buf=buf,epoch=0}
end
function M.release(entry)
  entry.epoch=entry.epoch+1;entry.armed=nil
  if entry.owner then entry.owner:destroy();entry.owner=nil end
end
function M.destroy(entry)
  M.release(entry)
  if api.nvim_buf_is_valid(entry.buf)then api.nvim_buf_delete(entry.buf,{force=true})end
end
function M.mount(entry,win,axis,valid,restore)
  if entry.owner and entry.win==win and not entry.owner:is_destroyed()then entry.axis=axis;return end
  M.release(entry);entry.win,entry.axis=win,axis
  local owner=Object.new();entry.owner=owner
  local epoch=entry.epoch
  local function target()
    if entry.owner==owner and entry.epoch==epoch and valid()then return win,entry.buf,epoch end
    return -1,-1,-1
  end
  local timer
  local widget=Widget.new{parent=owner,event=function(_,kind,row,col,button,key,_,pos)
    if not valid()then return false end
    if kind=='key'and(key=='<CR>'or key=='<Space>')then timer:stop();restore();return true end
    if kind=='press'and button==1 then
      timer:stop()
      entry.armed=(not pos or not pos.clicks or pos.clicks==1)and{row,col}or nil
      return true
    end
    if kind=='move'and button==1 then timer:stop();entry.armed=nil;return true end
    if kind=='release'and button==1 then
      local armed=entry.armed;entry.armed=nil
      if armed and armed[1]==row and armed[2]==col then timer:start(math.max(1,vim.o.mousetime))end
      return true
    end
    if kind=='wheel'then return true end
    if kind=='right'then timer:stop();entry.armed=nil end
    return kind=='right'or kind=='release'
  end}
  function widget:_grab_cancelled()entry.armed=nil end
  -- Wait for native click-count disambiguation so a double click cannot open the body.
  timer=require('yana_ui.timer').new{parent=owner,single_shot=true}
  timer:connect('timeout',owner,function()if valid()then restore()end end)
  entry.widget=widget
  local target_fn=target
  entry.layout=require('yana_ui.box_layout').new{parent=owner};entry.layout:add_widget(widget)
  entry.writer=require('yana_ui.paint_writer').new{parent=owner,win=win,buf=entry.buf,generation=epoch,current_target=target_fn}
  local focus=require('yana_ui.focus').new{parent=owner,current_target=target_fn}
  widget:show();focus:register(widget,win,entry.buf,epoch)
  entry.dispatcher=require('yana_ui.input').new{parent=owner,root=widget,focus=focus,writer=entry.writer,
    current_target=target_fn,keys={'<CR>','<Space>','<Esc>'}}
end
function M.paint(entry,title,group)
  assert(type(title)=='string'and not title:find('[\r\n%z]'),'compact title must be single-line text')
  group=group or'TabLine'
  assert(type(group)=='string'and group:match('^[%w_.@]+$'),'invalid compact highlight')
  local width,height=api.nvim_win_get_width(entry.win),api.nvim_win_get_height(entry.win)
  local lines,marks={},{}
  if entry.axis=='row'then
    lines[1]=' +'
    local count=vim.fn.strchars(title,true)
    for i=1,height-1 do
      lines[i+1]=i==height-1 and count>i and' …'or' '..Metrics.character(title,i-1)
    end
  else lines[1]=Metrics.cell_clip('+ '..title,width)end
  local appearance=api.nvim_get_hl_id_by_name(group)
  for i=1,height do
    lines[i]=Metrics.pad(Metrics.cell_clip(lines[i]or'',width),width)
    marks[i]={slot=i,row=i-1,start_byte=0,end_byte=#lines[i],appearance=appearance}
  end
  entry.writer:set_content_size(width,height)
  assert(entry.layout:activate(0,0,width,height,entry.epoch))
  entry.writer:prepare(entry.widget,lines,marks);entry.widget:update()
  assert(entry.writer:flush())
end
return M
