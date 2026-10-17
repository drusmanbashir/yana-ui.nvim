-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-FileCopyrightText: 2016 The Qt Company Ltd
-- SPDX-License-Identifier: LGPL-3.0-only
-- Derived from Qt src/widgets/kernel/qapplication.cpp:2038-2124,2262-2311,2364-2376 (qtbase v6.8.3).
-- Modified: Lua/Neovim adaptation by Usman Bashir; notice added 2026-10-08.
local geometry = require("yana_ui.geometry")
local context_anchor = require("yana_ui.context_anchor")
---@alias YInputMapping string|fun():any
local M = {}
local owners, mappings, latest = {}, {}, {}
local right_release_owners = {}
local mouse_modes = { "n", "i" }
local native, installed, global_owner = {}, {}, {}
local count, owner_serial = 0, 0
local owner_order, owner_priority = {}, {}
local pointer_keys = { ["<LeftMouse>"] = { "press", 1 }, ["<LeftRelease>"] = { "release", 1 },
  ["<RightRelease>"] = { "release", 3 },
  ["<MouseMove>"] = { "move", 0 }, ["<LeftDrag>"] = { "move", 1 },
  ["<RightMouse>"] = { "right", 3 }, ["<ScrollWheelUp>"] = { "wheel", 0, "up" },
  ["<ScrollWheelDown>"] = { "wheel", 0, "down" }, ["<ScrollWheelLeft>"] = { "wheel", 0, "left" },
  ["<ScrollWheelRight>"] = { "wheel", 0, "right" } }
for clicks = 2, 4 do
  for suffix, kind in pairs({ Mouse = "press", Release = "release", Drag = "move" }) do
    pointer_keys["<" .. clicks .. "-Left" .. suffix .. ">"] = { kind, 1, nil, clicks }
  end
end

local function route_pointer(kind, pos, button, key)
  if vim.fn.pumvisible() == 1 then return false end
  -- WIDGETS pointer: one native target and content conversion per intake.
  pos.content = geometry.pointer(pos.winid, pos)
  pos.content_resolved = true
  local ordered = {}
  for owner, handler in pairs(owners) do
    local layer, zindex = 0, 0
    if owner_priority[owner] then layer, zindex = owner_priority[owner]() end
    ordered[#ordered + 1] = { owner = owner, handler = handler, layer = layer,
      zindex = zindex, serial = owner_order[owner] }
  end
  table.sort(ordered, function(a, b)
    if a.layer ~= b.layer then return a.layer > b.layer end
    if a.zindex ~= b.zindex then return a.zindex > b.zindex end
    return a.serial > b.serial
  end)
  for _, entry in ipairs(ordered) do
    -- Legacy acquire handlers historically receive only left releases.
    if owners[entry.owner] == entry.handler
      and (kind ~= "release" or button ~= 3 or right_release_owners[entry.owner])
      and entry.handler(kind, pos, button, key) ~= false then return true end
  end
  return false
end

local function snapshot(mode, lhs, buf)
  local maps = buf and vim.api.nvim_buf_get_keymap(buf, mode) or vim.api.nvim_get_keymap(mode)
  for _, map in ipairs(maps) do if map.lhs == lhs then return map end end
  local raw = vim.api.nvim_replace_termcodes(lhs, true, false, true)
  for _, map in ipairs(maps) do if map.lhsraw == raw then return map end end
end

local function same(a, b)
  return a ~= nil and b ~= nil and vim.deep_equal(a, b)
end

---Install an owned mapping and remember its predecessor. release(owner)
---restores it only while this mapping remains current, preserving later foreign
---mappings. Native keymap argument errors propagate.
---@param owner any Non-nil identity used to group mappings for release.
---@param mode string Native mapping mode, for example "n".
---@param lhs string Native left-hand-side key name.
---@param callback YInputMapping Native mapping text or callback.
---@param opts? table [default: nil] Native keymap options; buffer true or 0 resolves the current buffer.
---@return YInputMapping callback # The supplied native mapping text or callback.
function M.map(owner, mode, lhs, callback, opts)
  opts = vim.tbl_extend("force", {}, opts or {})
  local buf = opts.buffer
  if buf == true or buf == 0 then buf = vim.api.nvim_get_current_buf(); opts.buffer = buf end
  local key = tostring(buf or 0) .. ":" .. mode .. ":" .. lhs
  local previous = snapshot(mode, lhs, buf)
  local parent = latest[key]
  if not parent or not same(previous, parent.installed) then parent = nil end
  vim.keymap.set(mode, lhs, callback, opts)
  local record = { key = key, mode = mode, lhs = lhs, buf = buf,
    previous = previous, parent = parent, installed = snapshot(mode, lhs, buf), active = true }
  mappings[owner] = mappings[owner] or {}
  mappings[owner][#mappings[owner] + 1], latest[key] = record, record
  return callback
end

local function release_maps(owner)
  for i = #(mappings[owner] or {}), 1, -1 do
    local record = mappings[owner][i]
    record.active = false
    if not record.buf or vim.api.nvim_buf_is_valid(record.buf) then
      if same(snapshot(record.mode, record.lhs, record.buf), record.installed) then
        local source = record
        while source.parent and not source.parent.active do source = source.parent end
        local previous = source.parent and source.parent.installed or source.previous
        local function restore()
          if previous then vim.fn.mapset(record.mode, false, previous)
          else vim.keymap.del(record.mode, record.lhs, record.buf and { buffer = record.buf } or {}) end
        end
        if record.buf then vim.api.nvim_buf_call(record.buf, restore) else restore() end
        latest[record.key] = source.parent
      elseif latest[record.key] == record then latest[record.key] = nil end
    elseif latest[record.key] == record then latest[record.key] = nil end
  end
  mappings[owner] = nil
end

local function fallback(lhs, previous)
  -- Insert before already queued release/drag events; never execute typeahead
  -- inside this mapping. Native cursor movement must precede release handlers.
  if previous and previous.callback then
    local value = previous.callback()
    if previous.expr == 0 or type(value) ~= "string" then return end
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(value, true, false, true), "ni", false)
  elseif previous and previous.rhs and previous.rhs ~= "" then
    local rhs = vim.api.nvim_replace_termcodes(previous.rhs, true, false, true)
    local key = vim.api.nvim_replace_termcodes(lhs, true, false, true)
    if previous.noremap ~= 1 and rhs:sub(1, #key) == key then
      -- Native :map skips a leading copy of its lhs (map.txt recursive_mapping).
      -- Insert the remappable tail first, then the native key ahead of it.
      local tail = rhs:sub(#key + 1)
      if tail ~= "" then vim.api.nvim_feedkeys(tail, "mi", false) end
      vim.api.nvim_feedkeys(key, "ni", false)
    else vim.api.nvim_feedkeys(rhs, previous.noremap == 1 and "ni" or "mi", false) end
  else vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(lhs, true, false, true), "ni", false) end
end

local function release_escape_maps(owner)
  local maps=owner.escape_maps;owner.escape_maps=nil
  if maps then M.release(maps)end
end
local function release_pointer_tail(owner)
  if not owner then return end
  vim.api.nvim_del_autocmd(owner.autocmd)
  release_escape_maps(owner)
  M.release(owner)
end
local function map_pointer_tail(owner, button, handler, cancel)
  local buffers = {}
  if cancel then owner.escape_maps={}end
  local function bind()
    local buf = vim.api.nvim_get_current_buf()
    if buffers[buf] then return end
    buffers[buf] = true
    for _, mode in ipairs(mouse_modes) do
      if cancel and owner.escape_maps then
        M.map(owner.escape_maps,mode,'<Esc>',function()cancel()end,
          {buffer=buf,silent=true,nowait=true,desc='yana-ui: cancel pointer grab'})
      end
      for lhs, event in pairs(pointer_keys) do
        local kind = event[1]
        if ((kind == "release" or kind == "move") and event[2] == button)
          or kind == "press" or kind == "right" then
          local previous = snapshot(mode, lhs, buf) or snapshot(mode, lhs)
          M.map(owner, mode, lhs, function()
            local pos=vim.fn.getmousepos();pos.clicks=event[4]or 1
            if handler(kind,pos,event[2],event[3]or "")==false then
              fallback(lhs, previous)
            end
          end, {buffer=buf,silent=true,nowait=true,desc="yana-ui: pointer grab"})
        end
      end
    end
  end
  owner.autocmd = vim.api.nvim_create_autocmd("BufEnter", {callback=bind})
  bind()
end

local function install_mouse(label)
  native.mouse, native.mousemoveevent = vim.o.mouse, vim.o.mousemoveevent
  local mouse = native.mouse
  if not mouse:find("a", 1, true) then
    for _, mode in ipairs(mouse_modes) do if not mouse:find(mode, 1, true) then mouse = mouse .. mode end end
  end
  installed.mouse, installed.mousemoveevent = mouse, true
  vim.o.mouse, vim.o.mousemoveevent = mouse, true
  for _, mode in ipairs(mouse_modes) do
    for lhs, event in pairs(pointer_keys) do
      local kind = event[1]
      local previous = snapshot(mode, lhs)
      M.map(global_owner, mode, lhs, function()
        local pos = vim.fn.getmousepos();pos.clicks=event[4]or 1
        -- FIX-5: Qt src/widgets/kernel/qapplication.cpp:2262-2311.
        -- Redirected popup/grab input precedes native-window dispatch; equal
        -- layers use float zindex then registration order, never table order.
        if route_pointer(kind, pos, event[2], event[3] or "") then return end
        fallback(lhs, previous)
      end, { nowait = true, silent = true, desc = "yana-ui: pointer " .. kind })
    end
  end
end

---Acquire shared native mouse intake for an owner. Invalid owners/handlers
---raise an assertion. Reacquiring replaces its handler/priority; the first
---owner installs mouse mappings. Higher popup/grab layer, float zindex and
---then later registration win delivery order; a result other than false
---consumes input. A provided priority must be callable when intake runs.
---@param owner any Non-nil owner identity.
---@param handler fun(kind: string, pos: table): any Native mouse handler.
---@param label? string [default: nil] Compatibility argument; currently unused.
---@param priority? fun(): integer, integer [default: nil] Return layer and zindex; a nil callback selects zero for both.
---@return any owner # The supplied owner identity.
function M.acquire(owner, handler, label, priority)
  assert(owner ~= nil and type(handler) == "function", "input requires an owner and handler")
  if owners[owner] then owners[owner], owner_priority[owner] = handler, priority; return owner end
  if count == 0 then install_mouse(label) end
  owner_serial = owner_serial + 1
  owners[owner], owner_order[owner], owner_priority[owner], count = handler, owner_serial, priority, count + 1
  return owner
end

---Release this owner's mappings and shared mouse acquisition, if present.
---The final release restores still-owned global options/mappings. Repeated
---release is allowed; native restoration errors propagate.
---@param owner any Owner identity supplied to map() or acquire().
---@return nil result # No values are returned.
function M.release(owner)
  release_maps(owner)
  right_release_owners[owner] = nil
  if not owners[owner] then return end
  owners[owner], owner_order[owner], owner_priority[owner], count = nil, nil, nil, count - 1
  if count > 0 then return end
  release_maps(global_owner)
  for name, previous in pairs(native) do
    if vim.o[name] == installed[name] then vim.o[name] = previous end
  end
  native, installed = {}, {}
end

local function resolve_hit(win, screen_row, screen_col, resolver)
  assert(type(resolver) == "function", "yana_ui.input resolver must be a function")
  local cell = geometry.cell(win, screen_row, screen_col)
  if not cell then return nil end
  local target = resolver(cell)
  if target == nil then return nil end
  return { target = target, cell = cell }
end

--- Resolve a screen coordinate through the caller's plugin-owned resolver.
---Convert a native screen position and ask your resolver for a target.
---A missing native cell or nil resolver result returns nil. Invalid resolver
---values raise an assertion; native geometry errors propagate.
---@param win integer Native window handle.
---@param screen_row integer One-based screen row.
---@param screen_col integer One-based screen text-cell column.
---@param resolver fun(cell: table): any Caller-owned cell-to-target lookup.
---@return {target: any, cell: table}|nil hit # Target and native cell, or nil when unresolved.
function M.resolve(win, screen_row, screen_col, resolver)
  return resolve_hit(win, screen_row, screen_col, resolver)
end

local function drive(kind, win, screen_row, screen_col, resolver, handler)
  local hit = resolve_hit(win, screen_row, screen_col, resolver)
  if not hit then return nil end
  if handler then return handler(hit.target, hit.cell) end
  return hit.target
end

--- Resolve and dispatch a hover gesture through a caller-owned handler.
---Resolve a hover position and call handler(target, cell) when supplied.
---Without a handler, return the resolved target; no resolved cell/target
---returns nil. Invalid resolvers raise an assertion; callback errors propagate.
---@param win integer Native window handle.
---@param screen_row integer One-based screen row.
---@param screen_col integer One-based screen text-cell column.
---@param resolver fun(cell: table): any Caller-owned cell-to-target lookup.
---@param handler? fun(target: any, cell: table): any [default: nil] Optional resolved-target callback.
---@return any result # First handler return value, target, or nil when unresolved.
---@return any ... # Additional handler return values, if any.
function M.hover(win, screen_row, screen_col, resolver, handler)
  return drive("hover", win, screen_row, screen_col, resolver, handler)
end

--- Resolve and dispatch a press gesture through a caller-owned handler.
---Resolve a press position and call handler(target, cell) when supplied.
---Without a handler, return the resolved target; no resolved cell/target
---returns nil. Invalid resolvers raise an assertion; callback errors propagate.
---@param win integer Native window handle.
---@param screen_row integer One-based screen row.
---@param screen_col integer One-based screen text-cell column.
---@param resolver fun(cell: table): any Caller-owned cell-to-target lookup.
---@param handler? fun(target: any, cell: table): any [default: nil] Optional resolved-target callback.
---@return any result # First handler return value, target, or nil when unresolved.
---@return any ... # Additional handler return values, if any.
function M.press(win, screen_row, screen_col, resolver, handler)
  return drive("press", win, screen_row, screen_col, resolver, handler)
end

-- WIDGETS E: opt-in dispatch shares the legacy native intake and map lifetime.
local YObject = require("yana_ui.object")
local YWidget = require("yana_ui.widget")
local YFocus = require("yana_ui.focus")
local YPaintWriter = require("yana_ui.paint_writer")
---@class YEventDispatcherOptions
---@field parent YObject [default: required] Live owner; destruction releases this dispatcher's mappings and popup state.
---@field root YWidget [default: required] Live root for hit testing and default tab traversal.
---@field focus YFocus [default: required] Live focus manager; register root's target before native pointer delivery.
---@field writer YPaintWriter [default: required] Live canvas writer; flushed frames reconcile stationary hover.
---@field current_target fun():integer,integer,integer [default: required] Return current native win, buf and positive generation.
---@field keys? string[] [default: nil] Unique nonempty key names; nil selects Tab, S-Tab, Space, CR, Esc, Up, Down, Home and End.
--
---@class YEventDispatcher : YObject
---@doc brief Route canvas input to virtual controls while retaining native fallback.
---@doc qt QApplication event delivery. Neovim supplies keymaps, mouse positions and native windows. Direct dispatch() never replays ignored input; installed wrappers invoke the previous mapping or native key once when ignored.
---@doc inherits |YObject|; inherited properties, methods and destroyed signal retain |YObject| semantics. There are no additional properties or signals. The exported module also provides the compatibility map/acquire/release/resolve/hover/press functions below.
---@doc errors Invalid owners, widgets, event kinds/scalars, key arrays or mapping identities raise assertions or Lua/Neovim errors. Coordinates are zero-based canvas text cells. Native intake rechecks root, focus, writer and target generation. Event callback errors propagate. Construction acquires shared global mouse options and mappings; destroying the last owner restores only values and mappings still owned by the toolkit.
---@doc destroyed bind_keys,bind_context,push_popup,pop_popup
---@doc exception dispatch() returns false without a reason if this dispatcher or its root is dead. unbind_keys() remains usable after destruction. Popup opening may propagate a focus stale refusal. Private grab/hover helpers are not public methods.
---@doc context lua/yana_ui/input.lua|YEventDispatcher
---@doc setup Copy the Lua comments between the DOCS markers, remove their leading --, and run them in Neovim with yana-ui on runtimepath. You borrow the current window and buffer, create a visible root and register its target; owner destruction restores owned mappings without closing borrowed resources.
---@doc example local ui = require("yana_ui")
---@doc example local owner, win, buf = ui.YObject.new(), vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
---@doc example local target = function() return win, buf, 1 end
---@doc example local root = ui.YWidget.new({ parent = owner,
---@doc example   event = function(_, kind) print(kind); return true end })
---@doc example local focus = ui.YFocus.new({ parent = owner, current_target = target })
---@doc example local writer = ui.YPaintWriter.new({ parent = owner, win = win, buf = buf,
---@doc example   generation = 1, current_target = target })
---@doc example local layout = ui.YBoxLayout.new({ parent = owner })
---@doc example layout:add_widget(root); root:show(); layout:activate(0, 0, 8, 1, 1)
---@doc example focus:register(root, win, buf, 1)
---@doc example local dispatcher = ui.YEventDispatcher.new({ parent = owner, root = root,
---@doc example   focus = focus, writer = writer, current_target = target })
---@doc example dispatcher:dispatch("press", 0, 0, 1, "", 0)
---@doc example owner:destroy()
---@doc see |YWidget|, |YFocus|, |YPaintWriter|, |YTestInput|.
local YEventDispatcher = setmetatable({}, { __index = YObject })
YEventDispatcher.__index = YEventDispatcher
local next_binding = 0
local default_keys = { "<Tab>", "<S-Tab>", "<Space>", "<CR>", "<Esc>", "<Up>", "<Down>", "<Home>", "<End>" }
local function contains(widget, row, col)
  local r, c, w, h = widget:rect()
  return row >= r and col >= c and row < r + h and col < c + w
end
local function live(widget)
  return widget and not widget:is_destroyed() and widget:is_visible() and widget:is_enabled()
end
local function hit(widget, row, col, win)
  if not live(widget) then return nil end
  if widget.native_target and widget:native_target() ~= win then return nil end
  local wr, wc, width, height = widget:rect()
  if row < wr or col < wc or row >= wr + height or col >= wc + width then return nil end
  local child = widget._child_tail
  while child do
    if YWidget.is_instance(child) then
      local found = hit(child, row, col, win)
      if found then return found end
    end
    child = child._previous_sibling
  end
  return widget
end
local function bubble(widget, kind, row, col, button, key, mods, pos)
  while widget and YWidget.is_instance(widget) do
    if not widget:is_destroyed() and widget:event(kind, row, col, button, key, mods, pos) == true then return true end
    widget = widget:parent()
  end
  return false
end
local function popup(self)
  local top = self._popups[#self._popups]
  while top and not live(top.widget) do
    self._focus:pop_popup(top.focus_token)
    self._popups[#self._popups] = nil
    top = self._popups[#self._popups]
  end
  return top and top.widget
end
local function event_integer(value)
  assert(type(value) == "number" and value == math.floor(value), "invalid event scalar")
end
local function hover_path(widget)
  local path = {}
  while widget and YWidget.is_instance(widget) do
    path[#path + 1] = widget; widget = widget:parent()
  end
  return path
end
local function pointer_hit(self, row, col)
  -- FIX-5: vimfn.txt:3855-3881: native window identity already accounts for
  -- a focusable float covering this canvas, including native zindex stacking.
  local win = self._target()
  if self._pointer_winid and self._pointer_winid ~= win then return nil end
  return hit(self._root, row, col, win)
end
local function native_target(self)
  if self:is_destroyed() or self._writer:is_destroyed() then return false end
  local win, buf, generation = self._target()
  if win ~= self._writer._win or buf ~= self._writer._buf or generation ~= self._writer._generation
    or not self._focus:_matches(self._root, win, buf, generation) then return false end
  return win, buf, generation
end
function YEventDispatcher:_reconcile_hover()
  if self:is_destroyed() then return end
  if self._grab and not live(self._grab) then self:_cancel_grab(self._grab);return end
  if not self._pointer_row or self._crossing then return end
  local row, col = self._pointer_row, self._pointer_col
  local selected = popup(self) or (live(self._grab) and self._grab) or pointer_hit(self, row, col)
  if self._tooltip then
    if self._tooltip_blocked then self._tooltip:cancel()
    elseif self._tooltip:consider(selected,self._pointer_position) == "generation" then self._tooltip_blocked = true end
  end
  local before, after = self._hover_path or {}, hover_path(selected)
  local left, right = #before, #after
  -- Qt src/widgets/kernel/qapplication.cpp:2038-2124: the shared ancestor
  -- remains entered; exits go inward-to-outward, entries outward-to-inward.
  while left > 0 and right > 0 and before[left] == after[right] do left, right = left - 1, right - 1 end
  if left == 0 and right == 0 then self._hover = selected; return end
  self._crossing = true
  for _, binding in ipairs(self._hover_connections or {}) do
    if binding.effective then YWidget._observe_effective(binding.widget,self,nil)
    else binding.widget:disconnect(binding.token)end
  end
  self._hover, self._hover_path, self._hover_connections = selected, after, {}
  for _, widget in ipairs(after) do
    YWidget._observe_effective(widget,self,function(dispatcher)dispatcher:_reconcile_hover()end)
    self._hover_connections[#self._hover_connections+1]={widget=widget,effective=true}
    for _, signal in ipairs({ "destroyed" }) do
      local token = widget:connect(signal, self, function(dispatcher) dispatcher:_reconcile_hover() end)
      if token then self._hover_connections[#self._hover_connections + 1] = { widget = widget, token = token } end
    end
  end
  for i = 1, left do
    local widget = before[i]
    if not widget:is_destroyed() then
      YWidget._pointer(widget, false, widget:is_pressed())
      widget:event("leave", row, col, 0, "", 0)
    end
  end
  for i = right, 1, -1 do
    local widget = after[i]
    if live(widget) then
      YWidget._pointer(widget, contains(widget, row, col), widget:is_pressed())
      widget:event("enter", row, col, 0, "", 0)
    end
  end
  self._crossing = false
  -- Event callbacks may hide/destroy/reparent the prospective target.
  if not live(selected) or selected ~= (popup(self) or (live(self._grab) and self._grab) or pointer_hit(self, row, col)) then
    self:_reconcile_hover()
  end
end
---Send a scalar event to the top live popup, then the applicable pointer grab,
---focused key target or deepest eligible hit. Bubble to ancestors until one
---returns true. Move crossings leave inner-to-outer and enter outer-to-inner,
---excluding shared ancestors; release clears the grab before delivery and
---reconciles hover afterward. Invalid kinds/scalars/keys raise assertions.
---@param kind "move"|"press"|"release"|"right"|"wheel"|"key" Event kind.
---@param row integer Zero-based canvas row.
---@param col integer Zero-based canvas text-cell column.
---@param button integer Button code; 1 is left, 3 is right, 0 for key/wheel/move.
---@param key string Key name, wheel direction, or empty string for pointer events.
---@param mods integer Modifier value passed to the widget event callback.
---@param pos? table [default: nil] Native getmousepos() data; winid confines ordinary hit testing.
---@return boolean accepted # True if a widget accepts or a cancelled accepted gesture's tail is consumed; false if ignored or dispatcher/root dead.
function YEventDispatcher:dispatch(kind, row, col, button, key, mods, pos)
  assert(kind == "move" or kind == "press" or kind == "release" or kind == "right"
    or kind == "wheel" or kind == "key", "invalid event kind")
  event_integer(row); event_integer(col); event_integer(button); event_integer(mods)
  assert(type(key) == "string", "invalid event key")
  if self:is_destroyed() or self._root:is_destroyed() then return false end
  if (kind == "press" or kind == "right") and self._grab_intake then self:_cancel_grab(self._grab) end
  if self._grab and not live(self._grab) then self:_cancel_grab(self._grab) end
  if self._dismiss_guard and not self._dismiss_guard.active then self._dismiss_guard=nil end
  if self._dismiss_guard then
    local guard = self._dismiss_guard
    if kind == "press" or kind == "right" then self:_clear_dismiss_guard()
    elseif (kind == "release" or kind == "move") and button == guard.button then
      if kind == "release" then self:_clear_dismiss_guard() end
      return true
    end
  end
  if pos and kind ~= "key" then
    local win = native_target(self)
    if not win then return false end
    if not pos.content_resolved then
      pos.content = geometry.pointer(pos.winid, pos)
      pos.content_resolved = true
    end
    local cell = pos.content
    row, col = -1, -1
    if cell and cell.win == win then row, col = cell.line - 1, cell.display_col - 1 end
  end
  if kind ~= "key" then
    self._pointer_row, self._pointer_col, self._pointer_winid = row, col, pos and pos.winid or nil
    if pos then self._pointer_position = pos end
    if kind == "move" then self._tooltip_blocked = false
    elseif kind == "press" then
      self._tooltip_blocked = true
      self._tooltip:cancel()
    end
  end
  local selected = popup(self)
  if not selected then
    if kind == "key" then selected = self._focus:focus_widget()
    elseif (kind == "release" or kind == "move") and self._grab then selected = self._grab
    else selected = pointer_hit(self, row, col) end
  end
  if kind == "move" then
    if self._grab then
      local inside = contains(self._grab, row, col) and (not pos or pos.winid == self._target())
      YWidget._pointer(self._grab, inside, inside)
    end
    self:_reconcile_hover()
  elseif kind == "press" and selected and button == 1 then
    self._grab = selected
    self:_watch_grab(selected)
    YWidget._pointer(selected, selected:under_mouse(), true)
  elseif kind == "release" and button == 1 then
    if self._grab then YWidget._pointer(self._grab, self._grab:under_mouse(), false) end
    self._grab = nil
    self:_clear_grab_watch()
    self:_clear_grab_intake()
  end
  local accepted = selected ~= nil and bubble(selected, kind, row, col, button, key, mods, pos) or false
  if kind == "press" and button == 1 and accepted and live(self._grab) and not popup(self) then
    self:_own_grab_intake()
  elseif kind == "press" and button == 1 and accepted and not live(self._grab) and not popup(self) then
    -- A callback can cancel before native tail mappings have been installed.
    if self._grab then self:_cancel_grab(self._grab)end
    self:_swallow_gesture(1)
  end
  -- Qt src/widgets/kernel/qapplication.cpp:2364-2376: release delivery may
  -- delete its receiver; resolve the actual target after the grab and callback.
  if kind == "release" then self:_reconcile_hover() end
  return accepted
end
function YEventDispatcher:_widget_at(row, col)
  return pointer_hit(self, row, col)
end
local function finish_guard(guard)
  if not guard or not guard.active then return end
  guard.active = false
  local dispatcher = guard.dispatcher
  if dispatcher and dispatcher._dismiss_guard == guard then dispatcher._dismiss_guard = nil end
  guard.dispatcher = nil
  if guard.focus_lost then vim.api.nvim_del_autocmd(guard.focus_lost) end
  release_pointer_tail(guard)
end
local function detach_guard(guard)
  if not guard then return end
  local dispatcher = guard.dispatcher
  if dispatcher and dispatcher._dismiss_guard == guard then dispatcher._dismiss_guard = nil end
  guard.dispatcher = nil
end
local function passivate_guard(guard)
  if not guard.active or guard.passive then return end
  guard.passive=true
  guard.dispatcher=nil
  release_escape_maps(guard)
end
local function new_guard(dispatcher,button,passive)
  local guard = {active=true,button=button,dispatcher=dispatcher}
  if dispatcher then dispatcher._dismiss_guard = guard end
  right_release_owners[guard] = true
  local function pointer(kind,_,event_button)
    if not guard.active then return false end
    if kind == 'press' or kind == 'right' then finish_guard(guard);return false end
    if (kind == 'release' or kind == 'move') and event_button == guard.button then
      if kind == 'release' then finish_guard(guard) end
      return true
    end
    return false
  end
  M.acquire(guard,pointer,nil,function()return 3,0 end)
  local function escape()
    if not guard.active then return end
    local owner=guard.dispatcher
    if owner and not owner:is_destroyed() and owner._dismiss_guard==guard and popup(owner) then
      local ok,err=pcall(owner.dispatch,owner,'key',0,0,0,'<Esc>',0)
      local clean,why=pcall(function()
        if guard.active and (not guard.dispatcher or
          (guard.dispatcher==owner and owner._dismiss_guard==guard and not popup(owner)))then passivate_guard(guard)end
      end)
      if not ok then error(err,0)end
      if not clean then error(why,0)end
    else passivate_guard(guard) end
  end
  map_pointer_tail(guard,button,pointer,not passive and escape or nil)
  guard.focus_lost=vim.api.nvim_create_autocmd('FocusLost',{callback=function()finish_guard(guard)end})
  if passive then passivate_guard(guard)end
  return guard
end
function YEventDispatcher:_clear_dismiss_guard()
  local guard=self._dismiss_guard;self._dismiss_guard=nil
  finish_guard(guard)
end
function YEventDispatcher:_clear_grab_intake()
  local owner = self._grab_intake
  self._grab_intake = nil
  release_pointer_tail(owner)
end
function YEventDispatcher:_own_grab_intake()
  self:_clear_grab_intake()
  local owner = {}
  self._grab_intake = owner
  map_pointer_tail(owner, 1, function(kind, pos, button, key)
    if self._grab_intake ~= owner then return false end
    if kind == "press" or kind == "right" then self:_cancel_grab(self._grab); return false end
    return self:dispatch(kind, 0, 0, button, key, 0, pos)
  end,function()
    local widget=self._grab
    if self._grab_intake~=owner or not widget then return end
    owner.escape_cancelled=true
    local ok,err=pcall(function()if live(widget) then widget:event('key',0,0,0,'<Esc>',0)end end)
    local clean,why=pcall(function()
      if self._grab_intake==owner and self._grab==widget then self:_cancel_grab(widget)end
    end)
    if not ok then error(err,0)end
    if not clean then error(why,0)end
  end)
end
function YEventDispatcher:_swallow_gesture(button,passive)
  self:_clear_dismiss_guard()
  if self:is_destroyed() then return end
  new_guard(self,button,passive)
end
function YEventDispatcher:_clear_grab_watch()
  local watch=self._grab_watch;self._grab_watch=nil
  if watch then
    YWidget._observe_effective(watch.widget,watch.owner,nil)
    watch.owner:destroy()
  end
end
function YEventDispatcher:_watch_grab(widget)
  self:_clear_grab_watch()
  local owner=YObject.new{parent=self}
  self._grab_watch={widget=widget,owner=owner}
  -- W-EFFECTS: presses need eligibility delivery before any move/paint occurs.
  YWidget._observe_effective(widget,owner,function(_,reason)
    if self._grab==widget and (reason=='parent' or not live(widget))then self:_cancel_grab(widget)end
  end)
end
function YEventDispatcher:_cancel_grab(widget)
  local grabbed = self._grab == widget
  if grabbed then
    local intake = self._grab_intake
    self._grab = nil
    self:_clear_grab_watch()
    self:_clear_grab_intake()
    if intake then self:_swallow_gesture(1,intake.escape_cancelled) end
  end
  YWidget._pointer(widget, widget:under_mouse(), false)
  if grabbed and not widget:is_destroyed() then widget:_grab_cancelled() end
  if grabbed and not self:is_destroyed() then self:_reconcile_hover() end
end
function YEventDispatcher:_button_state(widget, pressed)
  YWidget._pointer(widget, widget:under_mouse(), pressed)
end
function YEventDispatcher:_arm_button(widget)
  self._grab = widget
  self:_watch_grab(widget)
  self:_button_state(widget, true)
end
local function key_names(keys)
  if keys == nil then keys = default_keys end
  local seen = {}
  assert(type(keys) == "table", "invalid key names")
  local copied = {}
  for i, lhs in ipairs(keys) do
    assert(type(lhs) == "string" and lhs ~= "" and not seen[lhs], "invalid key name")
    copied[i], seen[lhs] = lhs, true
  end
  for index in pairs(keys) do assert(type(index) == "number" and index >= 1 and index <= #copied
    and index == math.floor(index), "keys must be an array") end
  return copied
end
---Install buffer-local normal-mode key wrappers for a captured target triple.
---Invalid buffers, callbacks, identities or key arrays raise assertions. A
---wrapper rechecks the active window/buffer/generation, tries virtual input,
---then unaccepted Tab traversal, then predecessor/native fallback once.
---@param buf integer Valid buffer displayed by the captured target window.
---@param current_target? fun():integer,integer,integer [default: nil] Override callback; nil uses the constructor callback.
---@param keys? string[] [default: nil] Unique nonempty key names; nil uses the constructor key list.
---@return integer|false token # Positive binding token, or false if dispatcher dead.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YEventDispatcher:bind_keys(buf, current_target, keys)
  assert(type(buf) == "number" and vim.api.nvim_buf_is_valid(buf), "invalid key buffer")
  assert(current_target == nil or type(current_target) == "function", "invalid key target")
  if self:is_destroyed() then return false, "destroyed" end
  keys = key_names(keys or self._keys)
  local target = current_target or self._target
  local win, named_buf, generation = target()
  assert(named_buf == buf and type(win) == "number" and vim.api.nvim_win_is_valid(win)
    and vim.api.nvim_win_get_buf(win) == buf and type(generation) == "number"
    and generation > 0 and generation == math.floor(generation), "invalid key target identity")
  next_binding = next_binding + 1
  local binding = { token = next_binding, active = true }
  self._bindings[binding.token] = binding
  for _, lhs in ipairs(keys) do
    local previous = snapshot("n", lhs, buf) or snapshot("n", lhs)
    M.map(binding, "n", lhs, function()
      local w, b, g = target()
      local valid = binding.active and not self:is_destroyed() and self._bindings[binding.token] == binding
        and w == win and b == buf and g == generation and vim.api.nvim_win_is_valid(win)
        and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_get_buf(win) == buf
        and vim.api.nvim_get_current_win() == win and vim.api.nvim_get_current_buf() == buf
      local accepted = valid and self:dispatch("key", 0, 0, 0, lhs, 0)
      if valid and not accepted and (lhs == "<Tab>" or lhs == "<S-Tab>") then
        accepted = self._focus:focus_next(self._root, lhs == "<S-Tab>")
      end
      if not accepted then fallback(lhs, previous) end
    end, { buffer = buf, silent = true, nowait = true, desc = "yana-ui: key " .. lhs })
  end
  return binding.token
end
---Bind context requests to a borrowed source buffer. The callback receives a
---checked keyboard cursor or right-press row without moving the source cursor.
---@param buf integer Valid borrowed source buffer.
---@param current_target fun():integer,integer,string|integer Source window, buffer and stable generation.
---@param on_context fun(invocation:table):boolean Open the context menu; false leaves input unaccepted.
---@param opts? table [default: nil] Optional normal-mode key; default "m".
---@return integer|false token # Binding token, or false when destroyed.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YEventDispatcher:bind_context(buf, current_target, on_context, opts)
  assert(type(buf)=="number" and vim.api.nvim_buf_is_valid(buf),"invalid context buffer")
  assert(type(current_target)=="function" and type(on_context)=="function","invalid context callbacks")
  local key = opts and opts.key or "m"
  assert(type(key)=="string" and key~="","invalid context key")
  if self:is_destroyed() then return false,"destroyed" end
  next_binding = next_binding+1
  local binding = {token=next_binding,active=true,context=true,dispatcher=self,
    buf=buf,target=current_target,callback=on_context}
  self._bindings[binding.token] = binding
  local previous = snapshot("n",key,buf) or snapshot("n",key)
  M.map(binding,"n",key,function()
    if popup(self) or self._grab then
      if not self:dispatch("key",0,0,0,key,0) then fallback(key,previous) end
      return
    end
    local invocation = context_anchor.capture(binding)
    if not invocation or on_context(invocation)==false then fallback(key,previous) end
  end,{buffer=buf,silent=true,nowait=true,desc="yana-ui: context menu"})
  binding.autocmd = vim.api.nvim_create_autocmd("BufWipeout",{buffer=buf,once=true,
    callback=function() binding.autocmd=nil; self:unbind_keys(binding.token) end})
  return binding.token
end
function YEventDispatcher:_context_invocation(pos)
  local tokens = {}
  for token,binding in pairs(self._bindings) do if binding.context then tokens[#tokens+1]=token end end
  table.sort(tokens,function(a,b) return a>b end)
  for _,token in ipairs(tokens) do
    local binding = self._bindings[token]
    local invocation = context_anchor.capture(binding,pos)
    if invocation then return invocation,binding end
  end
end
---Release one binding token, restoring only mappings still owned by it.
---Invalid positive-integer tokens raise an assertion; unknown or already
---released tokens change nothing, including after destruction.
---@param token integer Positive token returned by bind_keys() or bind_context().
---@return boolean removed # True when removed; false when absent.
function YEventDispatcher:unbind_keys(token)
  assert(type(token) == "number" and token > 0 and token == math.floor(token), "invalid key token")
  local binding = self._bindings[token]
  if not binding then return false end
  binding.active, self._bindings[token] = false, nil
  if binding.autocmd then vim.api.nvim_del_autocmd(binding.autocmd) end
  release_maps(binding)
  return true
end
---Focus a popup through YFocus, push its routing entry, then reconcile hover.
---Invalid widgets raise an assertion; a refused focus does not push an entry.
---@param widget YWidget Live popup eligible for registered focus.
---@return integer|false token # Positive dispatcher popup token, or false on refusal.
---@return "destroyed"|"stale"|nil reason # Dispatcher/widget destruction or delegated focus refusal, or nil.
function YEventDispatcher:push_popup(widget)
  assert(YWidget.is_instance(widget), "popup must be a YWidget")
  if self:is_destroyed() or widget:is_destroyed() then return false, "destroyed" end
  self._tooltip_blocked = true
  self._tooltip:cancel()
  local token, reason = self._focus:push_popup(widget)
  if not token then return token, reason end
  self._popup_serial = self._popup_serial + 1
  self._popups[#self._popups + 1] = { token = self._popup_serial, widget = widget, focus_token = token }
  self:_reconcile_hover()
  return self._popup_serial
end
---Pop only the top routing token, ask YFocus to restore prior focus and
---reconcile hover. Invalid positive-integer tokens raise an assertion.
---@param token integer Dispatcher token returned by push_popup().
---@return boolean popped # True when removed; false if absent, out of order or dead.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YEventDispatcher:pop_popup(token)
  assert(type(token) == "number" and token > 0 and token == math.floor(token), "invalid popup token")
  if self:is_destroyed() then return false, "destroyed" end
  local top = self._popups[#self._popups]
  if not top or top.token ~= token then return false end
  self._popups[#self._popups] = nil
  self._focus:pop_popup(top.focus_token)
  self:_reconcile_hover()
  return true
end
local function native_pointer(self, kind, pos, button, key)
  local win = native_target(self)
  if not win then self._tooltip:cancel(); return false end
  local cell = pos.content
  local redirected = popup(self) or self._grab
  if not redirected and kind == "right" then
    local invocation,binding = self:_context_invocation(pos)
    if invocation and binding.callback(invocation) ~= false then
      self:_swallow_gesture(3)
      return true
    end
  end
  if not redirected and (pos.winid ~= win or not cell) then
    if kind == "move" then self:dispatch(kind, -1, -1, button or 0, key or "", 0, pos) end
    return false
  end
  return self:dispatch(kind, 0, 0, button or 1, key or "", 0, pos)
end
---Construct an opt-in dispatcher, acquire native pointer input and bind keys
---in the current target buffer. Invalid options, dead owners or malformed keys
---raise assertions. Register the root with YFocus for native mouse delivery;
---direct dispatch() uses the virtual tree without that native intake check.
---@param opts YEventDispatcherOptions Required owner, root, focus, writer and target callback.
---@return YEventDispatcher dispatcher # New input dispatcher.
function M.new(opts)
  assert(type(opts) == "table" and YObject.is_instance(opts.parent), "YEventDispatcher parent required")
  assert(YWidget.is_instance(opts.root) and not opts.root:is_destroyed()
    and YFocus.is_instance(opts.focus) and not opts.focus:is_destroyed()
    and YPaintWriter.is_instance(opts.writer) and not opts.writer:is_destroyed()
    and type(opts.current_target) == "function", "invalid event owners")
  local copied = key_names(opts.keys)
  local self = setmetatable(YObject.new(opts), YEventDispatcher)
  self._root, self._focus, self._writer, self._target = opts.root, opts.focus, opts.writer, opts.current_target
  self._popups, self._popup_serial = {}, 0
  self._keys, self._bindings = copied, {}
  right_release_owners[self] = true
  self._tooltip = require("yana_ui.tooltip").new({parent=self,current_target=self._target,
    valid_target=function() return native_target(self) end})
  -- A completed native canvas commit observes final membership/geometry,
  -- including newly created controls beneath a stationary pointer.
  self._writer:connect("flushed", self, function(dispatcher) dispatcher:_reconcile_hover() end)
  M.acquire(self, function(kind, pos, button, key) return native_pointer(self, kind, pos, button, key) end, nil, function()
    local top = popup(self)
    local win = top and type(top.native_target) == "function" and top:native_target() or self._target()
    local zindex = vim.api.nvim_win_is_valid(win) and (vim.api.nvim_win_get_config(win).zindex or 0) or 0
    return top and 2 or (live(self._grab) and 1 or 0), zindex
  end)
  local _, buf = opts.current_target()
  self:bind_keys(buf)
  return self
end
function YEventDispatcher:_dispose()
  self:_clear_grab_watch()
  local guard=self._dismiss_guard;self._dismiss_guard=nil;detach_guard(guard)
  if self._grab_intake then new_guard(nil,1,self._grab_intake.escape_cancelled) end
  self:_clear_grab_intake()
  for token in pairs(self._bindings) do self:unbind_keys(token) end
  for _, widget in ipairs(self._hover_path or {}) do YWidget._pointer(widget, false, widget:is_pressed()) end
  if self._grab then YWidget._pointer(self._grab, self._grab:under_mouse(), false) end
  while #self._popups > 0 do
    self._focus:pop_popup(self._popups[#self._popups].focus_token)
    self._popups[#self._popups] = nil
  end
  M.release(self)
  for _,binding in ipairs(self._hover_connections or {})do
    if binding.effective then YWidget._observe_effective(binding.widget,self,nil)end
  end
  self._hover, self._grab = nil, nil
end

return M
-- DOCS: YEventDispatcher example start
-- local ui = require("yana_ui")
-- local owner, win, buf = ui.YObject.new(), vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
-- local target = function() return win, buf, 1 end
-- local root = ui.YWidget.new({ parent = owner,
--   event = function(_, kind) print(kind); return true end })
-- local focus = ui.YFocus.new({ parent = owner, current_target = target })
-- local writer = ui.YPaintWriter.new({ parent = owner, win = win, buf = buf,
--   generation = 1, current_target = target })
-- local layout = ui.YBoxLayout.new({ parent = owner })
-- layout:add_widget(root); root:show(); layout:activate(0, 0, 8, 1, 1)
-- focus:register(root, win, buf, 1)
-- local dispatcher = ui.YEventDispatcher.new({ parent = owner, root = root,
--   focus = focus, writer = writer, current_target = target })
-- dispatcher:dispatch("press", 0, 0, 1, "", 0)
-- owner:destroy()
-- DOCS: YEventDispatcher example end
