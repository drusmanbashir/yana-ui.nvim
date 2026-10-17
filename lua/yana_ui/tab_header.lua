-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- WIDGETS TABS: native winbar adapter; tab identities and selection belong to YTabBar.
local api=vim.api
local Metrics=require('yana_ui.text_metrics')
local Input=require('yana_ui.input')
local Action=require('yana_ui.action')
local Style=require('yana_ui.style')
local M={}
local windows,clicks,serial={},{},0
local function escape(s) return s:gsub('%%','%%%%') end
local function live(m)
  return windows[m.win]==m and not m.suspended and not m.bar:is_destroyed() and api.nvim_win_is_valid(m.win)
end
local function token(m,identity,kind)
  local entry=m.ids[identity]
  if not entry then entry={}; m.ids[identity]=entry end
  if not entry[kind] then
    serial=serial+1; entry[kind]=serial
    clicks[serial]={mount=m,identity=identity,kind=kind}
  end
  return entry[kind]
end
local function linked(id,text,group)
  return '%'..id..'@v:lua.YanaUiTabHeaderClick@%#'..group..'#'..escape(text)..'%X'
end
function M.owns(win) return windows[win]~=nil and not windows[win].suspended end
function M.refresh(m)
  if windows[m.win]~=m or m.bar:is_destroyed() or not api.nvim_win_is_valid(m.win) or m.refreshing then return end
  m.refreshing=true
  local retained={}
  for _,tab in ipairs(m.bar._tabs) do
    retained[tab]=true; token(m,tab,'select'); token(m,tab,'close')
  end
  local corner=m.opts.corner and m.opts.corner(m.bar:currentIndex()) or {}
  assert(type(corner)=='table','corner must return actions')
  m.corner={}
  for _,action in ipairs(corner) do
    assert(getmetatable(action)==Action,'corner requires YAction')
    assert(not action:label():find('[\r\n]'),'corner labels must be single line')
    if not action:is_destroyed() then
      retained[action]=true; token(m,action,'action'); m.corner[#m.corner+1]=action
      if not m.connections[action] then
        m.connections[action]={action:connect('changed',m.bar,function() M.refresh(m) end),
          action:connect('destroyed',m.bar,function() M.refresh(m) end)}
      end
    end
  end
  for identity,ids in pairs(m.ids) do
    if not retained[identity] then
      for _,id in pairs(ids) do clicks[id]=nil end
      m.ids[identity]=nil
      for _,connection in ipairs(m.connections[identity] or {}) do identity:disconnect(connection) end
      m.connections[identity]=nil
    end
  end
  m.status=m.opts.status and m.opts.status(m.bar:currentIndex()) or ''
  assert(type(m.status)=='string' or m.status==nil,'status must return text or nil')
  m.status=m.status or ''; assert(not m.status:find('[\r\n]'),'status must be single line')
  m.refreshing=false
  if not m.suspended then api.nvim__redraw({win=m.win,winbar=true})end
end
function M.render(win)
  local m=windows[win]
  -- %{} evaluates in the drawn window; statusline_winid exists only for %!.
  if not m or not live(m) or api.nvim_get_current_win()~=win then return '' end
  local width=api.nvim_win_get_width(win)
  local groups=m.groups
  local corner,corner_width={},0
  for _,action in ipairs(m.corner) do
    if not action:is_destroyed() then
      local label=' '..action:label()..' '
      corner_width=corner_width+Metrics.width(label)
      corner[#corner+1]=linked(m.ids[action].action,label,action:is_enabled() and groups.button or groups.disabled)
    end
  end
  local available=math.max(0,width-corner_width)
  local hint=0
  for i,tab in ipairs(m.bar._tabs) do hint=hint+Metrics.width(tab.text)+2+(m.bar:isTabClosable(i-1) and 2 or 0) end
  local status_width=math.min(Metrics.width(m.status)+2,math.max(0,available-hint))
  local line,spans=m.bar:_compose(math.max(0,available-status_width))
  local parts={}
  for _,span in ipairs(spans) do
    local tab=m.bar._tabs[span.index+1]; local ids=m.ids[tab]
    local group=span.index==m.bar:currentIndex() and groups.active or groups.inactive
    local part=line:sub(span.start_byte+1,span.end_byte)
    if span.close_col then
      local close=Metrics.byte_at_display(part,span.close_col-span.col+1)+1
      parts[#parts+1]=linked(ids.select,part:sub(1,close-1),group)
      parts[#parts+1]=linked(ids.close,'×',group)
      parts[#parts+1]=linked(ids.select,part:sub(close+#'×'),group)
    else parts[#parts+1]=linked(ids.select,part,group) end
  end
  if status_width>0 then parts[#parts+1]='%#'..groups.subtitle..'#'..escape(Metrics.elide('  '..m.status,status_width)) end
  parts[#parts+1]='%#'..groups.normal..'#%='; parts[#parts+1]=table.concat(corner); parts[#parts+1]='%#'..groups.normal..'#'
  return table.concat(parts)
end
_G.YanaUiTabHeaderClick=function(id,count,button)
  local entry=clicks[id]; local m=entry and entry.mount
  if not m or not live(m) or button~='l' or count~=1 or not m.bar:is_enabled()
    or vim.fn.getmousepos().winid~=m.win then return end
  if entry.kind=='action' then
    if m.ids[entry.identity] then entry.identity:trigger() end
    return
  end
  local index
  for i,tab in ipairs(m.bar._tabs) do if tab==entry.identity then index=i-1; break end end
  if index==nil then return end
  if entry.kind=='close' then m.bar:requestClose(index)
  else
    m.bar:emit('tabBarClicked',index)
    if live(m) then
      for i,tab in ipairs(m.bar._tabs) do if tab==entry.identity then m.bar:setCurrentIndex(i-1); break end end
    end
  end
end
function M.mount(bar,win,opts)
  assert(type(win)=='number' and api.nvim_win_is_valid(win),'expected native window')
  opts=opts or {}; assert(type(opts)=='table','expected header options')
  for _,name in ipairs({'corner','status'}) do assert(opts[name]==nil or type(opts[name])=='function','invalid '..name) end
  assert(opts.groups==nil or type(opts.groups)=='table','invalid header groups')
  local groups=vim.tbl_extend('force',{},Style._tab_groups)
  for role,name in pairs(opts.groups or {}) do
    assert(groups[role] and type(name)=='string' and name:match('^[%w_.@]+$'),'invalid header highlight role')
    groups[role]=name
  end
  assert(not windows[win] and not bar._header,'header already mounted')
  local m={bar=bar,win=win,opts=opts,groups=groups,old=vim.wo[win].winbar,ids={},connections={}}
  m.expression='%{%v:lua.require\'yana_ui.tab_header\'._render('..win..')%}'
  windows[win],bar._header=m,m
  m.group=api.nvim_create_augroup('YTabHeader'..bar.id,{clear=true})
  api.nvim_create_autocmd('WinClosed',{group=m.group,callback=function(event)
    if tonumber(event.match)==win then bar:unmount_header() end
  end})
  api.nvim_create_autocmd('WinNew',{group=m.group,callback=function()
    for _,other in ipairs(api.nvim_list_wins()) do
      if other~=win and vim.wo[other].winbar==m.expression then vim.wo[other].winbar=m.old end
    end
  end})
  -- Shared intake owns mouse options; native winbar callbacks handle clicks.
  Input.acquire(m,function() return false end)
  local ok,why=pcall(M.refresh,m)
  if not ok then M.unmount(bar); error(why) end
  vim.wo[win].winbar=m.expression
  return true
end
function M.reassert(bar)
  local m=bar._header
  if m and live(m) then vim.wo[m.win].winbar=m.expression end
end
-- COLLAPSE: retain identities while relinquishing the still-owned native strip.
function M.suspend(bar)
  local m=bar._header
  if not m then return false,'header is not mounted'end
  if m.suspended then return false end
  if not live(m) or vim.wo[m.win].winbar~=m.expression then return false,'foreign header'end
  m.suspended=true
  local changed,reason=pcall(api.nvim_set_option_value,"winbar",m.old,{win=m.win})
  if not changed then m.suspended=nil;error(reason,0)end
  Input.release(m)
  return true
end
function M.resume(bar)
  local m=bar._header
  if not m or not api.nvim_win_is_valid(m.win) then return false,'header is not mounted'end
  if not m.suspended then return false end
  local current=vim.wo[m.win].winbar
  if current~='' and current~=m.old then return false,'foreign header'end
  local changed,reason=pcall(function()
    api.nvim_set_option_value("winbar",m.expression,{win=m.win})
    m.suspended=nil
    Input.acquire(m,function()return false end)
    M.refresh(m)
  end)
  if not changed then
    m.suspended=true;Input.release(m)
    pcall(api.nvim_set_option_value,"winbar",current,{win=m.win})
    error(reason,0)
  end
  return true
end
function M.unmount(bar)
  local m=bar._header; if not m then return false end
  bar._header=nil; windows[m.win]=nil
  if m.group then api.nvim_del_augroup_by_id(m.group) end
  Input.release(m)
  for _,ids in pairs(m.ids) do for _,id in pairs(ids) do clicks[id]=nil end end
  for action,connections in pairs(m.connections) do for _,connection in ipairs(connections) do action:disconnect(connection) end end
  if api.nvim_win_is_valid(m.win) and vim.wo[m.win].winbar==m.expression then vim.wo[m.win].winbar=m.old end
  return true
end
function M._render(win)
  local ok,result=pcall(M.render,win)
  return ok and result or ''
end
return M
