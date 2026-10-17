-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-FileCopyrightText: 2016 The Qt Company Ltd.
-- SPDX-License-Identifier: LGPL-3.0-only
-- Derived from qtbase v6.8.4-lts-lgpl src/widgets/widgets/qtabbar.cpp:
-- 956-1095,1402-1445,1991-2001,2009-2096,2366-2375; qtabbar_p.h:80,135.
-- WIDGETS TABS: independently expressed Lua index/history port; cell rendering.
local Widget = require('yana_ui.widget')
local Object = require('yana_ui.object')
local Metrics = require('yana_ui.text_metrics')
local Layout = require('yana_ui.layout')
local YTabBar = setmetatable({}, {__index=Widget}); YTabBar.__index=YTabBar
local behaviors={SelectRightTab=true,SelectLeftTab=true,SelectPreviousTab=true}
local function integer(i) assert(type(i)=='number' and i==math.floor(i), 'expected tab index') end
local function text(s) return require('yana_ui.push_button')._text(s) end
local function at(self,i) return self._tabs[i+1] end
local function remap(from,to,i)
  if i==from then return to end
  if i>=math.min(from,to) and i<=math.max(from,to) then return i+(from<to and -1 or 1) end
  return i
end
---@class YTabBarOptions : YWidgetOptions
---@field tabsClosable? boolean [default: false] Show close buttons unless a tab overrides it.
---@field selectionBehaviorOnRemove? string [default: "SelectRightTab"] SelectRightTab, SelectLeftTab or SelectPreviousTab.
---@class YTabBar : YWidget
---@doc brief A horizontal cell strip with zero-based Qt tab indexes.
---@doc qt QTabBar. Index/history logic follows Qt; no icons, drag reorder, vertical shapes, RTL or scroll buttons. Narrow labels use YTextMetrics and layout_axis; extremely narrow strips show the selected tab only. setTabClosable is a per-tab extension.
---@doc inherits |YWidget|.
---@doc errors Invalid indexes, labels, boolean options, selection behavior, native windows or header providers raise assertions. Header provider errors propagate during refresh. Invalid positions otherwise leave the tabs unchanged.
---@doc destroyed addTab,insertTab,removeTab,moveTab,setCurrentIndex,setTabText,setTabsClosable,setTabClosable,setSelectionBehaviorOnRemove,requestClose,prepare,mount_header
---@doc setup Run in Neovim with yana-ui on runtimepath. This state-only example owns and destroys its bar.
---@doc context lua/yana_ui/tab_bar.lua|YTabBar
-- DOCS: YTabBar example start
---@doc example local bar = require('yana_ui.tab_bar').new({tabsClosable=true})
---@doc example bar:addTab('Breakpoints'); bar:setTabClosable(0,false)
---@doc example bar:addTab('Registers'); bar:setCurrentIndex(1)
---@doc example bar:connect('tabCloseRequested',bar,function(self,i) self:removeTab(i) end)
---@doc example bar:requestClose(1); assert(bar:count()==1)
---@doc example bar:destroy()
-- DOCS: YTabBar example end
---Construct a tab model with the supplied owner and options.
---@doc see |YTabWidget|, |YAction|.
---@doc property currentIndex|currentIndex()|setCurrentIndex(index)|currentChanged|-1
---@doc property tabsClosable|tabsClosable()|setTabsClosable(value)|none|option:tabsClosable
---@signal currentChanged(index: integer) | Selection changes, including removal to the same numeric index; insert before current is silent as in Qt.
---@signal tabCloseRequested(index: integer) | An eligible close gesture requests removal; the consumer removes it.
---@signal tabBarClicked(index: integer) | Left press on a label, before currentChanged; -1 on empty strip.
---@signal tabMoved(from: integer, to: integer) | After index/history remapping, before currentChanged.
---@param opts? YTabBarOptions Constructor options; state-only use needs no canvas.
---@return YTabBar
function YTabBar.new(opts)
  opts=opts or {}; assert(type(opts)=='table','expected tab options')
  if opts.tabsClosable~=nil then Object.boolean(opts.tabsClosable) end
  assert(opts.selectionBehaviorOnRemove==nil or behaviors[opts.selectionBehaviorOnRemove],'invalid selection behavior')
  local self=setmetatable(Widget.new({parent=opts.parent,size_hint={width=0,height=1},
    maximum_size={width=2147483647,height=1}}),YTabBar)
  self._tabs,self._current,self._closable={},-1,opts.tabsClosable==true
  self._behavior=opts.selectionBehaviorOnRemove or 'SelectRightTab'
  return self
end
---Read the number of tabs.
---@return integer
function YTabBar:count() return #self._tabs end
---Read the selected zero-based index; empty models return -1.
---@return integer
function YTabBar:currentIndex() return self._current end
---Read the default close-button setting.
---@return boolean
function YTabBar:tabsClosable() return self._closable end
---Read the selection policy used when a current tab is removed.
---@return string
function YTabBar:selectionBehaviorOnRemove() return self._behavior end
---Change the selection policy for future removals.
---@param value string One of the three Select*Tab values.
---@return boolean
function YTabBar:setSelectionBehaviorOnRemove(value)
  assert(behaviors[value],'invalid selection behavior')
  if self:is_destroyed() then return false,'destroyed' end
  if self._behavior==value then return false end
  self._behavior=value; return true
end
---Insert a tab at the supplied position, preserving the selected identity.
---@param i integer Zero-based index; out of range appends.
---@param label string Single-line UTF-8.
---@return integer|false index
---@return string|nil reason
function YTabBar:insertTab(i,label)
  integer(i); text(label); if self:is_destroyed() then return false,'destroyed' end
  if i<0 or i>=#self._tabs then i=#self._tabs end
  table.insert(self._tabs,i+1,{text=label,last=-1})
  for _,tab in ipairs(self._tabs) do if tab.last>=i then tab.last=tab.last+1 end end
  if #self._tabs==1 then self:setCurrentIndex(i)
  elseif i<=self._current then self._current=self._current+1 end
  self:update(); return i
end
---Append a tab and select it only when the model was empty.
---@param label string Single-line UTF-8.
---@return integer|false index
---@return string|nil reason
function YTabBar:addTab(label) return self:insertTab(-1,label) end
---Select a valid tab; unchanged or invalid positions do nothing.
---@param i integer Zero-based valid index; others are ignored.
---@return boolean
---@return string|nil reason
function YTabBar:setCurrentIndex(i)
  integer(i); if self:is_destroyed() then return false,'destroyed' end
  if not at(self,i) or self._current==i then return false end
  local old=self._current; self._current=i
  if at(self,old) then at(self,i).last=old end
  self:update(); self:emit("currentChanged",i); return true
end
---Remove membership and select according to the configured removal policy.
---@param i integer Zero-based index.
---@return boolean
---@return string|nil reason
function YTabBar:removeTab(i)
  integer(i); if self:is_destroyed() then return false,'destroyed' end
  local removed=at(self,i); if not removed then return false end
  local next_index=removed.last; table.remove(self._tabs,i+1)
  for _,tab in ipairs(self._tabs) do
    if tab.last==i then tab.last=-1 elseif tab.last>i then tab.last=tab.last-1 end
  end
  if i==self._current then
    self._current=-1
    if #self._tabs==0 then self:emit("currentChanged",-1)
    else
      if next_index>i then next_index=next_index-1 end
      if self._behavior~='SelectPreviousTab' or not at(self,next_index) then
        next_index=math.max(0,math.min(i-(self._behavior=='SelectLeftTab' and 1 or 0),#self._tabs-1))
      end
      local previous=at(self,next_index).last
      self:setCurrentIndex(next_index)
      if not self:is_destroyed() and at(self,next_index) then at(self,next_index).last=previous end
    end
  elseif i<self._current then self:setCurrentIndex(self._current-1) end
  self:update(); return true
end
---Move membership and preserve the selected identity.
---@param from integer Source index.
---@param to integer Destination index.
---@return boolean
---@return string|nil reason
function YTabBar:moveTab(from,to)
  integer(from); integer(to); if self:is_destroyed() then return false,'destroyed' end
  if from==to or not at(self,from) or not at(self,to) then return false end
  table.insert(self._tabs,to+1,table.remove(self._tabs,from+1))
  for _,tab in ipairs(self._tabs) do tab.last=remap(from,to,tab.last) end
  local old=self._current; self._current=remap(from,to,old)
  self:update(); self:emit("tabMoved",from,to)
  if not self:is_destroyed() and old~=self._current then self:emit("currentChanged",self._current) end
  return true
end
---Read a tab label; invalid positions return empty text.
---@param i integer Zero-based index.
---@return string text Empty for an invalid index.
function YTabBar:tabText(i) integer(i); return at(self,i) and at(self,i).text or '' end
---Replace a tab label and refresh its presentation.
---@param i integer Zero-based index.
---@param label string Single-line UTF-8.
---@return boolean
---@return string|nil reason
function YTabBar:setTabText(i,label)
  integer(i); text(label); if self:is_destroyed() then return false,'destroyed' end
  local tab=at(self,i); if not tab or tab.text==label then return false end
  tab.text=label; self:update(); return true
end
---Change the default without replacing per-tab overrides.
---@param value boolean Default close-button visibility.
---@return boolean
---@return string|nil reason
function YTabBar:setTabsClosable(value)
  Object.boolean(value); if self:is_destroyed() then return false,'destroyed' end
  if self._closable==value then return false end
  self._closable=value; self:update(); return true
end
---Override close permission for one tab.
---@param i integer Zero-based index.
---@param value boolean Override preserved across default changes.
---@return boolean
---@return string|nil reason
function YTabBar:setTabClosable(i,value)
  integer(i); Object.boolean(value); if self:is_destroyed() then return false,'destroyed' end
  local tab=at(self,i); if not tab or tab.closable==value then return false end
  tab.closable=value; self:update(); return true
end
---Read the effective close permission for one tab.
---@param i integer Zero-based index.
---@return boolean
function YTabBar:isTabClosable(i)
  integer(i); local tab=at(self,i)
  if not tab then return false end
  if tab.closable~=nil then return tab.closable end
  return self._closable
end
---Emit an eligible close request without removing membership.
---@param i integer Zero-based index.
---@return boolean requested No deletion occurs automatically.
---@return string|nil reason
function YTabBar:requestClose(i)
  integer(i); if self:is_destroyed() then return false,'destroyed' end
  if not self:is_enabled() or not self:isTabClosable(i) then return false end
  self:emit("tabCloseRequested",i); return true
end
function YTabBar:_compose(width)
  local chain={}; local tiny=width<#self._tabs
  for i,tab in ipairs(self._tabs) do
    if not tiny or i-1==self._current then
      local hint=Metrics.width(tab.text)+2+(self:isTabClosable(i-1) and 2 or 0)
      chain[#chain+1]={minimum=1,hint=hint,maximum=hint,stretch=0,expansive=false,empty=false,index=i-1}
    end
  end
  -- The existing cell allocator owns widths; a trailing stretch keeps tabs left-aligned.
  chain[#chain+1]={minimum=0,hint=0,maximum=2147483647,stretch=1,expansive=true,empty=true}
  require('yana_ui.layout_axis').allocate(chain,0,width,0)
  local line,spans='',{}
  for _,item in ipairs(chain) do
    if item.index then
      local n=item.size; local close=self:isTabClosable(item.index) and n>=4
      local label=Metrics.elide(self:tabText(item.index),math.max(0,n-(close and 4 or (n>=3 and 2 or 0))))
      local part=n>=3 and (' '..label..(close and ' ×' or '')..' ') or label
      part=Metrics.cell_clip(part,n); part=part..string.rep(' ',math.max(0,n-Metrics.width(part)))
      local start=#line; line=line..part
      spans[#spans+1]={index=item.index,col=item.position,width=n,start_byte=start,end_byte=#line,
        close_col=close and item.position+n-2 or nil}
    end
  end
  return line,spans
end
---Prepare the strip on its borrowed canvas with the supplied style.
---@param writer YPaintWriter Canvas writer.
---@param style YStyle Theme-derived appearance owner.
---@return boolean
---@return string|nil reason
function YTabBar:prepare(writer,style)
  assert(require('yana_ui.paint_writer').is_instance(writer),'expected YPaintWriter')
  assert(getmetatable(style)==require('yana_ui.style'),'expected YStyle')
  if self:is_destroyed() or writer:is_destroyed() then return false,'destroyed' end
  self._style=style; style:attach(self)
  local _,_,width=self:rect(); local line,spans=self:_compose(width)
  local marks={}; self._slots_by_tab=self._slots_by_tab or {}
  for j,span in ipairs(spans) do
    local slot=self._slots_by_tab[j] or self.id*1000+j
    while writer._slots[slot] and writer._slots[slot].widget~=self do slot=slot+1 end
    self._slots_by_tab[j]=slot
    local active=span.index==self._current
    local mask=active and style:state(self,false,true) or 0
    local appearance=style:appearance('item',mask,active and 'active' or 'disabled')
    if span.end_byte>span.start_byte and appearance then
      marks[#marks+1]={slot=slot,row=0,start_byte=span.start_byte,end_byte=span.end_byte,appearance=appearance}
    end
  end
  self._spans=spans; self._preparing=true
  local ok,why=writer:prepare(self,{line},marks)
  self._preparing=false; self._prepared_writer=writer
  return ok,why
end
---Refresh the attached canvas or header, then request a widget repaint.
---@return boolean requested
---@return string|nil reason Destruction refusal or nil.
function YTabBar:update()
  if self._header then require('yana_ui.tab_header').refresh(self._header) end
  if not self._preparing and self._prepared_writer and not self._prepared_writer:is_destroyed() and not self:is_destroyed() then
    self:prepare(self._prepared_writer,self._style)
  end
  return Widget.update(self)
end
---@class YTabHeaderGroups
---@field normal? string [default: YanaUiTabFill] Full header band; linked to TabLineFill.
---@field active? string [default: YanaUiTabActive] Selected tab; linked to TabLineSel.
---@field inactive? string [default: YanaUiTabInactive] Other tabs; linked to TabLine.
---@field subtitle? string [default: YanaUiTabStatus] Status text; linked to Comment.
---@field button? string [default: YanaUiTabButton] Enabled corner actions; linked to TabLine.
---@field disabled? string [default: YanaUiTabDisabled] Disabled corner actions; linked to Comment.
---@class YTabHeaderOptions
---@field corner? fun(index: integer): YAction[] [default: nil] Borrowed actions at the right edge.
---@field status? fun(index: integer): string|nil [default: nil] Dim single-line subtitle; yields space before tabs.
---@field groups? YTabHeaderGroups [default: nil] Borrowed native highlight names, fixed per mount. Unknown roles and names outside letters, digits, underscore, dot and @ are refused.
---Borrow a native window's winbar without creating a strip window. Native
---single left clicks select or request close; there is no header key focus.
---@param win integer Existing native window.
---@param opts? YTabHeaderOptions [default: nil] Header providers.
---@return boolean mounted
---@return string|nil reason Destruction refusal or nil.
function YTabBar:mount_header(win,opts)
  if self:is_destroyed() then return false,'destroyed' end
  self:show()
  return require('yana_ui.tab_header').mount(self,win,opts)
end
---Restore the still-owned winbar and release callbacks/input. Idempotent.
---@return boolean removed
function YTabBar:unmount_header() return require('yana_ui.tab_header').unmount(self) end
function YTabBar:_dispose() self:unmount_header() end
---Refresh the prepared canvas when a style is attached.
---@param writer YPaintWriter Canvas writer.
---@return boolean painted
---@return string|nil reason Destruction refusal or nil.
function YTabBar:paint(writer)
  if self:is_destroyed() then return false,'destroyed' end
  if self._style then self:prepare(writer,self._style) end
  return true
end
---Handle canvas pointer gestures and normalized navigation keys.
---@param kind string Dispatcher event.
---@param row integer Canvas row, zero-based.
---@param col integer Canvas display column, zero-based.
---@param button integer Native mouse button.
---@param key string Normalized key.
---@return boolean accepted
function YTabBar:event(kind,row,col,button,key)
  if self:is_destroyed() or not self:is_visible() or not self:is_enabled() then self._close_press=nil; return false end
  if kind=='key' then
    if key=='<Left>' or key=='<Right>' then
      self:setCurrentIndex(math.max(0,math.min(#self._tabs-1,self._current+(key=='<Left>' and -1 or 1)))); return true
    elseif key=='<Home>' or key=='<End>' then self:setCurrentIndex(key=='<Home>' and 0 or #self._tabs-1); return true
    elseif key=='<Delete>' then self:requestClose(self._current); return true end
    return false
  end
  local r,c,width=self:rect(); local _,spans=self:_compose(width); local hit
  if row==r then for _,span in ipairs(spans) do if col>=c+span.col and col<c+span.col+span.width then hit=span; break end end end
  if kind=='press' and button==1 then
    self._close_press=nil
    if hit and hit.close_col and col==c+hit.close_col then self._close_press=at(self,hit.index); return true end
    self:emit("tabBarClicked",hit and hit.index or -1)
    if not self:is_destroyed() and hit and at(self,hit.index) then self:setCurrentIndex(hit.index) end
    return true
  elseif kind=='release' and button==1 then
    local pressed=self._close_press; self._close_press=nil
    if pressed and hit and at(self,hit.index)==pressed and hit.close_col and col==c+hit.close_col then self:requestClose(hit.index) end
    return true
  end
  return false
end
return YTabBar
