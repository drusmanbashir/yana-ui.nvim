-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- WIDGETS TTV-01..05, TV-M01: decorate visible rows; YAbstractItemView owns input, paint and model glue.
local Base=require('yana_ui.abstract_item_view')
---@class YTreeRow : YTableRow
---@field parent_id? string|integer [default: nil] Consumer's visible parent identity.
---@field depth integer Nonnegative visible indentation depth.
---@field expandable? boolean [default: false] Show a disclosure and accept expansion requests.
---@field expanded? boolean [default: false] Consumer's currently rendered expansion state.
---@class YTreeViewOptions : YAbstractItemViewOptions
---@field tree_column string|integer Required visible column containing indentation and disclosure.
---@field indentation? integer [default: 2] Nonnegative display cells per depth.
---@class YTreeView : YAbstractItemView
---@doc brief Display a consumer-owned visible hierarchy using shared table columns and input.
---@doc qt QTreeView. Supply flattened visible rows, or attach a tree model with set_model; the consumer owns children, expansion and fetching. No domain traversal or automatic model mutation is added.
---@doc inherits |YAbstractItemView|, not |YTableView|; columns, widths, row states, sorting, model binding, native target ownership and activation retain their semantics.
---@signal expansion_requested(row_id: string|integer, expanded: boolean, generation: string|integer) | A matching disclosure click or eligible arrow asks for a desired state. Only later rows, from set_rows or the model, change presentation.
---@doc errors Tree columns remain visible on replacement. Depth and indentation are nonnegative finite integers at most 2147483647. Parent identities follow table identity rules. Expansion flags are booleans. Validate complete rows before mutation.
---@doc destroyed set_columns
---@doc context lua/yana_ui/tree_view.lua|YTreeView
---@doc setup Run this in Neovim with yana-ui on runtimepath. Mount into your own native buffer/window as with |YTableView|.
---@doc example local ui=require('yana_ui')
---@doc example local tree=ui.YTreeView.new{tree_column='name',columns={{id='name',title='Name',min_width=2,width=20}}}
---@doc example tree:set_rows({{id='root',depth=0,expandable=true,cells={name='Root'}}},1)
---@doc example tree:connect('expansion_requested',tree,function(_,id,expanded,generation)print(id,expanded,generation)end)
---@doc example tree:destroy()
---@doc see |YAbstractItemView|, |YTableView|, |YWidget|.
local YTreeView=setmetatable({},{__index=Base});YTreeView.__index=YTreeView
local function integer(value)
  assert(type(value)=='number' and value>=0 and value<=2147483647 and value==math.floor(value),'invalid tree integer')
end
local function tree_column(columns,id)
  assert(type(columns)=='table','tree columns required')
  for _,column in ipairs(columns)do if column.id==id then return end end
  error('tree column must be visible',2)
end
---Construct an unmounted tree over supplied visible hierarchy rows.
---@param opts YTreeViewOptions View options plus required tree_column.
---@return YTreeView view # Visible tree with no native target or domain model.
function YTreeView.new(opts)
  assert(type(opts)=='table','tree options required')
  tree_column(opts.columns,opts.tree_column)
  local indentation=opts.indentation==nil and 2 or opts.indentation;integer(indentation)
  local self=setmetatable(Base.new(opts),YTreeView)
  self._tree_column,self._indentation=opts.tree_column,indentation
  return self
end
function YTreeView:_copy_columns(columns)
  tree_column(columns,self._tree_column)
  return Base._copy_columns(self,columns)
end
function YTreeView:_copy_row(value)
  local row=Base._copy_row(self,value,true)
  row.parent_id,row.depth=value.parent_id,value.depth
  row.expandable,row.expanded=value.expandable==true,value.expanded==true
  return row
end
function YTreeView:_cell_content(row,column,value,_,width)
  if column~=self._tree_column then return value end
  local depth=row.depth*self._indentation
  local prefix=string.rep(' ',math.min(depth,width))
  local marker=row.expandable and (row.expanded and '▾' or '▸')or' '
  local region=row.expandable and depth+1<=width and {part='disclosure',start_cell=depth,end_cell=depth+1}or nil
  return prefix..marker..' '..value,region
end
function YTreeView:_input_keys()return {'<CR>','<Esc>','<Left>','<Right>'}end
function YTreeView:_request_cell(row,column,generation,input)
  local desired
  if input.part=='disclosure'then desired=not row.expanded
  elseif input.key=='<Right>'then if row.expandable and not row.expanded then desired=true end
  elseif input.key=='<Left>'then if row.expandable and row.expanded then desired=false end
  else return Base._request_cell(self,row,column,generation,input)end
  if desired~=nil then self:emit("expansion_requested",row.id,desired,generation)end
end
return YTreeView
-- DOCS: YTreeView example start
-- local ui=require('yana_ui')
-- local tree=ui.YTreeView.new{tree_column='name',columns={{id='name',title='Name',min_width=2,width=20}}}
-- tree:set_rows({{id='root',depth=0,expandable=true,cells={name='Root'}}},1)
-- tree:connect('expansion_requested',tree,function(_,id,expanded,generation)print(id,expanded,generation)end)
-- tree:destroy()
-- DOCS: YTreeView example end
