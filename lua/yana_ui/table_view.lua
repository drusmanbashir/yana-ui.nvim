-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- WIDGETS TV-01..16, TV-M01: flat concrete view; YAbstractItemView owns paint, input and model glue.
local Base=require('yana_ui.abstract_item_view')
---@class YTableViewOptions : YAbstractItemViewOptions
---@class YTableView : YAbstractItemView
---@doc brief Display consumer records in a scrollable table with draggable column widths.
---@doc qt QTableView/QHeaderView Interactive. Flat rows only; header requests and confirmed indicators are separate. Supply ordered rows, or attach a model with set_model.
---@doc inherits |YAbstractItemView|; columns, rows, widths, sorting, model binding, native target ownership and activation retain their semantics.
---@doc errors Validation and refusals follow |YAbstractItemView|.
---@doc context lua/yana_ui/table_view.lua|YTableView
---@doc setup Run this in Neovim with yana-ui on runtimepath. You supply and clean up the borrowed scratch window/buffer after destroying the table.
---@doc example local ui=require('yana_ui')
---@doc example local owner,buf=ui.YObject.new(),vim.api.nvim_create_buf(false,true)
---@doc example local win=vim.api.nvim_open_win(buf,false,{relative='editor',row=1,col=1,width=30,height=5,style='minimal'})
---@doc example local table=ui.YTableView.new{parent=owner,columns={{id='name',title='Name',min_width=2,width=12}}}
---@doc example table:set_rows({{id='first',cells={name='Example'}}},1)
---@doc example table:mount(buf,win)
---@doc example owner:destroy()
---@doc example vim.api.nvim_win_close(win,true);vim.api.nvim_buf_delete(buf,{force=true})
---@doc see |YAbstractItemView|, |YTreeView|, |YWidget|.
local YTableView=setmetatable({},{__index=Base});YTableView.__index=YTableView
---Construct a visible unmounted table; native targets remain consumer-owned.
---Asserts when constructor options or columns are invalid.
---@param opts YTableViewOptions Required columns and optional owner/groups.
---@return YTableView view # New table with detached presentation state and no model.
function YTableView.new(opts)return setmetatable(Base.new(opts),YTableView)end
return YTableView
-- DOCS: YTableView example start
-- local ui=require('yana_ui')
-- local owner,buf=ui.YObject.new(),vim.api.nvim_create_buf(false,true)
-- local win=vim.api.nvim_open_win(buf,false,{relative='editor',row=1,col=1,width=30,height=5,style='minimal'})
-- local table=ui.YTableView.new{parent=owner,columns={{id='name',title='Name',min_width=2,width=12}}}
-- table:set_rows({{id='first',cells={name='Example'}}},1)
-- table:mount(buf,win)
-- owner:destroy()
-- vim.api.nvim_win_close(win,true);vim.api.nvim_buf_delete(buf,{force=true})
-- DOCS: YTableView example end
