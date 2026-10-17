-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- COLLAPSE: orchestrate host-owned state through panel_host's native operations.
local Collapse=require('yana_ui.panel_collapse')
local Compact=require('yana_ui.panel_compact')
local Grid=require('yana_ui.grid_layout')
local api=vim.api
local M={}
function M.new()
  return {intent={},entries={},shares={},busy=false,checkpoints={}}
end
local function state(host)return host._collapse end
local function detached(host,id,win,entry)
  if not win or not api.nvim_win_is_valid(win)then
    if entry.detached then entry.detached=nil;entry.saved=nil end
    return false
  end
  if entry.detached then return true end
  if win and api.nvim_win_is_valid(win)and(api.nvim_win_get_buf(win)~=entry.buf or vim.wo[win].winbar~='')then
    host.borrowed[api.nvim_win_get_buf(win)]=true
    Compact.release(entry);entry.detached=true
  end
  return entry.detached==true
end
function M.intent(host)return state(host).pending or state(host).intent end
function M.compact(host,id,win)
  return M.intent(host)[id]and host.map[id]==win and state(host).entries[id]or nil
end
local function call(provider,method,win,id,buf)
  local fn=provider.compact and provider.compact[method]
  if not fn then return end
  local ok,why=fn(win,id,buf)
  if ok==false and why then error(method..' '..id..': '..tostring(why),0)end
end
local function validate_intent(host,intent)
  if type(intent)~='table'then return nil,'collapsed must be a set'end
  for id,value in pairs(intent)do
    if value~=true or not host.providers[id]or not host.providers[id].compact then
      return nil,'panel does not support collapse: '..tostring(id)
    end
  end
  return true
end
local function measured(host,ops)
  local s=state(host)
  if not host.tree then return s.shares end
  local bounds=ops.region()
  if s.bounds and not vim.deep_equal(bounds,s.bounds)then return s.shares end
  return Collapse.capture(host.tree,s.intent,s.shares,host.map)
end
function M.commit(host,id,win,ops)
  local entry=M.compact(host,id,win)
  if not entry then return false end
  local s=state(host);local provider=host.providers[id]
  if entry.detached or(not s.busy and detached(host,id,win,entry))then return true end
  local function valid()
    return M.compact(host,id,win)==entry and api.nvim_win_is_valid(win)
      and api.nvim_win_get_buf(win)==entry.buf
  end
  local generation=host.generation
  local compose=provider.presentation or host.presentation
  local frame=compose and compose(win,id)or{}
  if generation~=host.generation or provider~=host.providers[id]or not valid()then return true end
  ops.compact_options(win,entry.axis,frame.options)
  Compact.mount(entry,win,entry.axis,valid,function()
    if s.busy then return end
    local ok,why=host:set_collapsed(id,false)
    if ok then
      local rendered,reason=host:render({id})
      if not rendered then vim.notify(reason,vim.log.levels.ERROR)end
    elseif why then vim.notify(why,vim.log.levels.WARN)end
  end)
  Compact.paint(entry,provider.compact.title(win,id),provider.compact.hl_group)
  return true
end
function M.restore_views(host,ops,clear)
  for id,entry in pairs(state(host).entries)do
    local saved=entry.restore_view
    local win=host.map[id]
    if saved and win and api.nvim_win_is_valid(win)and api.nvim_win_get_buf(win)==saved.buf then
      ops.view(win,saved.view)
      entry.applied_view=ops.peek(win)
    end
    if clear then entry.restore_view=nil end
  end
end
function M.begin_render(host,ops)
  for id,entry in pairs(state(host).entries)do
    if entry.restore_view and entry.applied_view then
      local win=host.map[id]
      local view=win and api.nvim_win_is_valid(win)and ops.peek(win)
      for _,key in ipairs({'topline','lnum','col','leftcol'})do
        if not view or view[key]~=entry.applied_view[key]then entry.restore_view=nil;break end
      end
    end
  end
end

function M.apply(host,tree,opts,ops)
  local s=state(host)
  if s.busy then return nil,'panel transition is busy'end
  local intent=vim.deepcopy(opts and opts.collapsed or s.intent)
  local valid,why=validate_intent(host,intent);if not valid then return nil,why end
  local parsed;parsed,why=Grid._parse_split(tree);if not parsed then return nil,why end
  local cache=opts and opts.shares or measured(host,ops)
  local native,buffers={},{}
  local function collect(node)
    if node.id then
      local entry=s.entries[node.id];local win=host.map[node.id]
      if s.intent[node.id]and entry and detached(host,node.id,win,entry)and not intent[node.id]then
        error('compact target replaced: '..node.id,0)
      end
      local provider=host.providers[node.id]
      if not provider then error('unregistered panel: '..node.id,0)end
      local buf,err=ops.buffer(node.id);if not buf then error(err,0)end
      buffers[node.id]=buf
      native[node.id]={width=math.max(1,vim.o.winminwidth),height=math.max(1,vim.o.winminheight)}
      if not intent[node.id]and provider.compact then native[node.id].height=math.max(2,vim.o.winminheight+1)end
      if entry and entry.detached and win and api.nvim_win_is_valid(win)then
        native[node.id].height=math.max(1,vim.o.winminheight+(vim.wo[win].winbar~=''and 1 or 0))
      end
    else for _,edge in ipairs(node.children)do collect(edge.node)end end
  end
  local prepared,error_message=pcall(collect,tree)
  if not prepared then return nil,tostring(error_message)end
  local derived;derived,why=Collapse.derive(tree,intent,cache,native);if not derived then return nil,why end
  local bounds=ops.region()
  local plan;plan,why=Grid.split_layout(derived.tree,bounds);if not plan then return nil,why end
  local snapshot=ops.snapshot()
  local oldtree,oldintent,oldshares=host.tree,s.intent,s.shares
  local oldentries={};for id,e in pairs(s.entries)do oldentries[id]=vim.tbl_extend('force',{},e)end
  local previous_bindings={};for id,w in pairs(host.map)do
    if api.nvim_win_is_valid(w)then previous_bindings[id]=api.nvim_win_get_buf(w)end
  end
  local new_entries,changes={},{}
  local function stage()
    s.busy=true;s.pending=intent
    for _,entry in pairs(s.entries)do entry.restore_view=nil;entry.applied_view=nil end
    for id,details in pairs(derived.compact)do
      local entry=s.entries[id]
      if not entry then entry=Compact.new();s.entries[id]=entry;new_entries[id]=entry end
      Compact.release(entry)
      entry.axis=details.axis
      local win=host.map[id]
      if win and not oldintent[id]then
        entry.saved=ops.save(win);entry.saved.provider=host.providers[id]
        call(host.providers[id],'suspend',win,id,entry.buf)
        changes[#changes+1]={id=id,method='suspend',win=win}
        ops.normalise(win)
      end
      buffers[id]=entry.detached and api.nvim_win_get_buf(host.map[id])or entry.buf
    end
    for id in pairs(oldintent)do
      local win=host.map[id];local entry=s.entries[id]
      if win and not intent[id]and derived.arranged[id]and entry then
        Compact.release(entry)
        call(host.providers[id],'resume',win,id,entry.buf)
        changes[#changes+1]={id=id,method='resume',win=win}
        local buf,err=ops.buffer(id);if not buf then error(err,0)end
        buffers[id]=buf
        ops.bind(win,buf)
        if entry.saved then
          local values=vim.tbl_extend("force",{},entry.saved.options)
          if entry.saved.provider~=host.providers[id]or buf~=entry.saved.buf then values.winbar=nil end
          ops.restore_options(win,values)
          if buf==entry.saved.buf then entry.restore_view=entry.saved end
        end
      end
    end
    host.generation=host.generation+1
    local ok,err=ops.apply(derived.tree,buffers)
    if not ok then error(err,0)end
    -- New or formerly omitted compact leaves acquire their mount after creation.
    for id in pairs(derived.compact)do
      if not previous_bindings[id]then
        local win=host.map[id];local entry=s.entries[id]
        call(host.providers[id],'suspend',win,id,entry.buf)
      end
    end
    M.restore_views(host,ops,false)
    return true
  end
  local result,err=ops.protect(function()
    local ok,reason=pcall(stage)
    if ok then return true end
    s.pending=oldintent
    local recovered,recovery_error=pcall(function()
      for i=#changes,1,-1 do
        local change=changes[i];local entry=s.entries[change.id]
        if change.method=='suspend'then
          call(host.providers[change.id],'resume',change.win,change.id,entry.buf)
        else call(host.providers[change.id],'suspend',change.win,change.id,entry.buf)end
      end
      for id,entry in pairs(new_entries)do Compact.release(entry);s.entries[id]=nil end
      for id,entry in pairs(oldentries)do
        -- Active dispatcher resources are recreated by commit, never resurrected.
        Compact.release(s.entries[id]or entry)
        entry.owner=nil;entry.armed=nil;s.entries[id]=entry
      end
      if oldtree then
        local oldderived=assert(Collapse.derive(oldtree,oldintent,oldshares,ops.minima(oldintent)))
        local restored,restore_error=ops.apply(oldderived.tree,previous_bindings)
        assert(restored,restore_error)
      end
      ops.restore(snapshot)
    end)
    for _,entry in pairs(new_entries)do Compact.destroy(entry)end
    if not recovered then return nil,tostring(reason)..'; recovery failed: '..tostring(recovery_error)end
    return nil,tostring(reason)
  end)
  s.pending=nil;s.busy=false
  if not result then return nil,err end
  host.tree=vim.deepcopy(tree);s.intent=intent;s.shares=cache
  s.bounds=ops.region();s.geometry=ops.geometry()
  if not s.group then
    s.group=api.nvim_create_augroup('YanaPanelResize'..host.root,{clear=true})
    api.nvim_create_autocmd('WinScrolled',{group=s.group,callback=function()
      if s.busy then return end
      for id in pairs(s.intent)do
        local win=host.map[id]
        if win and api.nvim_win_is_valid(win)then
          local view=ops.peek(win)
          if view.topline~=1 or view.leftcol~=0 then
            local ok,reason=host:commit({id});if not ok then vim.notify(reason,vim.log.levels.WARN)end
          end
        end
      end
    end})
    api.nvim_create_autocmd('WinResized',{group=s.group,callback=function()
      if s.busy or not host.tree or not api.nvim_win_is_valid(host.root)then return end
      local current=ops.geometry()
      if vim.deep_equal(current,s.geometry)then return end
      local now=ops.region()
      if vim.deep_equal(now,s.bounds)then s.shares=measured(host,ops)end
      if next(s.intent)then
        local ok,reason=M.apply(host,host.tree,{shares=s.shares},ops)
        if not ok then vim.notify(reason,vim.log.levels.WARN)end
      else s.bounds=now;s.geometry=current end
    end})
  end
  return true
end
function M.save_layout(host,ops)
  if not host.tree then return nil,'host has no layout'end
  local s=state(host);local token={}
  s.checkpoints[token]={tree=vim.deepcopy(host.tree),intent=vim.deepcopy(s.intent),shares=measured(host,ops)}
  return token
end
function M.restore_layout(host,token,opts,ops)
  local saved=state(host).checkpoints[token]
  if not saved then return nil,'unknown layout checkpoint'end
  local intent=vim.deepcopy(saved.intent)
  if opts and opts.collapse then intent[opts.collapse]=true end
  return M.apply(host,saved.tree,{collapsed=intent,shares=saved.shares},ops)
end
function M.forget_layout(host,token)
  local s=state(host);local had=s.checkpoints[token]~=nil;s.checkpoints[token]=nil;return had
end

function M.close(host)
  local s=state(host)
  if s.group then api.nvim_del_augroup_by_id(s.group)end
  for _,entry in pairs(s.entries)do Compact.destroy(entry)end
  host._collapse=M.new()
end
return M
