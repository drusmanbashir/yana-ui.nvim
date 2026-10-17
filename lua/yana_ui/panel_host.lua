-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- Own registered Neovim splits and floating windows through one panel host.
local grid = require("yana_ui.grid_layout")
local transition = require("yana_ui.panel_transition")
local api = vim.api
local M = {}
---@class YPanelFrame
---@field options? table [default: {}] Local window option values.
---@field title_line? string [default: nil] Winbar override when supplied.
---@field viewport? table [default: { leftcol = 0 }] winsaveview fields; unspecified fields stay unchanged.
---@class YPanelCompactOptions
---@field title fun(win: integer, id: string): string Single-line compact label.
---@field suspend? fun(win: integer, id: string, compact_buf: integer): boolean|nil, string|nil [default: nil] Retain and suspend an existing mount; false plus reason refuses.
---@field resume? fun(win: integer, id: string): boolean|nil, string|nil [default: nil] Paired inverse; resume the current selected page without geometry writes.
---@field hl_group? string [default: TabLine] Borrowed native compact highlight.
---@class YPanelProvider
---@field buffer fun(): integer Return a live borrowed buffer handle.
---@field render fun(win: integer, id: string) Update provider content; return values are ignored.
---@field presentation? fun(win: integer, id: string): YPanelFrame [default: nil] Override the host presentation callback.
---@field compact? YPanelCompactOptions [default: nil] Opt into retained compact presentation.
---@class YPanelHostOptions
---@field root_win? integer [default: current window] Ordinary root window; floating roots are rejected.
---@field presentation? fun(win: integer, id: string): YPanelFrame [default: nil] Compose options, winbar and viewport at commit.
---@class YPanelFloatOptions
---@field width? integer [default: 80] Width capped at columns minus two.
---@field height? integer [default: 20] Height capped at lines minus cmdheight minus two.
---@field enter? boolean [default: false] Focus the float after commit.
---@class YPanelHost
---@field root integer Current ordinary root window; close may choose an owned replacement.
---@field tab integer Root tabpage.
---@field generation integer Current native operation generation.
---@doc brief Apply registered panel providers to native splits and floating windows.
---@doc qt Nested QSplitter host; see |yana-ui-native-window-counterparts|.
---@doc inherits none; buffers are borrowed. close() restores the original root buffer/options and closes host-created windows without deleting provider buffers. The host has no signals or destruction flag.
---@doc property root|root (read-only field)|none|none|option:root_win
---@doc property presentation|none|set_presentation(presentation)|none|option:presentation
---@doc property windows|windows()|none|none|empty table
---@doc property generation|generation (read-only field)|none|none|0
---@doc property collapsed|is_collapsed(id)|set_collapsed(id, boolean)|none|false
---@doc errors Invalid roots, registration data and presentation setters raise assertions. Native helper errors propagate. Protected host operations return nil plus an error string for unavailable roots, invalid split layouts, unregistered panels, failed/invalid buffer providers or window operations. commit()/render() wrap presentation/render callback errors with the panel id. Collapse preflights invalid requests; same-topology transition failures attempt in-place recovery and append recovery failed when external destruction or another error prevents it. Ordinary non-collapse apply attempts the previous arrangement after a window-operation error. Callback side effects outside host ownership cannot be reversed.
---@doc context lua/yana_ui/panel_host.lua|YPanelHost
---@doc setup With your checkout on runtimepath, run this excerpt in Neovim. It borrows the current root, creates one buffer, restores the root, then deletes its buffer.
---@doc example local ui = require("yana_ui")
---@doc example local buf = vim.api.nvim_create_buf(false, true)
---@doc example local host = ui.YPanelHost.new()
---@doc example host:register("main", { buffer = function() return buf end,
---@doc example   render = function() vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Panel" }) end })
---@doc example assert(host:apply({ id = "main" }))
---@doc example assert(host:render())
---@doc example assert(host:close())
---@doc example vim.api.nvim_buf_delete(buf, { force = true })
---@doc see |YGrid|, |geometry|.
local YPanelHost = {}
YPanelHost.__index = YPanelHost
local operations
local panel_options = { number = false, relativenumber = false, signcolumn = "no",
  foldcolumn = "0", statuscolumn = "", winbar = "", winfixwidth = false, winfixheight = false }
local function valid(win) return type(win) == "number" and api.nvim_win_is_valid(win) end
local function in_tab(host, win) return valid(win) and api.nvim_win_get_tabpage(win) == host.tab end
-- WIDGETS Window platform boundary; compatibility clients request native writes.
---Write differing local window options; native option errors propagate.
---@param win integer Native window handle.
---@param values table Option names and values.
---@return nil result # No value is returned.
function M.options(win, values)
  for name, value in pairs(values) do
    if not (name == 'winbar' and require('yana_ui.tab_header').owns(win))
      and api.nvim_get_option_value(name, { win = win, scope = "local" }) ~= value then
      api.nvim_set_option_value(name, value, { win = win, scope = "local" })
    end
  end
end
---Forward a native window configuration update.
---@param win integer Native window handle.
---@param config table nvim_win_set_config fields.
---@return nil result # Native configuration update returns no value.
function M.place(win, config) return api.nvim_win_set_config(win, config) end
---Open a native window; ownership and later cleanup belong to you.
---@param buf integer Live buffer handle.
---@param enter boolean Whether to focus the new window.
---@param config table nvim_open_win fields.
---@return integer win # New native window handle.
function M.open(buf, enter, config) return api.nvim_open_win(buf, enter, config) end
---Close a native window with force enabled; native errors propagate.
---@param win integer Native window handle.
---@return nil result # Native close returns no value.
function M.close(win) return api.nvim_win_close(win, true) end
---Merge winsaveview fields in the target window and restore the resulting view.
---@param win integer Native window handle.
---@param values table winsaveview fields to replace.
---@return any result # Native nvim_win_call result; the view callback returns no explicit value.
function M.viewport(win, values)
  return api.nvim_win_call(win, function()
    local view = vim.fn.winsaveview()
    for name, value in pairs(values) do view[name] = value end
    vim.fn.winrestview(view)
  end)
end
---Set native window height when different, then reset topline to 1 and leftcol to 0.
---@param win integer Native window handle.
---@param rows integer Requested height in cells.
---@return true resized # True after successful native writes.
function M.rows(win, rows)
  if api.nvim_win_get_height(win) ~= rows then api.nvim_win_set_height(win, rows) end
  M.viewport(win, { topline = 1, leftcol = 0 })
  return true
end
local function options(host, win)
  if host.initialized[win] then return end
  host:options(win, panel_options)
  host.initialized[win] = true
end
local function first(node)
  if node.id then return node.id end
  return first(node.children[1].node)
end
local function shape(node)
  if node.id then return #node.id .. ":" .. node.id end
  local parts = { node.axis }
  for _, child in ipairs(node.children) do parts[#parts + 1] = shape(child.node) end
  return "(" .. table.concat(parts, ";") .. ")"
end
local function region(host)
  local row, col, bottom, right = math.huge, math.huge, 0, 0
  local seen = { [host.root] = true }
  for _, win in pairs(host.map) do seen[win] = true end
  for win in pairs(seen) do
    if valid(win) and api.nvim_win_get_tabpage(win) == host.tab and api.nvim_win_get_config(win).relative == "" then
      local pos = api.nvim_win_get_position(win)
      row, col = math.min(row, pos[1]), math.min(col, pos[2])
      bottom, right = math.max(bottom, pos[1] + api.nvim_win_get_height(win)), math.max(right, pos[2] + api.nvim_win_get_width(win))
    end
  end
  return { width = right - col, height = bottom - row }, { row, col }
end
local function protect(host, fn)
  local hidden, outside = {}, {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(host.tab)) do
    if win ~= host.root and not host.owned[win] and api.nvim_win_get_config(win).relative == "" then
      outside[win] = { width = api.nvim_win_get_width(win), height = api.nvim_win_get_height(win) }
    end
  end
  for buf in pairs(host.borrowed) do
    if api.nvim_buf_is_valid(buf) then
      local mode = api.nvim_get_option_value("bufhidden", { buf = buf })
      if mode == "wipe" or mode == "delete" or mode == "unload" then
        hidden[buf] = mode
        api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
      end
    end
  end
  local previous_guard=host._hidden_guard
  host._hidden_guard=hidden
  local ok, a, b = pcall(fn)
  host._hidden_guard=previous_guard
  -- Neovim equalizes siblings when a split closes; retain unrelated allocations.
  local restored, restore_error = pcall(function()
    for win, size in pairs(outside) do
      if in_tab(host, win) then
        if api.nvim_win_get_width(win) ~= size.width then api.nvim_win_set_width(win, size.width) end
        if api.nvim_win_get_height(win) ~= size.height then api.nvim_win_set_height(win, size.height) end
      end
    end
  end)
  for buf, mode in pairs(hidden) do if api.nvim_buf_is_valid(buf) then api.nvim_set_option_value("bufhidden", mode, { buf = buf }) end end
  if not ok then return nil, "window operation failed: " .. tostring(a) end
  if not restored then return nil, "window operation failed: restore external geometry: " .. tostring(restore_error) end
  return a, b
end
local function provider_buffer(host, id)
  local provider = host.providers[id]
  if not provider then return nil, "unregistered panel: " .. id end
  local ok, buf = pcall(provider.buffer)
  if not ok then return nil, "panel buffer failed: " .. id .. ": " .. tostring(buf) end
  if type(buf) ~= "number" or not api.nvim_buf_is_valid(buf) then return nil, "invalid panel buffer: " .. id end
  host.borrowed[buf] = true
  if host._hidden_guard and host._hidden_guard[buf]==nil then
    local mode=vim.bo[buf].bufhidden
    if mode=="wipe"or mode=="delete"or mode=="unload"then
      host._hidden_guard[buf]=mode;vim.bo[buf].bufhidden="hide"
    end
  end
  return buf
end

---Capture the root buffer and panel-related local options; reject a floating or invalid root.
---@param opts? YPanelHostOptions [default: nil] Root and optional presentation callback.
---@return YPanelHost host # New host; construction makes no splits.
function M.new(opts)
  opts = opts or {}
  local root = opts.root_win or api.nvim_get_current_win()
  assert(valid(root) and api.nvim_win_get_config(root).relative == "", "panel_host root must be an ordinary window")
  local original = api.nvim_win_get_buf(root)
  local saved = {}
  for name in pairs(panel_options) do saved[name] = api.nvim_get_option_value(name, { win = root }) end
  return setmetatable({ root = root, tab = api.nvim_win_get_tabpage(root), original = original,
    root_options = saved, providers = {}, map = {}, owned = {}, floats = {}, order = {},
    borrowed = { [original] = true }, initialized = {}, generation = 0,
    presentation = opts.presentation, _collapse=transition.new() }, YPanelHost)
end

---Register or replace callbacks for a nonempty id; retain callback functions,
---not the provider table. buffer() is called when applying or opening a float.
---@param id string Nonempty panel id.
---@param provider YPanelProvider Buffer, render and optional presentation callbacks.
---@return YPanelHost host # This host for chaining.
function YPanelHost:register(id, provider)
  assert(type(id) == "string" and id ~= "", "panel id must be a nonempty string")
  assert(type(provider) == "table" and type(provider.buffer) == "function" and type(provider.render) == "function",
    "panel requires buffer and render providers")
  assert(provider.presentation == nil or type(provider.presentation) == "function", "presentation must be a function")
  local compact=provider.compact
  assert(compact==nil or(type(compact)=="table"and type(compact.title)=="function"),"compact requires title callback")
  if compact then
    assert((compact.suspend==nil and compact.resume==nil)or(type(compact.suspend)=="function"and type(compact.resume)=="function"),"compact lifecycle requires suspend and resume")
    compact=vim.tbl_extend("force",{},compact)
    self._collapse_enabled=true
  end
  self.providers[id] = { buffer = provider.buffer, render = provider.render, presentation = provider.presentation,compact=compact }
  return self
end

---Read valid panel windows in the host tab. A mapped split wins when an id also has a float.
---@return table<string,integer> windows # New id-to-window table.
function YPanelHost:windows()
  local out = {}
  for id, win in pairs(self.map) do if valid(win) and api.nvim_win_get_tabpage(win) == self.tab then out[id] = win end end
  for id, win in pairs(self.floats) do if out[id] == nil and in_tab(self, win) then out[id] = win end end
  return out
end

---Write local options; first save any previously uncaptured root option for close().
---@param win integer Native target window.
---@param values table Local option names and values.
---@return nil result # No value is returned.
function YPanelHost:options(win, values)
  if win == self.root then
    for name in pairs(values) do
      if self.root_options[name] == nil then
        self.root_options[name] = api.nvim_get_option_value(name, { win = win, scope = "local" })
      end
    end
  end
  M.options(win, values)
end

---Replace the host presentation callback; no commit occurs until you request one.
---@param presentation fun(win: integer, id: string): YPanelFrame Required callback.
---@return nil result # No value is returned.
function YPanelHost:set_presentation(presentation)
  assert(type(presentation) == "function", "host presentation must be a function")
  self.presentation = presentation
end

---Compose presentation for each live split and float, then write options and viewport.
---Skip a target if the callback changes the host generation or removes its registration.
---Unknown ids and absent windows are skipped; this method does not call provider render().
---@param ids? string[] [default: current split order] Panels to commit; include float-only ids explicitly.
---@return true|nil committed # True on success; nil on callback/native failure.
---@return string|nil reason # "panel commit failed: <id>: <error>", or nil.
function YPanelHost:commit(ids)
  local generation = self.generation
  for _, id in ipairs(ids or self.order) do
    local provider = self.providers[id]
    local function commit_window(win)
      if provider and in_tab(self, win) then
        if self._collapse_enabled then
          local ok,handled=pcall(transition.commit,self,id,win,operations(self))
          if not ok then return nil,"panel commit failed: "..id..": "..tostring(handled)end
          if handled then return true end
        end
        local compose = provider.presentation or self.presentation
        local ok, reason = pcall(function()
          local frame = compose and compose(win, id) or {}
          if generation ~= self.generation or not in_tab(self, win)
            or (win ~= self.map[id] and win ~= self.floats[id]) then return end
          local values = vim.tbl_extend("force", {}, frame.options or {})
          if frame.title_line ~= nil then values.winbar = frame.title_line end
          self:options(win, values)
          M.viewport(win, vim.tbl_extend("force", { leftcol = 0 }, frame.viewport or {}))
        end)
        if not ok then return nil, "panel commit failed: " .. id .. ": " .. tostring(reason) end
      end
      return true
    end
    local ok, reason = commit_window(self.map[id])
    if not ok then return nil, reason end
    if self.floats[id] ~= self.map[id] then
      ok, reason = commit_window(self.floats[id])
      if not ok then return nil, reason end
    end
  end
  return true
end

local function bind(win,buf)
  if api.nvim_win_get_buf(win)==buf then return end
  local locked=vim.wo[win].winfixbuf
  vim.wo[win].winfixbuf=false
  local ok,why=pcall(api.nvim_win_set_buf,win,buf)
  if valid(win)then vim.wo[win].winfixbuf=locked end
  if not ok then error(why,0)end
end
local function apply(self, tree, bindings)
  if not valid(self.root) or api.nvim_win_get_tabpage(self.root) ~= self.tab then return nil, "root window is unavailable" end
  local bounds, origin
  api.nvim_win_call(self.root, function() bounds = region(self) end)
  local plan, err = grid.split_layout(tree, bounds)
  if not plan then return nil, err end
  local buffers, wanted = {}, {}
  for _, id in ipairs(plan.order) do
    if bindings then buffers[id]=bindings[id]else buffers[id],err=provider_buffer(self,id)end
    if not buffers[id] then return nil, err end
    wanted[id] = true
  end
  local signature = shape(tree)
  local rearrange = self.signature ~= signature
  for id, win in pairs(self.map) do if wanted[id] and not in_tab(self, win) then rearrange = true end end
  return protect(self, function()
    return api.nvim_win_call(self.root, function()
      for id, win in pairs(self.map) do
        if not in_tab(self, win) then self.map[id], self.owned[win] = nil, nil end
      end
      local root_id
      for id, win in pairs(self.map) do if win == self.root then root_id = id end end
      if not root_id or not wanted[root_id] then
        local id = plan.order[1]
        local previous = self.map[id]
        if previous and previous ~= self.root and valid(previous) then api.nvim_win_close(previous, true); self.owned[previous] = nil end
        if root_id then self.map[root_id] = nil end
        self.map[id] = self.root
      end
      for id, win in pairs(self.map) do
        if not wanted[id] then
          if win ~= self.root and self.owned[win] and valid(win) then api.nvim_win_close(win, true) end
          self.owned[win], self.map[id] = nil, nil
        end
      end
      for id, buf in pairs(buffers) do
        local win = self.map[id]
        if valid(win) then bind(win,buf); options(self,win) end
      end
      local function ensure(id, anchor, direction)
        local win = self.map[id]
        if not valid(win) then
          win = api.nvim_open_win(buffers[id], false, { split = direction, win = anchor, noautocmd = true })
          self.map[id], self.owned[win] = win, true
        elseif rearrange and win ~= anchor then
          api.nvim_win_set_config(win, { split = direction, win = anchor })
        end
        options(self, win)
        return win
      end
      local function build(node, anchor)
        if node.id then return end
        local anchors, previous = { anchor }, anchor
        for i = 2, #node.children do
          anchors[i] = ensure(first(node.children[i].node), previous, node.axis == "row" and "right" or "below")
          previous = anchors[i]
        end
        for i, child in ipairs(node.children) do build(child.node, anchors[i]) end
      end
      local anchor = self.map[plan.order[1]]
      if not valid(anchor) then anchor = ensure(plan.order[1], self.root, "above") end
      build(tree, anchor)
      self.order=plan.order
      local committed,reason=self:commit()
      if not committed then error(reason,0)end
      -- Leaf sizes are already authoritative; ordinary split frames propagate them.
      for _ = 1, 2 do
        -- Native chrome can change the available area while presentation runs.
        local current=region(self)
        if not vim.deep_equal(current,bounds)then
          local refreshed,reason=grid.split_layout(tree,current)
          if not refreshed then error(reason,0)end
          bounds,plan=current,refreshed
        end
        for _, id in ipairs(plan.order) do
          local win, rect = self.map[id], plan.rects[id]
          api.nvim_win_set_width(win, rect.width)
          api.nvim_win_set_height(win, rect.height)
        end
      end
      -- Size writes refresh inactive-tab positions after a tabline appears.
      -- Validate the allocated shape relative to that current screen origin.
      local committed,reason=self:commit()
      if not committed then error(reason,0)end
      origin = select(2, region(self))
      for _, id in ipairs(plan.order) do
        local win, rect = self.map[id], plan.rects[id]
        local pos = api.nvim_win_get_position(win)
        if api.nvim_win_get_width(win) ~= rect.width or api.nvim_win_get_height(win) ~= rect.height
          or pos[1] ~= origin[1] + rect.row or pos[2] ~= origin[2] + rect.col then
          error(string.format("window layout does not fit: %s actual=%dx%d at %d,%d expected=%dx%d at %d,%d",
            id, api.nvim_win_get_width(win), api.nvim_win_get_height(win), pos[1], pos[2],
            rect.width, rect.height, origin[1] + rect.row, origin[2] + rect.col), 0)
        end
      end
      self.signature, self.order = signature, plan.order
      return true
    end)
  end)
end


local saved_options={'winbar','winfixheight','winfixwidth','wrap','cursorline','winfixbuf'}
operations=function(host)
  local ops={}
  ops.region=function()return region(host)end
  ops.buffer=function(id)return provider_buffer(host,id)end
  ops.apply=function(tree,buffers)return apply(host,tree,buffers)end
  ops.protect=function(fn)return protect(host,fn)end
  ops.bind=bind
  ops.view=M.viewport
  ops.peek=function(win)return api.nvim_win_call(win,vim.fn.winsaveview)end
  ops.restore_options=function(win,values)
    host:options(win,values)
    -- A buffer swap can retain the option string with a zero native bar height.
    if values.winbar~=nil and not require('yana_ui.tab_header').owns(win)then
      api.nvim_set_option_value('winbar',values.winbar,{win=win,scope='local'})
    end
  end
  ops.compact_options=function(win,axis,values)
    host:options(win,vim.tbl_extend('force',{},values or {},
      {winbar='',wrap=false,cursorline=false,winfixheight=axis=='column',winfixwidth=axis=='row'}))
    M.viewport(win,{topline=1,leftcol=0})
  end
  ops.normalise=function(win)
    if api.nvim_get_current_win()==win then vim.cmd('stopinsert')end
  end
  ops.save=function(win)
    local values={};for _,name in ipairs(saved_options)do values[name]=vim.wo[win][name]end
    return {buf=api.nvim_win_get_buf(win),view=api.nvim_win_call(win,vim.fn.winsaveview),options=values,
      width=api.nvim_win_get_width(win),height=api.nvim_win_get_height(win)}
  end
  ops.geometry=function()
    local result={}
    for id,win in pairs(host.map)do if in_tab(host,win)then
      result[id]={win=win,width=api.nvim_win_get_width(win),height=api.nvim_win_get_height(win),position=api.nvim_win_get_position(win)}
    end end
    return result
  end
  ops.snapshot=function()
    local result={windows={},focus=api.nvim_get_current_win(),root_options=vim.deepcopy(host.root_options)}
    for id,win in pairs(host.map)do if in_tab(host,win)then result.windows[id]={win=win,saved=ops.save(win)}end end
    return result
  end
  ops.restore=function(snapshot)
    for id,item in pairs(snapshot.windows)do
      assert(host.map[id]==item.win and in_tab(host,item.win),'window identity lost: '..id)
      bind(item.win,item.saved.buf);host:options(item.win,item.saved.options)
    end
    for _=1,2 do for _,item in pairs(snapshot.windows)do
      api.nvim_win_set_width(item.win,item.saved.width);api.nvim_win_set_height(item.win,item.saved.height)
    end end
    for _,item in pairs(snapshot.windows)do M.viewport(item.win,item.saved.view)end
    host.root_options=snapshot.root_options
    if valid(snapshot.focus)then api.nvim_set_current_win(snapshot.focus)end
  end
  ops.minima=function(intent)
    local result={};for id,provider in pairs(host.providers)do
      result[id]={width=math.max(1,vim.o.winminwidth),height=intent[id]and math.max(1,vim.o.winminheight)
        or provider.compact and math.max(2,vim.o.winminheight+1)or math.max(1,vim.o.winminheight)}
      local entry=host._collapse.entries[id];local win=host.map[id]
      if entry and entry.detached and in_tab(host,win)then
        result[id].height=math.max(1,vim.o.winminheight+(vim.wo[win].winbar~=''and 1 or 0))
      end
    end;return result
  end
  return ops
end

---Read collapse intent for a registered panel.
---@param id string Registered panel id.
---@return boolean collapsed True when compact, including temporarily omitted panels.
function YPanelHost:is_collapsed(id)
  assert(self.providers[id],'unregistered panel: '..tostring(id))
  return self._collapse.intent[id]==true
end
---Read a detached set of compact panel ids.
---@return table<string,boolean> collapsed A new true-valued set.
function YPanelHost:collapsed()return vim.deepcopy(self._collapse.intent)end
---Collapse or restore an arranged panel without replacing its native split.
---@param id string Registered arranged panel id.
---@param collapsed boolean Requested state.
---@return true|false|nil changed True on change, false on no-op, nil on refusal.
---@return string|nil reason Named refusal or transition/recovery failure.
function YPanelHost:set_collapsed(id,collapsed)
  assert(type(collapsed)=='boolean','collapsed must be boolean')
  if not self.providers[id]or not self.providers[id].compact then return nil,'panel does not support collapse: '..tostring(id)end
  if not in_tab(self,self.map[id])then return nil,'panel is not arranged: '..id end
  if self:is_collapsed(id)==collapsed then return false end
  local intent=self:collapsed();intent[id]=collapsed and true or nil
  return self:apply(self.tree,{collapsed=intent})
end

---Retain the current tree, collapse intent and measured allocation inside this host.
---@return table|nil checkpoint Opaque host-owned handle; nil without an applied tree.
---@return string|nil reason Missing layout.
function YPanelHost:save_layout()return transition.save_layout(self,operations(self))end
---Apply a saved arrangement atomically, optionally collapsing one pane in it.
---@param checkpoint table Handle returned by this host's save_layout().
---@param opts? table [default: nil] Optional collapse panel id.
---@return true|nil restored True on success; nil on refusal/failure.
---@return string|nil reason Unknown handle or apply failure.
function YPanelHost:restore_layout(checkpoint,opts)return transition.restore_layout(self,checkpoint,opts,operations(self))end
---Release a retained layout handle without changing the displayed layout.
---@param checkpoint table Handle returned by save_layout().
---@return boolean removed True if this host retained the handle.
function YPanelHost:forget_layout(checkpoint)return transition.forget_layout(self,checkpoint)end

---Increment generation, validate dimensions/providers, then create, resize or close
---registered splits. On success retain a copied tree and commit presentation.
---A window-operation failure closes owned windows and attempts the previous tree.
---@param tree YSplitNode Split tree for require("yana_ui.grid_layout").split_layout().
---@param opts? table [default: nil] Optional replacement collapsed true-valued set.
---@return true|nil applied # True on success; nil on failure.
---@return string|nil reason # Shared host/layout error, with recovery details when needed.
function YPanelHost:apply(tree, opts)
  if self._collapse_enabled then return transition.apply(self,tree,opts,operations(self))end
  self.generation = self.generation + 1
  local previous = self.tree
  local ok, err = apply(self, tree)
  if ok then self.tree = vim.deepcopy(tree); return true end
  if err and err:find("window operation failed:", 1, true) == 1 then
    local closed, close_error = self:close()
    if not closed then return nil, err .. "; recovery failed: " .. tostring(close_error) end
    if previous then
      local recovered, recovery_error = apply(self, previous)
      if not recovered then return nil, err .. "; recovery failed: " .. tostring(recovery_error) end
      self.tree = previous
    end
  end
  return nil, err
end

---Call render(win, id) for registered panels with live windows, then commit presentation.
---Only one window per id is rendered; windows() prefers the split over its float.
---@param ids? string[] [default: current split order] Panels to render; include float-only ids explicitly.
---@return true|nil rendered # True on success; nil on failure.
---@return string|nil reason # Unregistered-panel, panel-render or panel-commit error; nil on success.
function YPanelHost:render(ids)
  if self._collapse_enabled then transition.begin_render(self,operations(self))end
  local windows = self:windows()
  ids = ids or self.order
  for _, id in ipairs(ids) do
    local provider, win = self.providers[id], windows[id]
    if not provider then return nil, "unregistered panel: " .. tostring(id) end
    if win and not transition.compact(self,id,win)then
      local ok, err = pcall(provider.render, win, id)
      if not ok then return nil, "panel render failed: " .. id .. ": " .. tostring(err) end
    end
  end
  local ok,why=self:commit(ids)
  if ok and self._collapse_enabled then transition.restore_views(self,operations(self),true)end
  return ok,why
end

---Open or update an editor-relative float for a registered borrowed buffer,
---commit its presentation and optionally focus it. The float starts at row 1, col 1.
---@param id string Registered panel id.
---@param opts? YPanelFloatOptions [default: nil] Size and focus options.
---@return integer|nil win # Native float handle, or nil on failure.
---@return string|nil reason # Shared host/layout error, or nil.
function YPanelHost:float(id, opts)
  opts = opts or {}
  if not in_tab(self, self.root) then return nil, "root window is unavailable" end
  local buf, err = provider_buffer(self, id)
  if not buf then return nil, err end
  local plan
  plan, err = grid.split_layout({ id = id }, { width = math.min(opts.width or 80, vim.o.columns - 2),
    height = math.min(opts.height or 20, vim.o.lines - vim.o.cmdheight - 2) })
  if not plan then return nil, err end
  local rect = plan.rects[id]
  return protect(self, function()
    local win = self.floats[id]
    local config = { relative = "editor", row = 1, col = 1, width = rect.width, height = rect.height, border = "single", win = self.root }
    if in_tab(self, win) then api.nvim_win_set_buf(win, buf); api.nvim_win_set_config(win, config)
    else config.noautocmd = true; win = api.nvim_open_win(buf, opts.enter == true, config); self.floats[id] = win end
    options(self, win)
    local committed, reason = self:commit({ id })
    if not committed then error(reason, 0) end
    if opts.enter == true then api.nvim_set_current_win(win) end
    return win
  end)
end

---Close owned windows, restore the root buffer and saved options, clear arrangement
---state and advance generation. Registrations remain reusable and buffers stay borrowed.
---Repeated close() is supported; an invalid tab can still raise before protection.
---@return true|nil closed # True after cleanup; nil on protected native failure.
---@return string|nil reason # Window-operation error, or nil.
function YPanelHost:close()
  return protect(self, function()
    -- Neovim keeps one ordinary window per tab even after the root was closed.
    if not in_tab(self, self.root) and api.nvim_tabpage_is_valid(self.tab) then
      local replacement, outside
      for _, win in ipairs(api.nvim_tabpage_list_wins(self.tab)) do
        if api.nvim_win_get_config(win).relative == "" then
          if self.owned[win] then replacement = replacement or win else outside = true end
        end
      end
      if replacement and not outside then self.root = replacement end
    end
    for _, win in pairs(self.floats) do if in_tab(self, win) then api.nvim_win_close(win, true) end end
    for win in pairs(self.owned) do if in_tab(self, win) and win ~= self.root then api.nvim_win_close(win, true) end end
    if in_tab(self, self.root) then
      if api.nvim_buf_is_valid(self.original) then bind(self.root,self.original) end
      for name, value in pairs(self.root_options) do api.nvim_set_option_value(name, value, { win = self.root }) end
    end
    transition.close(self)
    self.map, self.owned, self.floats, self.order, self.signature, self.tree = {}, {}, {}, {}, nil, nil
    self.initialized = {}
    self.generation = self.generation + 1
    return true
  end)
end

-- DOCS: YPanelHost example start
-- local ui = require("yana_ui")
-- local buf = vim.api.nvim_create_buf(false, true)
-- local host = ui.YPanelHost.new()
-- host:register("main", { buffer = function() return buf end,
--   render = function() vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Panel" }) end })
-- assert(host:apply({ id = "main" }))
-- assert(host:render())
-- assert(host:close())
-- vim.api.nvim_buf_delete(buf, { force = true })
-- DOCS: YPanelHost example end
return M
