-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- TV-S01..09, TV-M04/05, ST-01/04: view-owned confirmed state; consumers or the attached model order records.
local Metrics=require('yana_ui.text_metrics')
local identity=require('yana_ui.object').identity
local Header={}
-- State -> {Unicode glyph, one-cell ASCII fallback} (TV-S02/S03).
local GLYPHS={none={'↕',':'},ascending={'▲','^'},descending={'▼','v'}}
function Header.column(view,id)
  for _,column in ipairs(view._columns)do if column.id==id then return column end end
end
local function order(value)
  assert(value=='ascending' or value=='descending','invalid sort order')
end
-- TV-M04 (R2): the one effective-sortable rule; every header/gesture/indicator check calls it.
-- An attached model decides alone; the column flag applies only without a model.
function Header.sortable(view,column)
  local model=view._model
  if model~=nil then return model:is_sortable(column.id)==true end
  return column.sortable
end
-- TV-M05: with a model its choice is the indicator; an unrepresentable choice clears it.
local function representable(view,indicator)
  local model=view._model
  if model then
    local id=model:sort_column()
    indicator=id~=nil and {column_id=id,order=model:sort_order()}or nil
    if indicator then order(indicator.order)end
  end
  local column=indicator and Header.column(view,indicator.column_id)
  if column and Header.sortable(view,column)then return indicator end
end
function Header.reconcile(view)view._sort_indicator=representable(view,view._sort_indicator)end
function Header.set(view,id,value)
  if id==nil then assert(value==nil,'clearing sort indicator requires nil order')
  else
    local column=Header.column(view,id)
    assert(column and Header.sortable(view,column),'sort column must be visible and sortable');order(value)
  end
  if view:is_destroyed()then return false,'destroyed' end
  local previous=view._sort_indicator
  if (not previous and id==nil)or(previous and previous.column_id==id and previous.order==value)then return false end
  view:_cancel_gesture()
  view._sort_indicator=id~=nil and {column_id=id,order=value}or nil
  view:render();return true
end
function Header.request(view,id,value)
  identity(id)
  local column=Header.column(view,id)
  if value~=nil then order(value)end
  if view:is_destroyed()then return false,'destroyed'end
  if not column or not Header.sortable(view,column) or not view:is_visible() or not view:is_enabled()then return false,'ineligible'end
  if value==nil then
    local current=view._sort_indicator
    value=current and current.column_id==id and current.order=='ascending' and 'descending'or'ascending'
  end
  return true,value
end
-- ST-01: one icon slot as wide as the widest state's glyph, measured per label,
-- so a narrower glyph pads its slot and the title never shifts between states.
function Header.label(view,column)
  if not Header.sortable(view,column)then return column.title end
  local indicator=view._sort_indicator
  local state=indicator and indicator.column_id==column.id and indicator.order or 'none'
  local width,size,icon=view._widths[column.id],1,nil
  for name,pair in pairs(GLYPHS)do
    local glyph=Metrics.width(pair[1])<=width and pair[1] or pair[2]
    size=math.max(size,Metrics.width(glyph))
    if name==state then icon=glyph end
  end
  icon=Metrics.pad(icon,size)
  if width==size then return icon end
  local title=Metrics.cell_clip(Metrics.expand_tabs(column.title,0),math.max(0,width-size-1))
  return Metrics.pad(title,width-size)..icon
end
return Header
