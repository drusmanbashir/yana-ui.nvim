-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-FileCopyrightText: 2021 The Qt Company Ltd
-- SPDX-FileCopyrightText: 2016 Intel Corporation
-- SPDX-FileCopyrightText: 2013 Olivier Goffart <ogoffart@woboq.com>
-- SPDX-License-Identifier: LGPL-3.0-only
-- Derived from Qt src/corelib/kernel/qobject.cpp:2200-2290 (qtbase v6.8.3).
-- Modified: Lua/Neovim adaptation by Usman Bashir; notice added 2026-10-08.
-- WIDGETS Stage2: connections and parent-owned lifetime have one owner.
---@class YObjectOptions
---@field parent? YObject [default: nil] Live owner; destroying it destroys this child.

---@class YObject
---@field id integer Monotonically allocated object identity; treat as read-only.
---@doc brief Parent-owned lifetime and ordered direct Lua signal delivery.
---@doc qt QObject. Connections call Lua functions synchronously, in connection order. There are no threads, queued connection modes or Qt event loop; delete_later() uses vim.schedule().
---@doc inherits none.
---@doc property id|id (read-only field)|none|none|new monotonically increasing integer
---@doc property parent|parent()|set_parent(parent)|none|option:parent
---@doc property destroyed|is_destroyed()|destroy(), delete_later()|destroyed|false
---@signal destroyed(object: YObject) | Emitted exactly once when destruction starts, before children and connections are removed. It is emitted even when signals are blocked; object:is_destroyed() is already true.
---@doc errors boolean() and block_signals() require booleans and identity() a nonempty string or finite integer; other values raise assertions, even after destruction. Other validation failures are listed with their methods.
---@doc destroyed set_parent,connect,emit,block_signals,delete_later,destroy
---@doc exception connect() also refuses a destroyed receiver. emit() allows the destroyed signal while destroy() is delivering it. Getters and is_instance() still work after destruction.
---@doc context examples/disable_button.lua|YObject
---@doc setup In that file, owner owns the root, button, action and input resources. This q-key callback destroys them, cancels the job and closes the Neovim resources.
---@doc example local function close()
---@doc example   if owner:is_destroyed() then return end
---@doc example   owner:destroy()
---@doc example   if job then job:kill(15); job = nil end
---@doc example   vim.api.nvim_del_augroup_by_id(group)
---@doc example   if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
---@doc example   if vim.api.nvim_buf_is_valid(canvas) then vim.api.nvim_buf_delete(canvas, { force = true }) end
---@doc example   if vim.api.nvim_buf_is_valid(document) then
---@doc example     for _, key in ipairs({ "t", "q" }) do vim.keymap.del("n", key, { buffer = document }) end
---@doc example   end
---@doc example end
---@doc see |YAction|, |yana-ui-explanation|.
local YObject = {}
YObject.__index = YObject
local identities = setmetatable({}, { __mode = "k" })
local next_id, next_token = 0, 0
local delivery_depth, deletion_queued = 0, false
local deletion_head, deletion_tail
local function drain_deletions()
  deletion_queued = false
  if delivery_depth > 0 then return end
  local ok, err = true, nil
  while deletion_head do
    local object = deletion_head
    deletion_head = object._delete_next
    if not deletion_head then deletion_tail = nil end
    object._delete_next, object._delete_pending = nil, false
    if not object._dead then
      local destroyed, reason = pcall(object.destroy, object)
      if not destroyed and ok then ok, err = false, reason end
    end
  end
  if not ok then error(err, 0) end
end
local function queue_deletions()
  if deletion_head and not deletion_queued then
    deletion_queued = true
    vim.schedule(drain_deletions)
  end
end

---Recognize identities allocated by YObject.new(), including subclasses and
---destroyed objects. A non-object value is allowed.
---@param value any Value to inspect.
---@return boolean instance # True for an allocated YObject identity.
function YObject.is_instance(value) return identities[value] == true end

---Validate a required boolean.
---@param value boolean Value to validate.
---@return boolean value # The same validated value.
function YObject.boolean(value)
  assert(type(value) == "boolean", "expected boolean")
  return value
end

-- R3: the one row/column/generation identity rule; item views, YTableSort and
-- YSortFilterProxyModel call it.
local function stable_identity(value)
  return (type(value) == "string" and value ~= "")
    or (type(value) == "number" and math.abs(value) < math.huge and value == math.floor(value))
end

---Validate a stable record identity: a nonempty string or a finite integer.
---Other values raise an assertion.
---@param value string|integer Value to validate.
---@return string|integer value # The same validated value.
function YObject.identity(value)
  assert(stable_identity(value), "invalid identity")
  return value
end

local function validate_parent(self, parent)
  if parent == nil then return end
  assert(YObject.is_instance(parent) and not parent:is_destroyed(), "parent must be a live YObject")
  local cursor = parent
  while cursor do
    assert(cursor ~= self, "YObject parent cycle")
    cursor = cursor._parent
  end
end

local function detach(self)
  local parent = self._parent
  if not parent then return end
  if self._previous_sibling then self._previous_sibling._next_sibling = self._next_sibling
  else parent._child_head = self._next_sibling end
  if self._next_sibling then self._next_sibling._previous_sibling = self._previous_sibling
  else parent._child_tail = self._previous_sibling end
  self._parent, self._previous_sibling, self._next_sibling = nil, nil, nil
end

---Construct a live object. Options must be a table when supplied; a parent
---must be a live YObject. Invalid options or parents raise assertions.
---@param opts? YObjectOptions [default: nil] Constructor options.
---@return YObject object # New object with its read-only id.
function YObject.new(opts)
  if opts == nil then opts = {} end
  assert(type(opts) == "table", "YObject options must be a table")
  validate_parent(nil, opts.parent)
  next_id = next_id + 1
  local self = setmetatable({ id = next_id, _connections = {}, _serial = 0,
    _emitting = 0, _dead = false, _blocked = false }, YObject)
  identities[self] = true
  self:set_parent(opts.parent)
  return self
end

---Read the current owner. Destruction detaches the object from its parent.
---@return YObject|nil parent # Current parent, or nil when unparented.
function YObject:parent() return self._parent end
---Read whether destruction has started.
---@return boolean destroyed # True from the start of destroy() onward.
function YObject:is_destroyed() return self._dead end

---Move ownership, or detach with nil. A parent must be a live YObject and
---must not create a cycle; invalid parents raise before the destroyed check.
---@param parent? YObject [default: nil] New live owner; nil detaches.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YObject:set_parent(parent)
  validate_parent(self, parent)
  if self._dead then return false, "destroyed" end
  if self._parent == parent then return false end
  detach(self)
  self._parent = parent
  if parent then
    self._previous_sibling = parent._child_tail
    if self._previous_sibling then self._previous_sibling._next_sibling = self
    else parent._child_head = self end
    parent._child_tail = self
  end
  YObject._notify_ancestry(self,'parent')
  return true
end

-- W-EFFECTS: ownership changes notify widgets even across non-widget owners.
local function notify_ancestry(object,reason)
  local affected={}
  local function collect(node)
    affected[#affected+1]=node
    local child=node._child_head
    while child do collect(child);child=child._next_sibling end
  end
  collect(object)
  for _,node in ipairs(affected)do
    if not node:is_destroyed() and node._effective_changed then node:_effective_changed(reason)end
  end
end
YObject._notify_ancestry=notify_ancestry

local function detach_receiver(connection)
  local receiver = connection.receiver
  if connection.in_previous then connection.in_previous.in_next = connection.in_next
  else receiver._incoming = connection.in_next end
  if connection.in_next then connection.in_next.in_previous = connection.in_previous end
  connection.in_previous, connection.in_next, connection.receiver = nil, nil, nil
end

local function prune(self)
  local cursor, previous = self._head, nil
  while cursor do
    if cursor.active then previous = cursor
    elseif previous then previous.next = cursor.next
    else self._head = cursor.next end
    cursor = cursor.next
  end
  self._tail = previous
end

---Connect a nonempty named signal to slot(receiver, a, b, c, d). Signal names
---are dynamic; no prior declaration is required. Invalid names, receivers or
---callbacks raise assertions. Connections are delivered in insertion order;
---connections added during emit() wait until a later emission. Destroying the
---sender or receiver automatically disconnects the connection.
---@param signal string Nonempty signal name.
---@param receiver YObject Object whose lifetime bounds the callback.
---@param slot fun(receiver: YObject, a: any, b: any, c: any, d: any) Callback; unused arguments may be omitted.
---@return integer|false token # Positive connection token, or false if either object is dead.
---@return "destroyed"|nil reason # "destroyed" if either object is dead; nil otherwise.
function YObject:connect(signal, receiver, slot)
  assert(type(signal) == "string" and signal ~= "", "signal must be a nonempty string")
  assert(YObject.is_instance(receiver), "receiver must be an YObject")
  assert(type(slot) == "function", "slot must be a function")
  if self._dead or receiver._dead then return false, "destroyed" end
  next_token = next_token + 1
  local connection = { token = next_token, signal = signal, receiver = receiver,
    sender = self, slot = slot, active = true, in_next = receiver._incoming }
  if receiver._incoming then receiver._incoming.in_previous = connection end
  receiver._incoming = connection
  if self._tail then self._tail.next = connection else self._head = connection end
  self._tail, self._serial = connection, next_token
  self._connections[next_token] = connection
  return next_token
end

---Remove one connection created by this sender. Invalid tokens raise an
---assertion; a valid but absent token is allowed, including after destruction.
---@param token integer Positive finite connection token.
---@return boolean removed # True when removed; false when absent.
function YObject:disconnect(token)
  assert(type(token) == "number" and token > 0 and token < math.huge
    and token == math.floor(token), "invalid connection token")
  local connection = self._connections[token]
  if not connection then return false end
  connection.active = false
  self._connections[token] = nil
  detach_receiver(connection)
  -- Emissions retain their traversal links until all nested delivery unwinds.
  if self._emitting == 0 then prune(self) end
  return true
end

local function deliver(self, signal, boundary, a, b, c, d)
  local connection = self._head
  while connection and connection.token <= boundary do
    if connection.active and connection.signal == signal and not connection.receiver._dead then
      connection.slot(connection.receiver, a, b, c, d)
    end
    connection = connection.next
  end
end

---Deliver a nonempty named signal synchronously with up to four arguments.
---Dynamic user-defined signal names are allowed. Disconnections during emission
---take effect immediately. Blocked signals are dropped, except destroyed.
---Invalid names raise assertions; callback errors propagate after delivery
---bookkeeping is restored. Nil arguments are passed to slots as nil.
---@param signal string Nonempty signal name.
---@param a? any [default: nil] First signal argument.
---@param b? any [default: nil] Second signal argument.
---@param c? any [default: nil] Third signal argument.
---@param d? any [default: nil] Fourth signal argument.
---@return boolean delivered # True if emitted or blocked; false if dead outside destroyed delivery.
---@return "destroyed"|nil reason # "destroyed" when emission is refused; nil otherwise.
function YObject:emit(signal, a, b, c, d)
  assert(type(signal) == "string" and signal ~= "", "signal must be a nonempty string")
  if self._dead and not (signal == "destroyed" and self._notifying_destroyed) then
    return false, "destroyed"
  end
  if self._blocked and signal ~= "destroyed" then return true end
  self._emitting = self._emitting + 1
  delivery_depth = delivery_depth + 1
  local ok, err = pcall(deliver, self, signal, self._serial, a, b, c, d)
  self._emitting = self._emitting - 1
  delivery_depth = delivery_depth - 1
  if self._emitting == 0 then prune(self) end
  if delivery_depth == 0 then queue_deletions() end
  if not ok then error(err, 0) end
  return true
end

---Set signal blocking and return its previous state, initially false.
---@param blocked boolean Whether to drop signals except destroyed.
---@return boolean previous # Previous blocked state, or false when destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YObject:block_signals(blocked)
  YObject.boolean(blocked)
  if self._dead then return false, "destroyed" end
  local previous = self._blocked
  self._blocked = blocked
  return previous
end

---Queue destruction with vim.schedule(); if delivery is active, scheduling
---waits until the outermost signal delivery finishes. Repeated calls while
---pending queue only one deletion. Scheduled destruction errors propagate.
---@return boolean queued # True for a live object, including when already pending; false when dead.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YObject:delete_later()
  if self._dead then return false, "destroyed" end
  if not self._delete_pending then
    self._delete_pending = true
    if deletion_tail then deletion_tail._delete_next = self else deletion_head = self end
    deletion_tail = self
    queue_deletions()
  end
  return true
end

---Start destruction, emit |YObject-destroyed|, destroy children in ownership
---order, disconnect incoming and outgoing connections, then detach from parent.
---Cleanup continues when a destroyed callback or child teardown throws; the
---first such error propagates after cleanup. Repeated destruction is refused.
---@return boolean destroyed # True on first destruction; false if already dead.
---@return "destroyed"|nil reason # "destroyed" when already dead; nil otherwise.
function YObject:destroy()
  if self._dead then return false, "destroyed" end
  self._dead, self._notifying_destroyed = true, true
  local ok, err = pcall(self.emit, self, "destroyed", self)
  self._notifying_destroyed = false
  -- Cleanup continues even if a destroyed slot throws; its error propagates.
  while self._child_head do
    local child = self._child_head
    local child_ok, child_error = pcall(child.destroy, child)
    if not child_ok and ok then ok, err = false, child_error end
    detach(child)
  end
  if self._dispose then
    local disposed, dispose_error = pcall(self._dispose, self)
    if not disposed and ok then ok, err = false, dispose_error end
  end
  while self._incoming do
    local connection = self._incoming
    connection.sender:disconnect(connection.token)
  end
  local connection = self._head
  while connection do
    local following = connection.next
    if connection.active then self:disconnect(connection.token) end
    connection = following
  end
  detach(self)
  if not ok then error(err, 0) end
  return true
end

return YObject
