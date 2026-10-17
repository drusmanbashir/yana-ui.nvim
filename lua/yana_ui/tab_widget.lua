-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-FileCopyrightText: 2016 The Qt Company Ltd.
-- SPDX-License-Identifier: LGPL-3.0-only
-- Derived from qtbase v6.8.4-lts-lgpl src/widgets/widgets/qtabwidget.cpp:
-- 435-445,627-633,750-780. Bar owns selection; pages follow its indexes.
-- WIDGETS TABS: supplied native windows stay fixed; buffers remain borrowed.
local Widget=require('yana_ui.widget')
local Object=require('yana_ui.object')
local Bar=require('yana_ui.tab_bar')
local YTabWidget=setmetatable({}, {__index=Widget}); YTabWidget.__index=YTabWidget
local api=vim.api
local function set_buffer(win,buf)
  local locked=vim.wo[win].winfixbuf
  vim.wo[win].winfixbuf=false
  local ok,why=pcall(api.nvim_win_set_buf,win,buf)
  if api.nvim_win_is_valid(win) then vim.wo[win].winfixbuf=locked end
  if not ok then error(why,0) end
end
local function index(i) assert(type(i)=='number' and i==math.floor(i),'expected tab index') end
local function page(value)
  assert((type(value)=='number' and api.nvim_buf_is_valid(value)) or
    (Widget.is_instance(value) and not value:is_destroyed()),'expected live widget or buffer')
end
---@class YTabWidgetOptions : YWidgetOptions
---@field tabsClosable? boolean [default: false] Default forwarded to the bar.
---@class YTabWidget : YWidget
---@doc brief One tab strip above a supplied page window, switched in place.
---@doc qt QTabWidget. Widget pages are parent-owned, native buffer pages borrowed. mount accepts two existing windows; YPanelHost or the consumer creates their arrangement. Duplicate addTab selects the existing page. SelectPreviousTab is the default to return from on-demand pages. No Qt pixel shapes, corner controls or native tabpage switching.
---@doc inherits |YWidget|.
---@doc errors Invalid indexes, labels, page identities, native windows or header providers raise assertions. A second mount raises. Native errors and provider errors propagate. Removed widget pages survive without their former parent; native pages remain borrowed.
---@doc destroyed addTab,insertTab,removeTab,setCurrentIndex,setTabText,setTabsClosable,setTabClosable,mount,mount_header,suspend,resume
---@doc setup Run in Neovim with yana-ui on runtimepath. The example borrows the current window, owns one page buffer and restores the window before cleanup.
---@doc context lua/yana_ui/tab_widget.lua|YTabWidget
-- DOCS: YTabWidget example start
---@doc example local tabs = require('yana_ui.tab_widget').new()
---@doc example local page = vim.api.nvim_create_buf(false,true)
---@doc example vim.api.nvim_buf_set_lines(page,0,-1,false,{'Application Output'})
---@doc example tabs:addTab(page,'Application Output')
---@doc example tabs:mount_header(vim.api.nvim_get_current_win())
---@doc example tabs:unmount(); tabs:destroy()
---@doc example vim.api.nvim_buf_delete(page,{force=true})
-- DOCS: YTabWidget example end
---Construct a page container with an owned tab bar.
---@doc see |YTabBar|, |YPanelHost|.
---@doc property currentIndex|currentIndex()|setCurrentIndex(index)|currentChanged|-1
---@doc property tabsClosable|tabsClosable()|setTabsClosable(value)|none|option:tabsClosable
---@signal currentChanged(index: integer) | Forwarded after the selected page has been shown.
---@signal tabCloseRequested(index: integer) | Forwarded request; consumers call removeTab.
---@signal tabBarClicked(index: integer) | Forwarded strip click.
---@param opts? YTabWidgetOptions Optional parent and default close buttons.
---@return YTabWidget
function YTabWidget.new(opts)
  opts=opts or {}; assert(type(opts)=='table','expected tab widget options')
  if opts.tabsClosable~=nil then Object.boolean(opts.tabsClosable) end
  local self=setmetatable(Widget.new({parent=opts.parent}),YTabWidget)
  self._pages={}
  self._bar=Bar.new({parent=self,tabsClosable=opts.tabsClosable,selectionBehaviorOnRemove='SelectPreviousTab'})
  self._bar:connect('currentChanged',self,function(w,i) w:_sync(); w:emit("currentChanged",i) end)
  self._bar:connect('tabCloseRequested',self,function(w,i) w:emit("tabCloseRequested",i) end)
  self._bar:connect('tabBarClicked',self,function(w,i) w:emit("tabBarClicked",i) end)
  self._bar:connect('tabMoved',self,function(w,from,to)
    table.insert(w._pages,to+1,table.remove(w._pages,from+1)); w:_sync()
  end)
  return self
end
---Read the owned tab bar.
---@return YTabBar
function YTabWidget:tabBar() return self._bar end
---Read the number of tabs.
---@return integer
function YTabWidget:count() return #self._pages end
---Read the selected zero-based index; empty models return -1.
---@return integer
function YTabWidget:currentIndex() return self._bar:currentIndex() end
---Read whether a native presentation is attached.
---@return boolean mounted False after explicit unmount or native window closure.
function YTabWidget:is_mounted() return self._mount~=nil end
---Select a valid tab; unchanged or invalid positions do nothing.
---@param i integer Zero-based index.
---@return boolean
---@return string|nil reason
function YTabWidget:setCurrentIndex(i) return self._bar:setCurrentIndex(i) end
---Find a page by identity, returning -1 when absent.
---@param value YWidget|integer Page identity.
---@return integer index -1 when absent.
function YTabWidget:indexOf(value)
  for i,entry in ipairs(self._pages) do if entry.page==value then return i-1 end end
  return -1
end
---Read the page at a zero-based index.
---@param i integer Zero-based index.
---@return YWidget|integer|nil
function YTabWidget:widget(i) index(i); return self._pages[i+1] and self._pages[i+1].page end
---Read the selected page, or nil for an empty container.
---@return YWidget|integer|nil
function YTabWidget:currentWidget() return self:widget(self:currentIndex()) end
---Insert a borrowed buffer or reparented widget page; duplicates select the existing page.
---@param i integer Zero-based index; invalid positions append.
---@param value YWidget|integer Widget or borrowed native buffer.
---@param label string Single-line UTF-8.
---@return integer|false index
---@return string|nil reason
function YTabWidget:insertTab(i,value,label)
  index(i); page(value); require('yana_ui.push_button')._text(label)
  if self:is_destroyed() then return false,'destroyed' end
  local existing=self:indexOf(value)
  if existing>=0 then self:setCurrentIndex(existing); return existing end
  if Widget.is_instance(value) then
    local ancestor=self
    while ancestor do assert(ancestor~=value,'page ownership cycle'); ancestor=ancestor:parent() end
    value:set_parent(self); value:hide()
  end
  if i<0 or i>=#self._pages then i=#self._pages end
  local entry={page=value}; table.insert(self._pages,i+1,entry)
  if Widget.is_instance(value) then
    entry.connection=value:connect('destroyed',self,function(w)
      local found=w:indexOf(value); if found>=0 then w:removeTab(found) end
    end)
  end
  self._bar:insertTab(i,label); self:_sync(); return i
end
---Append a page; adding an existing page selects its existing membership.
---@param value YWidget|integer Page identity; repeated calls select it.
---@param label string Single-line label.
---@return integer|false index
---@return string|nil reason
function YTabWidget:addTab(value,label) return self:insertTab(-1,value,label) end
---Remove membership, release a widget parent and preserve the page.
---@param i integer Index to remove; removed widgets survive with no parent.
---@return boolean
---@return string|nil reason
function YTabWidget:removeTab(i)
  index(i); if self:is_destroyed() then return false,'destroyed' end
  local entry=self._pages[i+1]; if not entry then return false end
  table.remove(self._pages,i+1)
  if Widget.is_instance(entry.page) then
    entry.page:disconnect(entry.connection)
    if not entry.page:is_destroyed() then entry.page:hide(); entry.page:set_parent(nil) end
  end
  self._bar:removeTab(i); self:_sync(); return true
end
---Read a tab label; invalid positions return empty text.
---@param i integer Index.
---@return string
function YTabWidget:tabText(i) return self._bar:tabText(i) end
---Replace a tab label and refresh its presentation.
---@param i integer Index.
---@param label string Label.
---@return boolean
---@return string|nil reason
function YTabWidget:setTabText(i,label) return self._bar:setTabText(i,label) end
---Read the default close-button setting.
---@return boolean
function YTabWidget:tabsClosable() return self._bar:tabsClosable() end
---Change the default without replacing per-tab overrides.
---@param value boolean Default close buttons.
---@return boolean
---@return string|nil reason
function YTabWidget:setTabsClosable(value) return self._bar:setTabsClosable(value) end
---Override close permission for one tab.
---@param i integer Index.
---@param value boolean Per-tab override.
---@return boolean
---@return string|nil reason
function YTabWidget:setTabClosable(i,value) return self._bar:setTabClosable(i,value) end
function YTabWidget:_sync()
  if self:is_destroyed() then return end
  local selected=self:currentWidget()
  for _,entry in ipairs(self._pages) do
    if Widget.is_instance(entry.page) and not entry.page:is_destroyed() then entry.page:set_visible(entry.page==selected) end
  end
  local m=self._mount; if not m or m.syncing or m.suspended then return end
  if not api.nvim_win_is_valid(m.page_win) or (m.bar_win and (not api.nvim_win_is_valid(m.bar_win)
    or api.nvim_win_get_buf(m.bar_win)~=m.bar_buf)) or api.nvim_win_get_buf(m.page_win)~=m.shown_buf then
    self:unmount(); return
  end
  m.syncing=true
  local ok,why=pcall(function()
  if m.page_owner then m.page_owner:destroy(); m.page_owner=nil end
  local target_buf=type(selected)=='number' and selected or m.canvas
  if not api.nvim_buf_is_valid(target_buf) then target_buf=m.canvas end
  -- Native window options are remembered per buffer. Leave each former page
  -- with the borrowed value so a later visit cannot resurrect our expression.
  if m.header and vim.wo[m.page_win].winbar==m.header_expression then
    vim.wo[m.page_win].winbar=m.header_original
  end
  set_buffer(m.page_win,target_buf)
  if Widget.is_instance(selected) then
    local owner=Object.new({parent=m.owner}); m.page_owner=owner
    local function target() return m.page_win,m.canvas,1 end
    local focus=require('yana_ui.focus').new({parent=owner,current_target=target})
    local writer=require('yana_ui.paint_writer').new({parent=owner,win=m.page_win,buf=m.canvas,generation=1,current_target=target})
    local layout=require('yana_ui.box_layout').new({parent=owner})
    layout:add_widget(selected); layout:activate(0,0,api.nvim_win_get_width(m.page_win),api.nvim_win_get_height(m.page_win),1)
    -- A previous page writer was destroyed; this canvas remains toolkit-owned.
    writer:prepare(selected,{},{}); selected:update(); writer:flush()
    focus:register(selected,m.page_win,m.canvas,1)
    require('yana_ui.input').new({parent=owner,root=selected,focus=focus,writer=writer,current_target=target})
  end
  end)
  -- Native callbacks can raise after the buffer has changed. Reconcile the
  -- actual page and strip before propagating the original error.
  local recovered,recovery_error=pcall(function()
    if api.nvim_win_is_valid(m.page_win) then
      m.shown_buf=api.nvim_win_get_buf(m.page_win)
      if m.header then require('yana_ui.tab_header').reassert(self._bar) end
      if not ok then
        local shown=self:indexOf(m.shown_buf)
        if shown>=0 then self._bar:setCurrentIndex(shown) end
      end
    end
  end)
  m.syncing=false
  if not ok then error(why,0) end
  if not recovered then error(recovery_error,0) end
end
---Mount the strip in an existing page window's winbar. Borrowed pages and
---window geometry follow mount(); no extra window is created.
---@param page_win integer Existing page window.
---@param opts? YTabHeaderOptions [default: nil] Corner actions and status provider.
---@return boolean mounted
---@return string|nil reason Destruction refusal or nil.
function YTabWidget:mount_header(page_win,opts)
  assert(type(page_win)=='number' and api.nvim_win_is_valid(page_win),'expected native page window')
  if self:is_destroyed() then return false,'destroyed' end
  assert(not self._mount,'already mounted')
  local m={header=true,header_original=vim.wo[page_win].winbar,page_win=page_win,old_page=api.nvim_win_get_buf(page_win),
    canvas=api.nvim_create_buf(false,true),owner=Object.new({parent=self})}
  self._mount=m; m.shown_buf=m.old_page
  local ok,why=pcall(self._bar.mount_header,self._bar,page_win,opts)
  if not ok then self:unmount(); error(why) end
  m.header_expression=vim.wo[page_win].winbar
  m.group=api.nvim_create_augroup('YTabWidget'..self.id,{clear=true})
  api.nvim_create_autocmd({'WinClosed','BufWipeout','BufWinEnter'}, {group=m.group,callback=function(event)
    if self._mount~=m or m.syncing then return end
    if event.event=='WinClosed' and tonumber(event.match)==page_win
      or event.event=='BufWipeout' and event.buf==m.canvas then self:unmount()
    elseif event.event=='BufWipeout' then
      local found=self:indexOf(event.buf); if found>=0 then self:removeTab(found) end
    elseif event.event=='BufWinEnter' and (not api.nvim_win_is_valid(page_win)
      or (api.nvim_win_get_buf(page_win)~=m.shown_buf and api.nvim_win_get_buf(page_win)~=m.suspended)) then self:unmount() end
  end})
  self:show(); self:_sync(); return true
end
---Borrow separate strip and page windows without changing their geometry.
---@param bar_win integer Existing window above page_win; its buffer is restored on unmount.
---@param page_win integer Existing page window; switching never resizes it.
---@return boolean mounted
---@return string|nil reason
function YTabWidget:mount(bar_win,page_win)
  assert(type(bar_win)=='number' and api.nvim_win_is_valid(bar_win) and type(page_win)=='number'
    and api.nvim_win_is_valid(page_win) and bar_win~=page_win,'expected two distinct native windows')
  if self:is_destroyed() then return false,'destroyed' end
  assert(not self._mount,'already mounted')
  local m={bar_win=bar_win,page_win=page_win,old_bar=api.nvim_win_get_buf(bar_win),old_page=api.nvim_win_get_buf(page_win),
    bar_buf=api.nvim_create_buf(false,true),canvas=api.nvim_create_buf(false,true),owner=Object.new({parent=self})}
  self._mount=m; m.shown_buf=m.old_page
  set_buffer(bar_win,m.bar_buf)
  local function target() return bar_win,m.bar_buf,1 end
  local focus=require('yana_ui.focus').new({parent=m.owner,current_target=target})
  local style=require('yana_ui.style').new({focus=focus})
  m.writer=require('yana_ui.paint_writer').new({parent=m.owner,win=bar_win,buf=m.bar_buf,generation=1,current_target=target})
  local layout=require('yana_ui.box_layout').new({parent=m.owner}); layout:add_widget(self._bar)
  self:show(); focus:register(self._bar,bar_win,m.bar_buf,1)
  require('yana_ui.input').new({parent=m.owner,root=self._bar,focus=focus,writer=m.writer,current_target=target,
    keys={'<Left>','<Right>','<Home>','<End>','<Delete>','<Tab>','<S-Tab>'}})
  local function render()
    if self._mount~=m or self:is_destroyed() then return end
    if not api.nvim_win_is_valid(bar_win) or api.nvim_win_get_buf(bar_win)~=m.bar_buf then self:unmount(); return end
    layout:activate(0,0,api.nvim_win_get_width(bar_win),1,1)
    self._bar:prepare(m.writer,style); m.writer:flush(); self:_sync()
  end
  m.group=api.nvim_create_augroup('YTabWidget'..self.id,{clear=true})
  api.nvim_create_autocmd({'WinResized','VimResized'}, {group=m.group,callback=render})
  api.nvim_create_autocmd({'WinClosed','BufWipeout','BufWinEnter'}, {group=m.group,callback=function(event)
    if self._mount~=m or m.syncing then return end
    if event.event=='WinClosed' and (tonumber(event.match)==bar_win or tonumber(event.match)==page_win)
      or event.event=='BufWipeout' and (event.buf==m.bar_buf or event.buf==m.canvas) then self:unmount()
    elseif event.event=='BufWipeout' then
      local found=self:indexOf(event.buf); if found>=0 then self:removeTab(found) end
    elseif event.event=='BufWinEnter' and (not api.nvim_win_is_valid(page_win) or api.nvim_win_get_buf(page_win)~=m.shown_buf
      or not api.nvim_win_is_valid(bar_win) or api.nvim_win_get_buf(bar_win)~=m.bar_buf) then self:unmount() end
  end})
  render(); return true
end
---Suspend a native-header mount before its host installs a compact buffer.
---Retain pages, history and owned canvases; separate-strip mounts refuse.
---@param replacement_buf integer Live host-owned compact buffer permitted during suspension.
---@return boolean suspended True on transition; false on no-op or refusal.
---@return string|nil reason Destroyed, missing/header-only mount, stale target or foreign header.
function YTabWidget:suspend(replacement_buf)
  assert(type(replacement_buf)=='number' and api.nvim_buf_is_valid(replacement_buf),'expected replacement buffer')
  if self:is_destroyed()then return false,'destroyed'end
  local m=self._mount
  if not m then return false,'not mounted'end
  if not m.header then return false,'header mount required'end
  if m.suspended then return false,m.suspended~=replacement_buf and 'already suspended'or nil end
  if not api.nvim_win_is_valid(m.page_win) or api.nvim_win_get_buf(m.page_win)~=m.shown_buf then return false,'stale'end
  local ok,why=require('yana_ui.tab_header').suspend(self._bar)
  if not ok then return false,why end
  m.suspended=replacement_buf
  if m.page_owner then m.page_owner:destroy();m.page_owner=nil end
  return true
end
---Resume the selected current page into the still-owned native target.
---A foreign buffer/header is never replaced; a removed mount refuses.
---@return boolean resumed True on transition; false on no-op or refusal.
---@return string|nil reason Destroyed, missing mount, stale target or foreign header.
function YTabWidget:resume()
  if self:is_destroyed()then return false,'destroyed'end
  local m=self._mount
  if not m then return false,'not mounted'end
  if not m.suspended then return false end
  if not api.nvim_win_is_valid(m.page_win) then return false,'stale'end
  local current=api.nvim_win_get_buf(m.page_win)
  if current~=m.suspended and current~=m.shown_buf then return false,'stale'end
  local selected=self:currentWidget()
  local target=type(selected)=='number' and selected or m.canvas
  if not api.nvim_buf_is_valid(target)then return false,'stale page'end
  local ok,why=require('yana_ui.tab_header').resume(self._bar)
  if not ok then return false,why end
  m.syncing=true
  local changed,reason=pcall(set_buffer,m.page_win,target)
  m.syncing=false
  if not changed then require('yana_ui.tab_header').suspend(self._bar);error(reason,0)end
  m.shown_buf=target;m.suspended=nil
  self:_sync()
  return true
end
---Detach the current presentation and restore only still-owned native resources.
---@return boolean removed Restores only still-owned window buffers; borrowed pages survive.
function YTabWidget:unmount()
  local m=self._mount; if not m then return false end
  local header_value
  if m.header and api.nvim_win_is_valid(m.page_win) then
    header_value=vim.wo[m.page_win].winbar
    if header_value==m.header_expression then header_value=m.header_original end
  end
  self._mount=nil
  local first_error
  local function attempt(fn)
    local ok,why=pcall(fn)
    if not ok and first_error==nil then first_error=why end
  end
  attempt(function() if m.group then api.nvim_del_augroup_by_id(m.group) end end)
  attempt(function() if m.header then self._bar:unmount_header() end end)
  attempt(function() m.owner:destroy() end)
  local restore={{m.page_win,m.shown_buf,m.old_page}}
  if m.bar_win then restore[#restore+1]={m.bar_win,m.bar_buf,m.old_bar} end
  for _,entry in ipairs(restore) do
    attempt(function()
      if api.nvim_win_is_valid(entry[1]) and api.nvim_win_get_buf(entry[1])==entry[2] and api.nvim_buf_is_valid(entry[3]) then
        set_buffer(entry[1],entry[3])
      end
    end)
  end
  attempt(function()
    if header_value~=nil and api.nvim_win_is_valid(m.page_win) then vim.wo[m.page_win].winbar=header_value end
  end)
  for _,buf in ipairs({m.canvas,m.bar_buf}) do
    attempt(function() if api.nvim_buf_is_valid(buf) then api.nvim_buf_delete(buf,{force=true}) end end)
  end
  if first_error~=nil then error(first_error,0) end
  return true
end
function YTabWidget:_dispose() self:unmount() end
return YTabWidget
