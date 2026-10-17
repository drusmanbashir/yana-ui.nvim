-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- COLLAPSE: derive host intent and measured shares through the existing allocator.
local Grid=require('yana_ui.grid_layout')
local api=vim.api
local M={}
local function identity(node)
  if node.id then return #node.id..':'..node.id end
  local parts={node.axis}
  for _,edge in ipairs(node.children)do parts[#parts+1]=identity(edge.node)end
  return '('..table.concat(parts,';')..')'
end
local function group_key(node)
  local parts={identity(node)}
  for _,edge in ipairs(node.children)do
    parts[#parts+1]=table.concat({tostring(edge.size),tostring(edge.min),tostring(edge.weight or 1)},':')
  end
  return table.concat(parts,'|')
end
function M.derive(tree,intent,cache,native)
  local parsed,why=Grid._parse_split(tree)
  if not parsed then return nil,why end
  local compact,arranged={},{}
  local function walk(node,parent_axis)
    if node.id then
      local collapsed=intent[node.id]==true
      arranged[node.id]=true
      local minimum=native[node.id] or {width=1,height=1}
      local leaf={id=node.id,min_width=math.max(node.min_width or 1,minimum.width),
        min_height=math.max(node.min_height or 1,minimum.height)}
      if collapsed then
        if not parent_axis then return nil,'last expanded pane in group'end
        compact[node.id]={axis=parent_axis,size=parent_axis=='row'and math.max(3,minimum.width)or math.max(1,minimum.height)}
        leaf.min_width,leaf.min_height=minimum.width,minimum.height
      end
      return leaf,not collapsed
    end
    local out={axis=node.axis,children={}}
    local expanded,elastic,local_compact=false,false,false
    local shares=cache[group_key(node)]
    for i,edge in ipairs(node.children)do
      local child,is_expanded=walk(edge.node,node.axis)
      if not child then return nil,is_expanded end
      expanded=expanded or is_expanded
      if edge.size==nil and is_expanded then elastic=true end
      local copy={node=child,size=edge.size,min=edge.min,weight=edge.weight}
      if child.id and compact[child.id]then
        copy.size,copy.min=compact[child.id].size,compact[child.id].size
        local_compact=true
      elseif edge.size==nil and shares and shares[i]then copy.weight=shares[i]end
      out.children[i]=copy
    end
    if local_compact and not expanded then return nil,'last expanded pane in group'end
    if local_compact and not elastic then return nil,'no expandable sibling in group'end
    return out,expanded
  end
  local effective,error_message=walk(tree)
  if not effective then return nil,error_message end
  return {tree=effective,compact=compact,arranged=arranged}
end
-- Only expanded elastic shares are remeasured; compact members keep their share.
function M.capture(tree,intent,cache,windows)
  local result=vim.deepcopy(cache)
  local function walk(node)
    if node.id then
      local win=windows[node.id]
      if not win or not api.nvim_win_is_valid(win) then return nil end
      local pos=api.nvim_win_get_position(win)
      return {row=pos[1],col=pos[2],width=api.nvim_win_get_width(win),height=api.nvim_win_get_height(win)}
    end
    local rects,top,left,bottom,right={},math.huge,math.huge,0,0
    for i,edge in ipairs(node.children)do
      local rect=walk(edge.node);if not rect then return nil end
      rects[i]=rect;top=math.min(top,rect.row);left=math.min(left,rect.col)
      bottom=math.max(bottom,rect.row+rect.height);right=math.max(right,rect.col+rect.width)
    end
    local key=group_key(node);local old=cache[key];local shares={}
    local active,old_total,actual_total={},0,0
    local compact_member,declared_active=false,0
    for _,edge in ipairs(node.children)do
      if edge.size==nil then
        if edge.node.id and intent[edge.node.id]then compact_member=true
        else declared_active=declared_active+(edge.weight or 1)end
      end
    end
    for i,edge in ipairs(node.children)do
      if edge.size==nil then
        local extent=node.axis=='row'and rects[i].width or rects[i].height
        shares[i]=old and old[i]or extent
        if not(edge.node.id and intent[edge.node.id])then
          active[#active+1]=i;old_total=old_total+shares[i];actual_total=actual_total+extent
        end
      end
    end
    if not old and compact_member and declared_active>0 then
      for i,edge in ipairs(node.children)do
        if edge.size==nil and edge.node.id and intent[edge.node.id]then
          shares[i]=(edge.weight or 1)*actual_total/declared_active
        end
      end
    end
    if old and actual_total>0 then
      for _,i in ipairs(active)do
        local extent=node.axis=='row'and rects[i].width or rects[i].height
        shares[i]=old_total*extent/actual_total
      end
    end
    result[key]=shares
    return {row=top,col=left,width=right-left,height=bottom-top}
  end
  walk(tree)
  return result
end
return M
