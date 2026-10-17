-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-FileCopyrightText: 2017 The Qt Company Ltd
-- SPDX-FileCopyrightText: 2016 Intel Corporation
-- SPDX-License-Identifier: LGPL-3.0-only
-- Derived from Qt src/widgets/kernel/qwidget.cpp:8221-8223 (qtbase v6.8.3).
-- Modified: Lua/Neovim adaptation by Usman Bashir; notice added 2026-10-08.
-- WIDGETS W: YObject owns the tree; YWidget owns local appearance and paint intent.
local YObject = require("yana_ui.object")
---@class YWidgetSize
---@field width integer Cell width from 0 through 2147483647.
---@field height integer Cell height from 0 through 2147483647.
---@class YWidgetOptions : YObjectOptions
---@field paint? fun(widget: YWidget, writer: YPaintWriter) [default: nil] Paint callback; use the supplied writer.
---@field event? fun(widget: YWidget, kind: string, row: integer, col: integer, button: integer, key: string, mods: any, pos: table|nil): boolean [default: nil] Return true to accept an event.
---@field size_hint? YWidgetSize [default: { width = 0, height = 0 }] Preferred cell size.
---@field minimum_size_hint? YWidgetSize [default: { width = 0, height = 0 }] Minimum cell size hint.
---@field maximum_size? YWidgetSize [default: { width = 2147483647, height = 2147483647 }] Maximum cell size.
---@field size_policy? YSizePolicy [default: nil] Layout allocation policy.
---@class YWidget : YObject
---@doc brief A virtual control with parent-owned visibility, enabled state and cell geometry.
---@doc qt QWidget. You supply a Neovim canvas and callbacks; a widget is not a native window. YLayout assigns its rectangle, and YPaintWriter writes its canvas.
---@doc inherits |YObject|; inherited methods and destroyed retain |YObject| semantics.
---@doc property visible|is_visible()|set_visible(value), show(), hide()|pointer_target_changed|false (unshown)
---@doc property enabled|is_enabled()|set_enabled(value)|pointer_target_changed|true
---@doc property hovered|under_mouse()|none|none|false
---@doc property pressed|is_pressed()|none|none|false
---@doc property size_hint|size_hint()|set_size_hint(w, h)|none|option:size_hint
---@doc property minimum_size_hint|minimum_size_hint()|set_minimum_size_hint(w, h)|none|option:minimum_size_hint
---@doc property maximum_size|maximum_size()|set_maximum_size(w, h)|none|option:maximum_size
---@doc property size_policy|none|set_size_policy(policy)|none|option:size_policy
---@doc property rect|rect()|none|none|0, 0, 0, 0 until allocated
---@doc property layout|none|set_layout(layout)|none|nil
---@signal pointer_target_changed() | Emitted after a local visibility or enabled change schedules descendant updates and invalidates layout. Unchanged values emit nothing; ancestor propagation and showing unshown children do not emit their signal.
---@doc errors Boolean setters reject non-booleans; size fields and setters require integers from 0 through 2147483647. Invalid values raise before the destroyed check. Parent validation follows |YObject|; callback errors propagate.
---@doc destroyed update,set_visible,show,hide,set_enabled,set_size_hint,set_minimum_size_hint,set_maximum_size,set_size_policy,set_layout,paint,event
---@doc exception set_layout() also refuses a destroyed layout. State getters return false after destruction; size getters remain readable.
---@doc context lua/yana_ui/widget.lua|YWidget
---@doc setup Run this block in Neovim with yana-ui on runtimepath. It needs no window or buffer and destroys its owner.
-- DOCS: YWidget example start
---@doc example local ui = require("yana_ui")
---@doc example local owner = ui.YObject.new()
---@doc example local root = ui.YWidget.new({ parent = owner })
---@doc example local child = ui.YWidget.new({ parent = root, size_hint = { width = 8, height = 1 } })
---@doc example root:show()
---@doc example assert(child:is_visible())
---@doc example child:hide(); root:hide(); root:show()
---@doc example assert(not child:is_visible())
---@doc example owner:destroy()
-- DOCS: YWidget example end
---@doc see |YObject|, |YLayout|, |YPaintWriter|, |yana-ui-tutorial-toolbar|.
local YWidget = setmetatable({}, { __index = YObject })
YWidget.__index = YWidget
local instances = setmetatable({}, { __mode = "k" })
local limit = 2147483647
local function dimension(n)
  assert(type(n) == "number" and n >= 0 and n <= limit and n == math.floor(n), "invalid size")
end
local function size(value, default)
  if value == nil then return default, default end
  assert(type(value) == "table", "invalid size")
  dimension(value.width); dimension(value.height)
  return value.width, value.height
end
---Recognize YWidget identities, including subclasses and destroyed widgets.
---@param value any Value to inspect.
---@return boolean instance # True for an allocated widget identity.
function YWidget.is_instance(value) return instances[value] == true end
---Create an initially unshown, enabled control. Options and size fields must
---be tables; paint and event must be functions when supplied. Invalid options
---raise assertions; size_policy must be a YSizePolicy when supplied.
---@param opts? YWidgetOptions [default: nil] Constructor options.
---@return YWidget widget # New virtual control.
function YWidget.new(opts)
  if opts == nil then opts = {} end
  assert(type(opts) == "table", "YWidget options must be a table")
  assert(opts.paint == nil or type(opts.paint) == "function", "invalid paint callback")
  assert(opts.event == nil or type(opts.event) == "function", "invalid event callback")
  local hw, hh = size(opts.size_hint, 0)
  local mw, mh = size(opts.minimum_size_hint, 0)
  local xw, xh = size(opts.maximum_size, limit)
  if opts.size_policy ~= nil then
    assert(require("yana_ui.size_policy").is_instance(opts.size_policy), "invalid size policy")
  end
  local self = setmetatable(YObject.new(opts), YWidget)
  instances[self] = true
  self._visibility, self._enabled = "unshown", true
  self._hovered, self._pressed = false, false
  self._paint_callback, self._event_callback = opts.paint, opts.event
  self._hint_w, self._hint_h, self._min_w, self._min_h = hw, hh, mw, mh
  self._max_w, self._max_h, self._policy = xw, xh, opts.size_policy
  return self
end
---Read effective visibility: this widget and every widget ancestor must be
---shown and live. Explicitly hidden children stay hidden when a parent shows.
---@return boolean visible # Effective visibility; false when destroyed.
function YWidget:is_visible()
  if self:is_destroyed() or self._visibility ~= "shown" then return false end
  local parent = self:parent()
  while parent do
    if YWidget.is_instance(parent) and (parent:is_destroyed() or parent._visibility ~= "shown") then return false end
    parent = parent:parent()
  end
  return true
end
---Read effective enabled state across this widget and its widget ancestors.
---@return boolean enabled # Effective enabled state; false when destroyed.
function YWidget:is_enabled()
  if self:is_destroyed() or not self._enabled then return false end
  local parent = self:parent()
  while parent do
    if YWidget.is_instance(parent) and not parent._enabled then return false end
    parent = parent:parent()
  end
  return true
end
---Read the pointer state maintained by YEventDispatcher.
---@return boolean hovered # True when hovered and live.
function YWidget:under_mouse() return not self:is_destroyed() and self._hovered end
---Read the pressed state maintained by YEventDispatcher.
---@return boolean pressed # True when pressed and live.
function YWidget:is_pressed() return not self:is_destroyed() and self._pressed end
function YWidget._pointer(widget, hovered, pressed)
  if widget:is_destroyed() then return false end
  if widget._hovered == hovered and widget._pressed == pressed then return false end
  widget._hovered, widget._pressed = hovered, pressed
  widget:update()
  return true
end
function YWidget:_grab_cancelled() end
-- W-EFFECTS: internal observers cannot be suppressed by block_signals().
function YWidget._observe_effective(widget,owner,callback)
  widget._state_observers=widget._state_observers or setmetatable({}, {__mode='k'})
  widget._state_observers[owner]=callback
end
function YWidget:_effective_changed(reason)
  if self:is_destroyed() then return end
  self:update()
  if self._geometry_layout then self._geometry_layout:invalidate() end
  local observers={}
  for owner,callback in pairs(self._state_observers or {})do observers[#observers+1]={owner,callback}end
  for _,entry in ipairs(observers)do
    if self:is_destroyed()then break end
    local owner,callback=entry[1],entry[2]
    if not owner:is_destroyed() and self._state_observers[owner]==callback then callback(owner,reason)end
  end
end
---Request paint from an attached writer, or retain a pending request until
---one is attached. This does not flush the canvas.
---@return boolean changed # True when requested; false if destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YWidget:update()
  if self:is_destroyed() then return false, "destroyed" end
  self._paint_pending = true
  if self._writer then self._writer:request(self) end
  return true
end
local function reveal(self)
  local child = self._child_head
  while child do
    if YWidget.is_instance(child) and child._visibility == "unshown" then
      child._visibility = "shown"; child:update(); reveal(child)
    end
    child = child._next_sibling
  end
end
---Set local visibility; showing reveals unshown widget children and repeats
---beneath those children.
---See |YWidget-pointer_target_changed| for notification ordering.
---@param value boolean Local visibility.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YWidget:set_visible(value)
  YObject.boolean(value)
  if self:is_destroyed() then return false, "destroyed" end
  local state = value and "shown" or "hidden"
  if self._visibility == state then return false end
  self._visibility = state
  if value then reveal(self) end
  YObject._notify_ancestry(self)
  -- Qt src/widgets/kernel/qwidget.cpp:8221-8223: hiding changes pointer target.
  self:emit("pointer_target_changed")
  return true
end
---Show through |YWidget:set_visible()|.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YWidget:show() return self:set_visible(true) end
---Hide through |YWidget:set_visible()|.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YWidget:hide() return self:set_visible(false) end
---Set local enabled state; ancestors still constrain effective state.
---@param value boolean Local enabled state.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YWidget:set_enabled(value)
  YObject.boolean(value)
  if self:is_destroyed() then return false, "destroyed" end
  if self._enabled == value then return false end
  self._enabled = value; YObject._notify_ancestry(self)
  self:emit("pointer_target_changed")
  return true
end
---Read both stored cell dimensions.
---@return integer width # Preferred width.
---@return integer height # Preferred height.
function YWidget:size_hint() return self._hint_w, self._hint_h end
---Read both stored cell dimensions.
---@return integer width # Minimum hint width.
---@return integer height # Minimum hint height.
function YWidget:minimum_size_hint() return self._min_w, self._min_h end
---Read both stored cell dimensions.
---@return integer width # Maximum width.
---@return integer height # Maximum height.
function YWidget:maximum_size() return self._max_w, self._max_h end
local function set_size(self, w, h, wk, hk)
  dimension(w); dimension(h)
  if self:is_destroyed() then return false, "destroyed" end
  if self[wk] == w and self[hk] == h then return false end
  self[wk], self[hk] = w, h
  if self._geometry_layout then self._geometry_layout:invalidate() end
  return true
end
---Store cell dimensions and invalidate the allocating layout on a change.
---@param w integer Cell width.
---@param h integer Cell height.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YWidget:set_size_hint(w, h) return set_size(self, w, h, "_hint_w", "_hint_h") end
---Store cell dimensions and invalidate the allocating layout on a change.
---@param w integer Cell width.
---@param h integer Cell height.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YWidget:set_minimum_size_hint(w, h) return set_size(self, w, h, "_min_w", "_min_h") end
---Store cell dimensions and invalidate the allocating layout on a change.
---@param w integer Cell width.
---@param h integer Cell height.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YWidget:set_maximum_size(w, h) return set_size(self, w, h, "_max_w", "_max_h") end
---Set the allocation policy and invalidate the allocating layout on change.
---A non-YSizePolicy raises an assertion before the destroyed check.
---@param policy YSizePolicy Allocation policy; nil is not accepted here.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YWidget:set_size_policy(policy)
  assert(require("yana_ui.size_policy").is_instance(policy), "invalid size policy")
  if self:is_destroyed() then return false, "destroyed" end
  if self._policy == policy then return false end
  self._policy = policy
  if self._geometry_layout then self._geometry_layout:invalidate() end
  return true
end
---Read the rectangle assigned by YLayout; coordinates are zero-based cells.
---@return integer row # Top row.
---@return integer col # Left column.
---@return integer width # Allocated width.
---@return integer height # Allocated height.
function YWidget:rect() return require("yana_ui.layout").rect(self) end
---Bind one YLayout. A non-layout or replacement of an existing different
---layout raises an assertion; layout binding may also reject invalid ownership.
---@param layout YLayout Live layout to bind.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when the widget or supplied layout is dead; nil otherwise.
function YWidget:set_layout(layout)
  assert(require("yana_ui.layout").is_instance(layout), "invalid layout")
  if self:is_destroyed() or layout:is_destroyed() then return false, "destroyed" end
  if self._layout == layout then return false end
  assert(self._layout == nil, "YWidget already has a layout")
  require("yana_ui.layout").bind(layout, self)
  self._layout = layout
  return true
end
function YWidget._release_layout(widget, layout)
  if widget._layout == layout then widget._layout = nil end
end
---Call your paint callback when supplied; its return value is ignored.
---@param writer YPaintWriter Canvas writer passed to your callback.
---@return boolean painted # True after the callback or when absent; false if destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YWidget:paint(writer)
  if self:is_destroyed() then return false, "destroyed" end
  if self._paint_callback then self._paint_callback(self, writer) end
  return true
end
---Call your event callback; only a literal true accepts the event.
---@param kind string Event kind from YEventDispatcher.
---@param row integer Zero-based canvas row, unchanged during bubbling.
---@param col integer Zero-based canvas display column, unchanged during bubbling.
---@param button integer Mouse button supplied by the dispatcher.
---@param key string Normalized key name for key events.
---@param mods any Modifier state supplied by the dispatcher.
---@param pos? table [default: nil] Native pointer observation, including clicks when supplied by mapped intake.
---@return boolean accepted # True only when your callback accepts; false if absent or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YWidget:event(kind, row, col, button, key, mods, pos)
  if self:is_destroyed() then return false, "destroyed" end
  return self._event_callback ~= nil and self._event_callback(self, kind, row, col, button, key, mods, pos) == true
end
return YWidget
