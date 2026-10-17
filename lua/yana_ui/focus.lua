-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- WIDGETS F: registration identity gates focus on actual native targets.
local YObject = require("yana_ui.object")
local YWidget = require("yana_ui.widget")
local metrics = require("yana_ui.text_metrics")
---@class YFocusOptions
---@field parent YObject [default: required] Live session owner; only one live YFocus may belong to it.
---@field current_target? fun(root:YWidget):integer,integer,integer [default: nil] Return the root's current win, buf and generation; nil relies on registered native validity.
--
---@class YFocus : YObject
---@doc brief Track a virtual focus target backed by a registered native window.
---@doc qt QApplication focus. Native current-window and buffer state remain authoritative. You register virtual roots and target generations; no Tab mapping is installed by YFocus itself.
---@doc inherits |YObject|; inherited properties, methods and destroyed signal retain |YObject| semantics.
---@doc property focus_widget|focus_widget()|set_focus(widget, reason), focus_next(root, backward)|focus_changed|nil
---@signal focus_changed(previous: YWidget|nil, current: YWidget|nil) | Emitted after the logical target changes and live old/new widgets request repaint, before set_focus() changes the native window. Reentrant callbacks may change or destroy the proposed target; unchanged targets emit nothing.
---@doc errors Invalid widget identities, positive native identities or callback types raise assertions. Registered windows must display the registered buffer. Eligibility requires a live, visible, enabled widget with a current registered root. Callback and native API errors propagate; borrowed windows and buffers are never closed.
---@doc destroyed register,release,set_focus,set_tab_order,focus_next,push_popup,pop_popup
---@doc exception register(), set_focus(), set_tab_order(), focus_next() and push_popup() also refuse destroyed widget arguments. set_focus() and delegated focus_next()/push_popup() may return stale when registration or generation no longer matches. focus_widget() returns nil after destruction and may reconcile focus and emit focus_changed while live.
---@doc context lua/yana_ui/focus.lua|YFocus
---@doc setup Copy the Lua comments between the DOCS markers, remove their leading --, and run them in Neovim with yana-ui on runtimepath. You borrow the current window and buffer, register one visible root and release the example owner afterward.
---@doc example local ui = require("yana_ui")
---@doc example local owner = ui.YObject.new()
---@doc example local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
---@doc example local target = function() return win, buf, 1 end
---@doc example local root = ui.YWidget.new({ parent = owner })
---@doc example local focus = ui.YFocus.new({ parent = owner, current_target = target })
---@doc example root:show(); focus:register(root, win, buf, 1)
---@doc example focus:set_focus(root, "example")
---@doc example print(focus:focus_widget() == root)
---@doc example owner:destroy()
---@doc see |YWidget|, |YEventDispatcher|, |YStyle|.
local YFocus = setmetatable({}, { __index = YObject })
YFocus.__index = YFocus
local sessions = setmetatable({}, { __mode = "k" })
---Recognize exactly the YFocus metatable, including destroyed focus objects.
---@param value any Value to inspect.
---@return boolean instance # True for a YFocus identity.
function YFocus.is_instance(value) return YObject.is_instance(value) and getmetatable(value) == YFocus end
local function integer(n)
  assert(type(n) == "number" and n > 0 and n < math.huge and n == math.floor(n), "invalid native identity")
end
local function root_for(self, widget)
  local cursor = widget
  while cursor do
    if self._roots[cursor] then return cursor, self._roots[cursor] end
    cursor = cursor:parent()
  end
end
local function current(self, root, record)
  if not record.valid or root:is_destroyed() or not vim.api.nvim_win_is_valid(record.win)
    or not vim.api.nvim_buf_is_valid(record.buf) or vim.api.nvim_win_get_buf(record.win) ~= record.buf then
    record.valid = false; return false
  end
  if self._target then
    local win, buf, generation = self._target(root)
    if win ~= record.win or buf ~= record.buf or generation ~= record.generation then return false end
  end
  return true
end
local function eligible(widget)
  return YWidget.is_instance(widget) and not widget:is_destroyed() and widget:is_visible() and widget:is_enabled()
end
local function changed(self, value)
  if self._focused == value then return false end
  local previous = self._focused
  self._focused = value
  if previous and not previous:is_destroyed() then previous:update() end
  if value then value:update() end
  self:emit("focus_changed", previous, value)
  return true
end
local function cursor_control(widget, row, col)
  if not eligible(widget) then return nil end
  local r,c,w,h = widget:rect()
  if row < r or row >= r+h or col < c or col >= c+w then return nil end
  local child = widget._child_tail
  while child do
    if YWidget.is_instance(child) then
      local found = cursor_control(child,row,col)
      if found then return found end
    end
    child = child._previous_sibling
  end
  return type(widget.click) == "function" and widget or nil
end
function YFocus:_sync_cursor()
  if self:is_destroyed() or self._placing_cursor then return end
  local win = vim.api.nvim_get_current_win()
  for root, record in pairs(self._roots) do
    if record.win == win and current(self,root,record) then
      local cursor = vim.api.nvim_win_get_cursor(win)
      local line = vim.api.nvim_buf_get_lines(record.buf,cursor[1]-1,cursor[1],false)[1] or ""
      local selected = cursor_control(root,cursor[1]-1,metrics.cell_at_byte(line,cursor[2])-1)
      if selected then changed(self,selected) end
      return
    end
  end
end
---Create the session's focus manager and native-target lifecycle observers.
---Invalid options, a non-live parent or a second live manager for that parent
---raise assertions. Destroying the owner removes these observers.
---@param opts YFocusOptions Required session owner and optional target callback.
---@return YFocus focus # Session focus manager.
function YFocus.new(opts)
  assert(type(opts) == "table" and YObject.is_instance(opts.parent), "YFocus parent required")
  assert(opts.current_target == nil or type(opts.current_target) == "function", "invalid target callback")
  assert(not sessions[opts.parent] or sessions[opts.parent]:is_destroyed(), "one live YFocus per session")
  local self = setmetatable(YObject.new(opts), YFocus)
  self._target, self._roots, self._orders, self._popups = opts.current_target, {}, {}, {}
  self._popup_serial = 0
  self._autocmd = vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter", "WinClosed", "BufWipeout", "CursorMoved" }, {
    callback = function(event)
      if self:is_destroyed() then return end
      for _, entry in ipairs(self._popups) do
        if (event.event == "BufWipeout" and event.buf == entry.opener.buf)
          or (event.event == "WinClosed" and tonumber(event.match) == entry.opener.win) then
          entry.opener.valid = false
        end
      end
      for root, record in pairs(self._roots) do current(self, root, record) end
      self:focus_widget()
      self:_sync_cursor()
    end,
  })
  sessions[opts.parent] = self
  return self
end
---Register or replace a root's native identity. Invalid roots, native handles,
---generations or window-buffer pairs raise assertions before the dead check.
---@param root YWidget Registered root for its widget subtree.
---@param win integer Positive valid window displaying buf.
---@param buf integer Positive valid buffer handle.
---@param generation integer Positive integer identifying the target lifetime.
---@return boolean registered # True after registration; false if manager or root is dead.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YFocus:register(root, win, buf, generation)
  assert(YWidget.is_instance(root), "root must be a YWidget")
  integer(win); integer(buf); integer(generation)
  assert(vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_win_get_buf(win) == buf, "invalid native registration")
  if self:is_destroyed() or root:is_destroyed() then return false, "destroyed" end
  self._roots[root] = { win = win, buf = buf, generation = generation, valid = true }
  return true
end
---Remove a root's registration and explicit tab order. Focus belonging to
---that root is cleared; native resources remain borrowed. Invalid roots raise
---an assertion; releasing an absent registration changes nothing.
---@param root YWidget Root to unregister.
---@return boolean released # True when removed; false if absent or manager dead.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YFocus:release(root)
  assert(YWidget.is_instance(root), "root must be a YWidget")
  if self:is_destroyed() then return false, "destroyed" end
  if not self._roots[root] then return false end
  local selected_root = self._focused and root_for(self, self._focused)
  self._roots[root], self._orders[root] = nil, nil
  if selected_root == root then changed(self, nil) end
  return true
end
---Reconcile the target against the current native window, registered identity
---and widget eligibility. An eligible registered root may become focused;
---otherwise focus is cleared. Reading this property can emit focus_changed.
---@return YWidget|nil widget # Eligible current widget, or nil when none or manager dead.
function YFocus:focus_widget()
  if self:is_destroyed() then return nil end
  local win = vim.api.nvim_get_current_win()
  if self._focused then
    local root, record = root_for(self, self._focused)
    if root and record.win == win and current(self, root, record) and eligible(self._focused) then return self._focused end
  end
  for root, record in pairs(self._roots) do
    if record.win == win and current(self, root, record) and eligible(root) then
      changed(self, root); return self._focused
    end
  end
  changed(self, nil)
  return nil
end
function YFocus:_matches(root, win, buf, generation)
  local record = self._roots[root]
  return not self:is_destroyed() and record ~= nil and current(self, root, record)
    and record.win == win and record.buf == buf and record.generation == generation
end
---Set an eligible logical target, then select its registered native window and cursor position.
---Recheck identity and eligibility after focus_changed callbacks; stale or dead
---targets are refused. Invalid widget or reason values raise assertions.
---@param widget YWidget Widget under a registered root.
---@param reason string Required reason label; accepted but not emitted or stored.
---@return boolean focused # True if focus can be applied, including an unchanged target; false on refusal.
---@return "destroyed"|"stale"|nil reason # Destruction or registration refusal, or nil.
function YFocus:set_focus(widget, reason)
  assert(YWidget.is_instance(widget), "focus target must be a YWidget")
  assert(type(reason) == "string", "focus reason required")
  if self:is_destroyed() or widget:is_destroyed() then return false, "destroyed" end
  local root, record = root_for(self, widget)
  if not root or not current(self, root, record) then return false, "stale" end
  if not eligible(widget) then return false end
  -- Set the logical target first: WinEnter observers must see that same target.
  changed(self, widget)
  if self:is_destroyed() or widget:is_destroyed() then return false, "destroyed" end
  if self._focused ~= widget or self._roots[root] ~= record or not current(self, root, record) then return false, "stale" end
  if not eligible(widget) then return false end
  self._placing_cursor = true
  if vim.api.nvim_get_current_win() ~= record.win then vim.api.nvim_set_current_win(record.win) end
  local row,col,width,height = widget:rect()
  if width > 0 and height > 0 and row < vim.api.nvim_buf_line_count(record.buf) then
    local line = vim.api.nvim_buf_get_lines(record.buf,row,row+1,false)[1]
    vim.api.nvim_win_set_cursor(record.win,{row+1,metrics.byte_at_display(line,col+1)})
  end
  self._placing_cursor = false
  return true
end
---Place after immediately following before in their root's explicit order.
---Invalid or identical widgets and widgets without a shared registered root
---raise assertions. Existing entries for after are moved rather than copied.
---@param before YWidget First tab target.
---@param after YWidget Following tab target under the same registered root.
---@return boolean stored # True after storing the order; false if manager or either widget is dead.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YFocus:set_tab_order(before, after)
  assert(YWidget.is_instance(before) and YWidget.is_instance(after) and before ~= after, "invalid tab order")
  if self:is_destroyed() or before:is_destroyed() or after:is_destroyed() then return false, "destroyed" end
  local root = root_for(self, before)
  assert(root and root_for(self, after) == root, "tab targets must share registered root")
  local order = self._orders[root] or {}
  local before_index
  for i = #order, 1, -1 do if order[i] == after then table.remove(order, i) end end
  for i, value in ipairs(order) do if value == before then before_index = i; break end end
  if not before_index then order[#order + 1] = before; before_index = #order end
  table.insert(order, before_index + 1, after)
  self._orders[root] = order
  return true
end
local function collect(root, order)
  if YWidget.is_instance(root) then order[#order + 1] = root end
  local child = root._child_head
  while child do collect(child, order); child = child._next_sibling end
end
---Cycle through eligible tab targets, wrapping in either direction. Without
---an explicit order, cache a root-first traversal of the ownership tree.
---Invalid roots or non-boolean backward values raise assertions.
---@param root YWidget Root whose tab order to traverse.
---@param backward boolean True for reverse traversal; false for forward traversal.
---@return boolean focused # Result of the first eligible set_focus(), or false if none or dead.
---@return "destroyed"|"stale"|nil reason # Direct or delegated focus refusal, or nil.
function YFocus:focus_next(root, backward)
  assert(YWidget.is_instance(root), "root must be a YWidget"); YObject.boolean(backward)
  if self:is_destroyed() or root:is_destroyed() then return false, "destroyed" end
  local order = self._orders[root]
  if not order then order = {}; collect(root, order); self._orders[root] = order end
  if #order == 0 then return false end
  local selected, start = self:focus_widget(), backward and 1 or 0
  for i, value in ipairs(order) do if value == selected then start = i; break end end
  local step = backward and -1 or 1
  for offset = 1, #order do
    local index = (start - 1 + offset * step) % #order + 1
    if eligible(order[index]) then return self:set_focus(order[index], "tab") end
  end
  return false
end
---Focus a popup and remember the prior widget and native opener for stack restoration.
---Invalid widget values raise an assertion; a refused set_focus() does not
---push a stack entry.
---@param widget YWidget Eligible popup under a registered root.
---@return integer|false token # Positive popup token, or false on focus refusal.
---@return "destroyed"|"stale"|nil reason # Direct or delegated focus refusal, or nil.
function YFocus:push_popup(widget)
  assert(YWidget.is_instance(widget), "popup must be a YWidget")
  if self:is_destroyed() or widget:is_destroyed() then return false, "destroyed" end
  local prior = self:focus_widget()
  local win = vim.api.nvim_get_current_win()
  local opener = { win = win, buf = vim.api.nvim_win_get_buf(win), cursor = vim.api.nvim_win_get_cursor(win), valid = true }
  if widget._popup_opener then
    prior, opener = nil, widget._popup_opener
    if not opener.eligible() then return false,"stale" end
  end
  local ok, reason = self:set_focus(widget, "popup")
  if not ok then return ok, reason end
  self._popup_serial = self._popup_serial + 1
  self._popups[#self._popups + 1] = { token = self._popup_serial, prior = prior, opener = opener }
  return self._popup_serial
end
---Pop only the current top token and restore an eligible prior widget or native opener.
---A true result means the stack entry was removed; restoration failure is not
---returned. Invalid positive-integer tokens raise an assertion.
---@param token integer Positive token returned by push_popup().
---@return boolean popped # True when the top was removed; false if absent, out of order or dead.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YFocus:pop_popup(token)
  integer(token)
  if self:is_destroyed() then return false, "destroyed" end
  local top = self._popups[#self._popups]
  if not top or top.token ~= token then return false end
  self._popups[#self._popups] = nil
  if eligible(top.prior) then self:set_focus(top.prior, "popup_restore")
  elseif top.prior == nil and top.opener.valid and vim.api.nvim_win_is_valid(top.opener.win)
    and (not top.opener.eligible or top.opener.eligible())
    and vim.api.nvim_buf_is_valid(top.opener.buf)
    and vim.api.nvim_win_get_buf(top.opener.win) == top.opener.buf
    and vim.api.nvim_win_get_tabpage(top.opener.win) == vim.api.nvim_get_current_tabpage() then
    vim.api.nvim_set_current_win(top.opener.win)
    vim.api.nvim_win_set_cursor(top.opener.win,top.opener.cursor)
    self:focus_widget()
  else self:focus_widget() end
  return true
end
function YFocus:_dispose()
  vim.api.nvim_del_autocmd(self._autocmd)
  self._focused, self._roots, self._orders, self._popups = nil, {}, {}, {}
  local owner = self:parent()
  if sessions[owner] == self then sessions[owner] = nil end
end
return YFocus
-- DOCS: YFocus example start
-- local ui = require("yana_ui")
-- local owner = ui.YObject.new()
-- local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
-- local target = function() return win, buf, 1 end
-- local root = ui.YWidget.new({ parent = owner })
-- local focus = ui.YFocus.new({ parent = owner, current_target = target })
-- root:show(); focus:register(root, win, buf, 1)
-- focus:set_focus(root, "example")
-- print(focus:focus_widget() == root)
-- owner:destroy()
-- DOCS: YFocus example end
