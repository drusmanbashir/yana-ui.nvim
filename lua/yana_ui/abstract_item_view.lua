-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-FileCopyrightText: 2016 The Qt Company Ltd
-- SPDX-License-Identifier: LGPL-3.0-only
-- From qtbase v6.8.4-lts-lgpl ed77a3ca. Header resize: qheaderview.cpp resizeSection
-- 841-912, mousePressEvent 2524-2563, mouseMoveEvent ResizeSection 2585-2598. Model
-- binding: qabstractitemview.h:25 class (derives YWidget; native buffer scrolling
-- replaces QAbstractScrollArea), qabstractitemview.cpp:715-765 setModel and 3741-3745
-- modelDestroyed. Sort glue qtableview.cpp:2754-2779,3395-3406,1018-1021
-- and qtreeview.cpp:835-852,2679-2690,4084-4087,216-217 lives once here, not per view.
-- WIDGETS TV-01..16, TV-S01..10, TV-M01..09, ST-01..04: presentation only; native input/focus/canvas keep ownership.
local Object=require('yana_ui.object')
local Widget=require('yana_ui.widget')
local Focus=require('yana_ui.focus')
local Style=require('yana_ui.style')
local Writer=require('yana_ui.paint_writer')
local Input=require('yana_ui.input')
local Layout=require('yana_ui.layout')
local Metrics=require('yana_ui.text_metrics')
local Geometry=require('yana_ui.geometry')
local Header=require('yana_ui.table_header')
local Cursor=require('yana_ui.table_cursor')
local ItemRow=require('yana_ui.item_row')
---@class YTableColumn
---@field id string|integer Unique stable column identity.
---@field title string Single-line heading.
---@field min_width integer Positive minimum text width in cells.
---@field width integer Initial text width at least min_width.
---@field hl_group? string [default: nil] Foreground/decoration for normal data cells; row states override it.
---@field sortable? boolean [default: false] Show a sort icon and accept header ordering requests; ignored while a model is attached, whose is_sortable decides.
---@class YTableRow
---@field id string|integer Unique stable record identity.
---@field cells table<string|integer,string> Single-line display values by column ID.
---@field current? boolean [default: false] Consumer's current-record presentation.
---@field disabled? boolean [default: false] Consumer's disabled-record presentation.
---@field dimmed? boolean [default: false] Use disabled appearance while retaining activation and selection.
---@field annotation? {text: string, hl_group: string} [default: nil] Non-actionable status at the viewport right edge, bounded by the finite canvas end during native overscroll.
---@class YTableFooterMark
---@field line integer One-based footer line.
---@field start_byte integer Zero-based inclusive text byte offset.
---@field end_byte integer Zero-based exclusive text byte offset.
---@field hl_group string Nonempty native highlight group.
---@class YTableFooter
---@field lines string[] Single-line text spanning the canvas width.
---@field marks YTableFooterMark[] Supplied highlight ranges within those lines.
---@field min_height integer Nonnegative minimum trailing height.
---@class YAbstractItemViewOptions
---@field parent? YObject [default: nil] Live owner, following YWidget lifetime.
---@field columns YTableColumn[] [default: required] Ordered visible columns; omitted IDs retain private widths.
---@field groups? table<string,string> [default: nil] Override normal/header/rule/separator/selected/current/disabled groups.
---@field elide? boolean [default: false] Use end ellipsis for overflowing headings and data cells.
---@class YAbstractItemView : YWidget
---@doc brief Shared item-view base: columns, header, row paint, native input, cursor identity and an optional row model.
---@doc qt QAbstractItemView, plus the sortByColumn glue Qt repeats in QTableView and QTreeView. Derives YWidget; native buffer scrolling replaces QAbstractScrollArea. One native buffer holds labels, rule and rows; headers scroll with it. Rows come from set_rows, or from model:rows() after set_model; a header request then calls model:sort once here. Native navigation remains native. Use |YTableView| or |YTreeView|.
---@doc inherits |YWidget|; parent, lifetime, visibility and enabled state retain their semantics. Only the listed constructor options are accepted.
---@signal activated(row_id: string|integer, column_id: string|integer, generation: string|integer) | Matching eligible release or CR requests activation after native cursor placement. Selection and commands remain consumer-owned.
---@signal column_resized(column_id: string|integer, cells: integer) | Emitted after an actual width change and repaint. Only that column changes; callbacks may unmount or destroy the view.
---@signal sort_requested(column_id: string|integer, order: string, generation: string|integer) | Eligible header click or request_sort asks for ascending/descending order. Without a model the consumer confirms with set_sort_indicator after updating its rows. With a model it follows model:sort, the row repaint and the model's indicator.
---@doc property column_widths|column_widths()|set_column_width(id, cells)|column_resized|constructor width hints
---@doc property model|model()|set_model(model)|none|nil
---@doc errors Columns and rows are dense arrays with distinct nonempty string or finite integer IDs. Widths are positive finite integers, width at least minimum. Text has no CR/LF/NUL. Validate complete input before mutation. Unknown groups/columns and invalid native targets assert. A model is a live YObject with rows, generation, is_sortable, sort, sort_column and sort_order. Callback and native API errors propagate.
---@doc destroyed mount,set_columns,set_rows,set_footer,set_selected_key,set_column_width,set_model,request_sort,render,event
---@doc exception unmount remains idempotent after destruction; row_at_line, column_widths and is_mounted remain readable; model returns nil. render/event refuse a stale target. set_rows generation is a stable nonempty string or finite integer, separate from mount epoch.
---@doc context lua/yana_ui/abstract_item_view.lua|YAbstractItemView
---@doc setup Run this in Neovim with yana-ui on runtimepath. The model here is a minimal stand-in for the row-model interface.
---@doc example local ui=require('yana_ui')
---@doc example local model,rows=ui.YObject.new(),{{id='b',cells={name='Beta'}},{id='a',cells={name='Alpha'}}}
---@doc example function model:rows()return rows end
---@doc example function model:generation()return 1 end
---@doc example function model:is_sortable(id)return id=='name' end
---@doc example function model:sort_column()return nil end
---@doc example function model:sort_order()return nil end
---@doc example function model:sort()return false,'unsortable' end
---@doc example local view=ui.YTableView.new{columns={{id='name',title='Name',min_width=2,width=12}}}
---@doc example view:set_model(model)
---@doc example print(view:model()==model)
---@doc example view:destroy();model:destroy()
---@doc see |YTableView|, |YTreeView|, |YWidget|, |YPaintWriter|, |YEventDispatcher|, |YFocus|.
local YAbstractItemView=setmetatable({},{__index=Widget});YAbstractItemView.__index=YAbstractItemView
local limit=2147483647
local roles={normal=true,header=true,rule=true,separator=true,selected=true,current=true,disabled=true}
local standard={header='Title',rule='Comment',separator='WinSeparator'}
local function integer(n,minimum)
  assert(type(n)=='number' and n<=limit and n>=minimum and n==math.floor(n),'invalid table integer')
end
local identity=Object.identity
local text=ItemRow.text
local function array(values)
  assert(type(values)=='table','table requires an array')
  local count=0
  for k in pairs(values)do integer(k,1);assert(k<=#values,'table requires a dense array');count=count+1 end
  assert(count==#values,'table requires a dense array')
end
local function logical_width(columns,widths)
  local width=0;for _,c in ipairs(columns)do width=width+(widths and widths[c.id] or c.width)+1 end
  assert(width<=limit,'table width exceeds cell layout limit');return width
end
local function footer_copy(value)
  if value==nil then return nil end
  assert(type(value)=='table','invalid table footer')
  array(value.lines);array(value.marks);integer(value.min_height,0)
  local out={lines={},marks={},min_height=value.min_height}
  for i,line in ipairs(value.lines)do text(line);out.lines[i]=line end
  for _,mark in ipairs(value.marks)do
    assert(type(mark)=='table','invalid footer mark');integer(mark.line,1)
    local line=assert(out.lines[mark.line],'unknown footer line')
    integer(mark.start_byte,0);integer(mark.end_byte,mark.start_byte)
    assert(mark.end_byte<=#line,'footer mark exceeds text')
    text(mark.hl_group);assert(mark.hl_group~='','empty footer group')
    out.marks[#out.marks+1]={line=mark.line,start_byte=mark.start_byte,end_byte=mark.end_byte,hl_group=mark.hl_group}
  end
  return out
end
local function columns_copy(values)
  array(values);local out,seen={},{}
  for _,v in ipairs(values)do
    assert(type(v)=='table','invalid column');identity(v.id);text(v.title)
    integer(v.min_width,1);integer(v.width,v.min_width);assert(not seen[v.id],'duplicate column ID')
    if v.hl_group~=nil then text(v.hl_group);assert(v.hl_group~='','empty column group')end
    if v.sortable~=nil then Object.boolean(v.sortable)end
    seen[v.id]=true;out[#out+1]={id=v.id,title=v.title,min_width=v.min_width,width=v.width,hl_group=v.hl_group,sortable=v.sortable==true}
  end
  logical_width(out);return out
end
function YAbstractItemView:_copy_columns(values)return columns_copy(values)end
-- F2: ItemRow owns the row shape; the proxy model validates through it too.
function YAbstractItemView:_copy_row(v,tree)
  ItemRow.check(v,tree)
  local cells={};for key,value in pairs(v.cells)do cells[key]=value end
  local annotation=v.annotation and {text=v.annotation.text,hl_group=v.annotation.hl_group}
  return {id=v.id,cells=cells,current=v.current==true,disabled=v.disabled==true,dimmed=v.dimmed==true,annotation=annotation}
end
local function rows_copy(self,values)
  array(values);local out,seen={},{}
  for _,v in ipairs(values)do
    local row=self:_copy_row(v)
    assert(not seen[row.id],'duplicate row ID');seen[row.id]=true;out[#out+1]=row
  end
  return out
end
function YAbstractItemView:_valid(m)
  return m~=nil and self._mount==m and not self:is_destroyed() and not m.owner:is_destroyed()
    and vim.api.nvim_win_is_valid(m.win) and vim.api.nvim_buf_is_valid(m.buf)
    and vim.api.nvim_win_get_buf(m.win)==m.buf
end
function YAbstractItemView:_target()
  local m=self._mount
  if self:_valid(m)then return m.win,m.buf,m.epoch end
end
---Construct a visible unmounted flat view; concrete classes call this base.
---Native targets remain consumer-owned. Asserts when options or columns are invalid.
---@param opts YAbstractItemViewOptions Required columns and optional owner/groups.
---@return YAbstractItemView view # New view with detached presentation state and no model.
function YAbstractItemView.new(opts)
  assert(type(opts)=='table','table options required')
  if opts.elide~=nil then Object.boolean(opts.elide)end
  local columns=columns_copy(opts.columns);local groups={}
  for key,value in pairs(opts.groups or {})do assert(roles[key],'unknown table group');text(value);assert(value~='','empty group');groups[key]=value end
  local self=setmetatable(Widget.new{parent=opts.parent},YAbstractItemView)
  self._columns,self._rows,self._groups,self._widths=columns,{},groups,{}
  self._elide=opts.elide==true
  for _,c in ipairs(columns)do self._widths[c.id]=c.width end
  self._revision,self._epoch,self._generation=0,0,0
  self._focus=Focus.new{parent=self,current_target=function()return self:_target()end}
  self._style=Style.new{focus=self._focus};self._style:attach(self)
  local layout=Layout.new{parent=self}
  function layout:_collect(row,col,width,height,plan)
    plan[#plan+1]={widget=self:parent(),rect={row,col,width,height}}
  end
  self:set_layout(layout)
  self:connect('pointer_target_changed',self,function(view)
    if not view:is_visible() or not view:is_enabled()then view:_cancel_gesture()end
  end)
  self:show();return self
end
function YAbstractItemView:_grab_cancelled() self._gesture=nil end
function YAbstractItemView:_cancel_gesture()
  self._gesture=nil
  local m=self._mount;if m and m.dispatcher then m.dispatcher:_cancel_grab(self)end
end
---Replace visible columns after complete validation; retain widths by ID.
---@param columns YTableColumn[] Ordered visible columns; a YTreeView's must include its tree_column.
---@return boolean changed # True after replacement; false when destroyed.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YAbstractItemView:set_columns(columns)
  local copy=self:_copy_columns(columns)
  if self:is_destroyed()then return false,"destroyed"end
  local widths=vim.deepcopy(self._widths)
  for _,c in ipairs(copy)do widths[c.id]=math.max(widths[c.id] or c.width,c.min_width)end
  logical_width(copy,widths);self:_cancel_gesture()
  self._columns,self._widths=copy,widths;self._revision=self._revision+1
  Header.reconcile(self)
  self:render();return true
end
---Copy displayed records and their consumer generation; cancel old gestures.
---Opted-in cursor restoration keeps record/column identity within content bounds.
---Asserts while a model is set: rows are model-owned.
---@param rows YTableRow[] Ordered presentation values, never domain records.
---@param generation string|integer Stable nonempty string or finite integer.
---@param opts? {preserve_cursor?: boolean, columns?: YTableColumn[]} [default: nil] Preserve record/column identity across replacement; optionally validate and replace columns in the same update.
---@return boolean changed # True after replacement; false when destroyed.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YAbstractItemView:set_rows(rows,generation,opts)
  assert(self._model==nil,'rows are model-owned')
  return self:_replace_rows(rows,generation,opts)
end
function YAbstractItemView:_replace_rows(rows,generation,opts)
  local copy=rows_copy(self,rows);identity(generation)
  opts=opts or {};assert(type(opts)=='table','invalid row replacement options')
  for key in pairs(opts)do assert(key=='preserve_cursor' or key=='columns','unknown row replacement option')end
  if opts.preserve_cursor~=nil then Object.boolean(opts.preserve_cursor)end
  local columns=opts.columns and self:_copy_columns(opts.columns)
  local widths=vim.deepcopy(self._widths)
  if columns then
    for _,c in ipairs(columns)do widths[c.id]=math.max(widths[c.id] or c.width,c.min_width)end
    logical_width(columns,widths)
  end
  if self:is_destroyed()then return false,"destroyed"end
  self._cursor_anchor=opts.preserve_cursor and Cursor.capture(self)or nil
  self:_cancel_gesture()
  if columns then self._columns,self._widths=columns,widths end
  -- ST-02: a model's indicator joins its rows in this one repaint (TV-M03).
  if columns or self._model then Header.reconcile(self)end
  self._rows,self._generation=copy,generation;self._revision=self._revision+1
  self:render();return true
end
---Replace copied footer presentation; nil removes its padding and text.
---The footer uses the same writer and never represents an actionable record.
---@param footer YTableFooter|nil Validated trailing presentation, or nil.
---@return boolean changed # True after replacement; false when destroyed.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YAbstractItemView:set_footer(footer)
  local copy=footer_copy(footer)
  if self:is_destroyed()then return false,"destroyed"end
  self:_cancel_gesture();self._footer=copy;self._revision=self._revision+1
  self:render();return true
end
---Set only the supplied selection presentation; commands remain consumer-owned.
---@param id string|integer|nil Selected row key, or nil to clear.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YAbstractItemView:set_selected_key(id)
  if id~=nil then identity(id)end
  if self:is_destroyed()then return false,"destroyed"end
  if self._selected==id then return false end
  self._selected=id;self:render();return true
end
---Return a detached map containing widths of currently visible column IDs.
---@return table<string|integer,integer> widths # Current widths, also after destruction.
function YAbstractItemView:column_widths()
  local out={};for _,c in ipairs(self._columns)do out[c.id]=self._widths[c.id]end;return out
end
---Change one visible column using the same bounds as a separator drag.
---Asserts when the column ID is unknown or the requested width is invalid.
---@param id string|integer Visible column ID.
---@param cells integer Positive finite desired text width.
---@return boolean changed # True after actual change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YAbstractItemView:set_column_width(id,cells)
  identity(id);integer(cells,1)
  local column;for _,c in ipairs(self._columns)do if c.id==id then column=c;break end end
  assert(column,'unknown column ID')
  if self:is_destroyed()then return false,"destroyed"end
  local m=self._mount;local upper=math.huge
  if self:_valid(m)then upper=math.max(column.min_width,Geometry.get(m.win).width-1)end
  cells=math.max(column.min_width,math.min(cells,upper))
  if cells==self._widths[id]then return false end
  if self._gesture and self._gesture.header then self:_cancel_gesture()end
  local widths=vim.deepcopy(self._widths);widths[id]=cells;logical_width(self._columns,widths)
  self._widths[id]=cells;self:render();self:emit("column_resized",id,cells);return true
end
---Return a detached confirmed indicator; with a model it mirrors the model's choice.
---@return {column_id: string|integer, order: string}|nil indicator # Confirmed state, or nil.
function YAbstractItemView:sort_indicator()return self._sort_indicator and vim.deepcopy(self._sort_indicator)or nil end
---Confirm a visible sortable column and order without emitting a request.
---Refuses while a model is attached: the model is the indicator's only source.
---@param id string|integer|nil Visible sortable column; nil clears.
---@param order "ascending"|"descending"|nil Required with id; nil when clearing.
---@return boolean changed # True on change; false when unchanged, model-owned or destroyed.
---@return "destroyed"|"model-owned"|nil reason # Refusal reason, or nil.
function YAbstractItemView:set_sort_indicator(id,order)
  -- TV-M09 (R1): mirrors the TV-M07 set_rows refusal; Header.reconcile is the model's only writer.
  if self._model~=nil then return false,'model-owned' end
  return Header.set(self,id,order)
end
---Request an order. Without a model, rows and the confirmed indicator are unchanged.
---With a model, call model:sort first; its layout_changed repaints rows and indicator.
---Invalid column IDs or orders raise, also after destruction.
---@param id string|integer Visible column sortable by the attached model, or by flag without one.
---@param order? "ascending"|"descending" [default: nil] New column ascends; active confirmed column toggles.
---@return boolean requested # True when emitted; false when ineligible, refused by the model or destroyed.
---@return "destroyed"|"ineligible"|nil reason # Refusal reason, or nil.
function YAbstractItemView:request_sort(id,order)
  local accepted,value=Header.request(self,id,order)
  if not accepted then return false,value end
  local model=self._model
  if model then
    -- TV-M06: layout_changed callbacks run inside sort and may destroy this view.
    local sorted,reason=model:sort(id,value)
    if self:is_destroyed()then return false,"destroyed"end
    if sorted==false and reason~=nil then return false,"ineligible"end
  end
  self:emit("sort_requested",id,value,self._generation);return true
end
local model_methods={'rows','generation','is_sortable','sort','sort_column','sort_order'}
---Attach a row model, or detach with nil. Attaching repaints model:rows() with
---model:generation() and adopts the model's sort indicator; later layout_changed
---signals repaint with cursor identity. Detaching, also on model destruction,
---keeps rows and clears the indicator. Asserts on a dead or incomplete model
---or invalid model rows/generation, before any change.
---@param model YObject|nil Live model with rows, generation, is_sortable, sort, sort_column and sort_order; nil detaches.
---@return boolean changed # True after attach or detach; false if unchanged or destroyed.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YAbstractItemView:set_model(model)
  if model~=nil then
    assert(Object.is_instance(model) and not model:is_destroyed(),'model must be a live YObject')
    for _,name in ipairs(model_methods)do assert(type(model[name])=='function','model lacks '..name)end
    rows_copy(self,model:rows());identity(model:generation())
  end
  if self:is_destroyed()then return false,"destroyed"end
  if model==self._model then return false end
  self:_release_model()
  if model==nil then self:_detached();return true end
  self._model=model
  self._model_tokens={model:connect('layout_changed',self,function(view)view:_model_layout(model,true)end),
    model:connect('destroyed',self,function(view)
      if view._model==model then view:_release_model();view:_detached()end
    end)}
  self:_model_layout(model,false);return true
end
---Read the attached row model.
---@return YObject|nil model # Attached model; nil when detached or destroyed.
function YAbstractItemView:model()return self._model end
function YAbstractItemView:_release_model()
  local model,tokens=self._model,self._model_tokens
  self._model,self._model_tokens=nil,nil
  for _,token in ipairs(tokens or {})do if token then model:disconnect(token)end end
end
function YAbstractItemView:_detached()
  self:_cancel_gesture()
  if not Header.set(self,nil,nil)then self:render()end
end
-- TV-M03/ST-02: rows and the model's indicator replace together in one repaint.
-- F2 defence: a model whose rows this view refuses is detached before the error
-- propagates, so later signals and header clicks cannot re-raise.
function YAbstractItemView:_model_layout(model,preserve)
  if self:is_destroyed() or self._model~=model then return end
  local ok,err=pcall(self._replace_rows,self,model:rows(),model:generation(),{preserve_cursor=preserve})
  if not ok then
    if self._model==model then self:_release_model();self:_detached()end
    error(err,0)
  end
end
---Map a native one-based data line to its supplied key; header/empty lines return nil.
---@param line integer Positive finite buffer line number.
---@return string|integer|nil id # Supplied row ID, or nil outside data.
function YAbstractItemView:row_at_line(line)
  integer(line,1);local row=self._rows[line-2];return row and row.id
end
function YAbstractItemView:_appearance(role)
  local group=self._groups[role] or standard[role]
  if group then return vim.api.nvim_get_hl_id_by_name(group)end
  local mask=role=='disabled' and 0 or Style.enabled
  if role=='selected'then mask=bit.bor(mask,Style.selected)
  elseif role=='current'then mask=bit.bor(mask,Style.on)end
  return self._style:appearance('item',mask,'active')
end
function YAbstractItemView:_cell_content(_,_,value)return value end
function YAbstractItemView:_input_keys()return {'<CR>','<Esc>'}end
function YAbstractItemView:_request_cell(record,column,generation)
  self:emit("activated",record.id,column,generation)
end
function YAbstractItemView:_compose(width,height,viewport)
  local lines,marks,regions,annotations={},{},{},{}
  local function annotate(row,role,record,line,first)
    local value=record and record.annotation
    if not value or value.text==''then return line end
    local label=Metrics.prefix_cells(Metrics.expand_tabs(value.text,0),viewport.width,0)
    local size=Metrics.width(label);local right=viewport.left+viewport.width
    local gap=size<viewport.width and 1 or 0;local start=right-size-gap
    local ellipsis=start>viewport.left and 1 or 0
    local prefix,rest,kept=Metrics.prefix_cells(line,start-ellipsis,0)
    local retained=#prefix
    prefix=prefix..(ellipsis==1 and '…'or'')..string.rep(' ',start-kept-ellipsis)
    local until_right,suffix,used=Metrics.prefix_cells(line,right,0)
    local old_right=#until_right;local suffix_gap=''
    if used<right and suffix~=''then
      local crossed=Metrics.character(suffix,0)
      suffix_gap=string.rep(' ',Metrics.width(crossed,used)-(right-used))
      old_right=old_right+#crossed;suffix=suffix:sub(#crossed+1)
    end
    local head=prefix..string.rep(' ',gap)..label
    local delta=#head+#suffix_gap-old_right
    local held={};for i=first,#marks do held[#held+1]=marks[i]end
    for i=#marks,first,-1 do marks[i]=nil end
    local function mark(a,b,appearance)
      if b>a then marks[#marks+1]={slot=#marks+1,row=row,start_byte=a,end_byte=b,appearance=appearance}end
    end
    for _,old in ipairs(held)do
      mark(old.start_byte,math.min(old.end_byte,retained),old.appearance)
      mark(math.max(old.start_byte,old_right)+delta,old.end_byte+delta,old.appearance)
    end
    local base=self:_appearance(role)
    mark(retained,#prefix+gap,base)
    mark(#prefix+gap,#head,self._style:_overlay(base,value.hl_group))
    mark(#head,#head+#suffix_gap,base)
    for column,region in pairs(regions[row] or {})do
      if region.end_cell>kept and region.start_cell<right then regions[row][column]=nil end
    end
    annotations[row]={start_cell=start,end_cell=right}
    return head..suffix_gap..suffix
  end
  local function add(row,values,role,rule,record)
    local pieces,col,bytes={},0,0;local first=#marks+1
    local function piece(value,appearance,override)
      pieces[#pieces+1]=value
      if #value>0 then marks[#marks+1]={slot=#marks+1,row=row,start_byte=bytes,end_byte=bytes+#value,appearance=override or self:_appearance(appearance)}end
      bytes=bytes+#value
    end
    for _,c in ipairs(self._columns)do
      local cells=self._widths[c.id];local value,region=values[c.id] or ''
      if record then value,region=self:_cell_content(record,c.id,value,col,cells)end
      local expanded=Metrics.expand_tabs(value,col)
      local clipped,_,used=Metrics.prefix_cells(expanded,cells,col)
      local retained=used
      if self._elide and not rule and Metrics.width(expanded)>cells then
        clipped=Metrics.elide(expanded,cells);used=Metrics.width(clipped)
        local prefix,rest,kept=Metrics.prefix_cells(expanded,math.max(0,cells-Metrics.width('…')),col);retained=kept
      end
      if region and region.start_cell>=0 and region.end_cell<=retained then
        regions[row]=regions[row] or {}
        regions[row][c.id]={part=region.part,start_cell=col+region.start_cell,end_cell=col+region.end_cell}
      end
      local appearance=record and role=='normal' and c.hl_group and self._style:_overlay(self:_appearance(role),c.hl_group)
      piece(rule and string.rep('─',cells) or clipped..string.rep(' ',cells-used),role,appearance)
      piece(rule and '┼' or '│','separator');col=col+cells+1
    end
    piece(string.rep(' ',width-col),role);lines[row+1]=annotate(row,role,record,table.concat(pieces),first)
  end
  local labels={};for _,c in ipairs(self._columns)do labels[c.id]=Header.label(self,c)end
  add(0,labels,'header');add(1,{},'rule',true)
  for i,row in ipairs(self._rows)do
    local role=row.disabled and 'disabled' or (row.id==self._selected and 'selected' or
      (row.dimmed and 'disabled' or (row.current and 'current' or 'normal')))
    add(i+1,row.cells,role,false,row)
  end
  local footer=self._footer
  if footer then
    local count=math.max(footer.min_height,#footer.lines)
    local first=height-count+1
    for line=#lines+1,first-1 do lines[line]=''end
    for i=1,count do
      local expanded=Metrics.expand_tabs(footer.lines[i] or '',0)
      lines[first+i-1]=Metrics.prefix_cells(expanded,width,0)
    end
    for _,mark in ipairs(footer.marks)do
      local original=footer.lines[mark.line]
      local rendered=lines[first+mark.line-1]
      local start=math.min(#rendered,#Metrics.expand_tabs(original:sub(1,mark.start_byte),0))
      local finish=math.min(#rendered,#Metrics.expand_tabs(original:sub(1,mark.end_byte),0))
      if finish>start then marks[#marks+1]={slot=#marks+1,row=first+mark.line-2,
        start_byte=start,end_byte=finish,appearance=vim.api.nvim_get_hl_id_by_name(mark.hl_group)}end
    end
  end
  return lines,marks,regions,annotations
end
---Recompose the full borrowed canvas without resizing panes or choosing focus.
---@return boolean rendered # True after a valid frame; false when unmounted/stale/dead.
---@return "destroyed"|"stale"|nil reason # Refusal reason, or nil.
function YAbstractItemView:render()
  if self:is_destroyed()then return false,"destroyed"end
  local m=self._mount
  if not self:_valid(m)then if m then self:unmount()end;return false,"stale"end
  self._render_serial=(self._render_serial or 0)+1
  local frame={serial=self._render_serial,revision=self._revision,current_win=vim.api.nvim_get_current_win(),
    view=vim.api.nvim_win_call(m.win,vim.fn.winsaveview)}
  frame.anchor,self._cursor_anchor=self._cursor_anchor,nil
  local old=vim.api.nvim_buf_get_lines(m.buf,frame.view.lnum-1,frame.view.lnum,false)[1] or ''
  frame.display_col=vim.api.nvim_win_call(m.win,function()
    return Metrics.cell_at_byte(old,math.min(frame.view.col,#old))-1+(frame.view.coladd or 0)
  end)
  local geometry=Geometry.get(m.win)
  local width=math.max(logical_width(self._columns,self._widths),geometry.width)
  local height=#self._rows+2
  if self._footer then
    local count=math.max(self._footer.min_height,#self._footer.lines)
    height=math.max(height+count,geometry.height)
  end
  self._layout:activate(0,0,width,height,m.epoch)
  local composed=vim.api.nvim_win_call(m.win,function()
    local left=math.min(frame.view.leftcol,math.max(0,width-geometry.width))
    return {self:_compose(width,height,{left=left,width=geometry.width})}
  end)
  local lines,marks,regions,annotations=unpack(composed)
  m.regions,m.annotations,m.leftcol=regions,annotations,frame.view.leftcol
  m.writer:set_content_size(width,height);m.writer:prepare(self,lines,marks);m.writer:request(self)
  local prior=m.frame;m.frame=frame
  local ok,result,reason=pcall(m.writer.flush,m.writer)
  if m.frame==frame then m.frame=prior end
  if not ok then error(result,0)end
  -- First flushed listener captured the writer's restored/clamped native view.
  -- A later callback owns any focus/cursor change; never correct over it.
  if result and self:_valid(m) and frame.serial==self._render_serial and frame.revision==self._revision
    and frame.expected and frame.current_win==vim.api.nvim_get_current_win()
    and frame.current_win==frame.expected_win then
    local now=vim.api.nvim_win_call(m.win,vim.fn.winsaveview)
    if vim.deep_equal(now,frame.expected)then
      local line=vim.api.nvim_buf_get_lines(m.buf,now.lnum-1,now.lnum,false)[1] or ''
      local byte=Metrics.byte_at_display(line,frame.display_col+1)
      local anchored=Cursor.restore(self,m,frame.anchor,now)
      if anchored or byte~=now.col then
        if not anchored then now.col,now.coladd=byte,0 end
        vim.api.nvim_win_call(m.win,function()
          if self:_valid(m) and frame.serial==self._render_serial then vim.fn.winrestview(now)end
        end)
      end
    end
  end
  return result,reason
end
local window_options={wrap=false,number=false,relativenumber=false,signcolumn='no',foldcolumn='0',foldenable=false,conceallevel=0}
---Read whether the view still owns a live native input and paint target.
---@return boolean mounted # False before mount, after release, on a foreign buffer/window, or after destruction.
function YAbstractItemView:is_mounted()return self:_valid(self._mount)end
---Borrow a native content target; preserve its resources and still-owned options.
---Asserts when the supplied window/buffer identity is invalid or changes during mount.
---@param buf integer Valid buffer transferred to the writer for canvas updates.
---@param win integer Valid window displaying buf, including an inactive tab.
---@return boolean mounted # True after mount; false when destroyed.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YAbstractItemView:mount(buf,win)
  integer(buf,1);integer(win,1)
  assert(vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win)==buf,'invalid table target')
  if self:is_destroyed()then return false,"destroyed"end
  self:unmount();self._epoch=self._epoch+1
  local m={buf=buf,win=win,epoch=self._epoch,owner=Object.new{parent=self},saved={}}
  self._mount=m
  m.modifiable=vim.bo[buf].modifiable
  m.owner._dispose=function()
    if m.autocmd then vim.api.nvim_del_autocmd(m.autocmd)end
    if m.owns_options and vim.api.nvim_buf_is_valid(buf) and not vim.bo[buf].modifiable then vim.bo[buf].modifiable=m.modifiable end
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win)==buf then
      for key,value in pairs(m.saved)do if vim.wo[win][key]==window_options[key]then vim.wo[win][key]=value end end
    end
  end
  local ok,err=pcall(function()
    local target=function()return self:_target()end
    m.writer=Writer.new{parent=m.owner,win=win,buf=buf,generation=m.epoch,current_target=target}
    m.writer:connect('flushed',m.owner,function()
      local frame=m.frame
      if frame and self:_valid(m)then
        frame.expected=vim.api.nvim_win_call(win,vim.fn.winsaveview)
        frame.expected_win=vim.api.nvim_get_current_win()
      end
    end)
    m.owns_options=true;vim.bo[buf].modifiable=false
    for key,value in pairs(window_options)do
      assert(self:_valid(m),'stale table mount')
      m.saved[key]=vim.wo[win][key];vim.wo[win][key]=value
    end
    assert(self:_valid(m),'stale table mount')
    self._focus:register(self,win,buf,m.epoch)
    m.dispatcher=Input.new{parent=m.owner,root=self,focus=self._focus,writer=m.writer,current_target=target,keys=self:_input_keys()}
    m.autocmd=vim.api.nvim_create_autocmd({'WinClosed','BufWipeout','BufWinEnter','VimResized','WinResized','WinScrolled'}, {callback=function(event)
      if self._mount~=m then return end
      if (event.event=='WinClosed' and tonumber(event.match)==m.win)
        or (event.event=='BufWipeout' and event.buf==m.buf)then self:unmount();return end
      if not self:_valid(m)then self:unmount()
      elseif event.event=='VimResized' or event.event=='WinResized'then self:render()
      elseif event.event=='WinScrolled' and (tonumber(event.match)==m.win or vim.v.event[tostring(m.win)])then
        local left=vim.api.nvim_win_call(m.win,vim.fn.winsaveview).leftcol
        if left~=m.leftcol then self:render()end
      end
    end})
    self:render()
    assert(self:_valid(m),'stale table mount')
  end)
  if not ok then pcall(self.unmount,self);error(err,0)end
  return true
end
---Release only owned mappings, marks, observers and options; retain presentation.
---@return boolean unmounted # True for a mounted view; false if already unmounted.
function YAbstractItemView:unmount()
  local m=self._mount;if not m then return false end
  self:_cancel_gesture()
  self._mount,self._gesture=nil,nil
  self._focus:release(self);m.owner:destroy();return true
end
function YAbstractItemView:_cell(col,row)
  local m=self._mount;local strip=m and m.annotations and m.annotations[row]
  if strip and col>=strip.start_cell and col<strip.end_cell then return end
  local start=0
  for _,c in ipairs(self._columns)do
    local edge=start+self._widths[c.id]
    if col>=start and col<=edge then return c.id,col==edge end
    start=edge+1
  end
end
function YAbstractItemView:_part(m,row,column,col)
  local region=m.regions and m.regions[row] and m.regions[row][column]
  if region and col>=region.start_cell and col<region.end_cell then return region.part end
end
function YAbstractItemView:_activate(m,row,col,pointer,revision,key,part)
  local record=self._rows[row-1];local id,separator=self:_cell(col,row)
  if not self:_valid(m) or not self:is_visible() or not self:is_enabled() or revision~=self._revision or not record or record.disabled or not id or separator then return false end
  if pointer then
    if vim.api.nvim_get_current_win()~=m.win then vim.api.nvim_set_current_win(m.win)end
    if not self:_valid(m) or not self:is_visible() or not self:is_enabled() or revision~=self._revision or vim.api.nvim_get_current_win()~=m.win then return false end
    local line=vim.api.nvim_buf_get_lines(m.buf,row,row+1,false)[1]
    vim.api.nvim_win_set_cursor(m.win,{row+1,Metrics.byte_at_display(line,col+1)})
    if not self:_valid(m) or not self:is_visible() or not self:is_enabled() or revision~=self._revision or vim.api.nvim_get_current_win()~=m.win then return false end
  end
  self:_request_cell(record,id,self._generation,{reason=pointer and 'pointer' or 'key',key=key,part=part});return true
end
---Handle checked dispatcher input; direct calls establish state only, not delivery.
---@param kind string Pointer kind or key.
---@param row integer Zero-based buffer row, already resolved by the dispatcher.
---@param col integer Zero-based logical display column, already resolved once.
---@param button integer Left button is 1; key events use 0.
---@param key string Normalized key; CR activates and Escape cancels.
---@param mods? integer [default: nil] Reserved modifier state.
---@param pos? table [default: nil] Native pointer identity supplied by the dispatcher.
---@return boolean accepted # True when handled; false on ignored/stale/dead input.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YAbstractItemView:event(kind,row,col,button,key,mods,pos)
  if self:is_destroyed()then return false,"destroyed"end
  local m=self._mount;if not self:_valid(m) or not self:is_visible() or not self:is_enabled()then self:_cancel_gesture();return false end
  if kind=='key'then
    if key=='<Esc>'then local armed=self._gesture~=nil;self:_cancel_gesture();return armed end
    if not vim.tbl_contains(self:_input_keys(),key) or vim.api.nvim_get_current_win()~=m.win then return false end
    if self._gesture and self._gesture.width then return true end
    local cursor=vim.api.nvim_win_get_cursor(m.win)
    local line=vim.api.nvim_buf_get_lines(m.buf,cursor[1]-1,cursor[1],false)[1]
    return self:_activate(m,cursor[1]-1,Metrics.cell_at_byte(line,cursor[2])-1,false,self._revision,key)
  end
  local view=vim.api.nvim_win_call(m.win,vim.fn.winsaveview)
  local g=Geometry.get(m.win)
  local inside=row>=view.topline-1 and row<view.topline-1+g.height and col>=view.leftcol and col<view.leftcol+g.width
    and (not pos or (pos.winid==m.win and pos.content~=nil))
  local id,separator=self:_cell(col,row);local record=self._rows[row-1]
  if kind=='press' and button==1 then
    self._gesture=nil
    if not inside or not id then return false end
    if row==0 and separator then
      self._gesture={column=id,col=col,width=self._widths[id],epoch=m.epoch,revision=self._revision}
    elseif row==0 and Header.sortable(self,Header.column(self,id)) then
      self._gesture={header=true,column=id,col=col,cancelled=pos and pos.clicks and pos.clicks~=1,
        epoch=m.epoch,revision=self._revision}
    elseif row>=2 and record and not record.disabled and not separator then
      self._gesture={row=record.id,column=id,part=self:_part(m,row,id,col),epoch=m.epoch,revision=self._revision}
    else return false end
    return true
  end
  local gesture=self._gesture
  if not gesture then return false end
  if gesture.epoch~=m.epoch or gesture.revision~=self._revision then self._gesture=nil;return false end
  if kind=='move' and gesture.header then gesture.cancelled=true;return true end
  if kind=='move' and gesture.width then
    if inside then self:set_column_width(gesture.column,math.max(1,gesture.width+col-gesture.col))end
    return true
  end
  if kind=='release' and button==1 then
    self._gesture=nil
    if gesture.header then
      if not gesture.cancelled and inside and row==0 and id==gesture.column and col==gesture.col and not separator then
        self:request_sort(id)
      end
    elseif not gesture.width and inside and record and record.id==gesture.row and id==gesture.column and not separator
      and self:_part(m,row,id,col)==gesture.part then
      self:_activate(m,row,col,true,gesture.revision,nil,gesture.part)
    end
    return true
  end
  return false
end
function YAbstractItemView:_dispose()self:_release_model();self:unmount()end
return YAbstractItemView
-- DOCS: YAbstractItemView example start
-- local ui=require('yana_ui')
-- local model,rows=ui.YObject.new(),{{id='b',cells={name='Beta'}},{id='a',cells={name='Alpha'}}}
-- function model:rows()return rows end
-- function model:generation()return 1 end
-- function model:is_sortable(id)return id=='name' end
-- function model:sort_column()return nil end
-- function model:sort_order()return nil end
-- function model:sort()return false,'unsortable' end
-- local view=ui.YTableView.new{columns={{id='name',title='Name',min_width=2,width=12}}}
-- view:set_model(model)
-- print(view:model()==model)
-- view:destroy();model:destroy()
-- DOCS: YAbstractItemView example end
