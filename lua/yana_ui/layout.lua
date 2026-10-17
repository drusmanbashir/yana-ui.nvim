-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-FileCopyrightText: 2016 The Qt Company Ltd
-- SPDX-License-Identifier: LGPL-3.0-only
-- Derived from Qt src/widgets/kernel/qlayout.cpp:755-786 (qtbase v6.8.3).
-- Modified: Lua/Neovim adaptation by Usman Bashir; notice added 2026-10-08.
-- WIDGETS L: sole opt-in item membership and committed YWidget rectangle owner.
local YObject = require("yana_ui.object")
local YWidget = require("yana_ui.widget")
---@class YLayoutMargins
---@field left? integer [default: 0] Left inset in cells.
---@field top? integer [default: 0] Top inset in cells.
---@field right? integer [default: 0] Right inset in cells.
---@field bottom? integer [default: 0] Bottom inset in cells.
---@class YLayoutOptions : YObjectOptions
---@field spacing? integer [default: 0] Gap between visible non-stretch items.
---@field margins? YLayoutMargins [default: {}] Insets; omitted sides are zero.
---@class YLayoutItem
---@field kind "widget"|"layout"|"stretch" Item category.
---@field value? YWidget|YLayout Widget or child layout; absent for stretches.
---@field stretch integer Main-axis stretch factor.
---@field alignment? YBoxAlignment Widget horizontal/vertical alignment.
---@class YLayout : YObject
---@doc brief Own virtual item membership and commit widget rectangles in text cells.
---@doc qt QLayout. You use zero-based cell rectangles and generation numbers; native windows remain the host's responsibility. The base layout is abstract.
---@doc inherits |YObject|; parent options, lifetime methods and the destroyed signal keep their inherited semantics.
---@doc property spacing|none|set_spacing(value)|none|option:spacing
---@doc property contents_margins|none|set_contents_margins(l, t, r, b)|none|option:margins
---@doc property count|count()|none|none|0
---@doc errors Layout integers must be finite whole numbers from 0 through 2147483647; generation starts at 1. Validation raises assertions before destruction checks. Options and margins must be tables; parent validation follows YObject. Read methods remain available after destruction.
---@doc destroyed invalidate,set_spacing,set_contents_margins,take_at,activate
---@doc exception No class-specific signals are emitted. activate() returns false, "stale" for a generation below the last successful activation. Calling activate() on the abstract base raises; nested calculation errors propagate before any rectangle is published.
---@doc context lua/yana_ui/layout.lua|YLayout
---@doc setup With your checkout on runtimepath, run this excerpt in Neovim. It owns only a layout and creates no windows.
---@doc example local ui = require("yana_ui")
---@doc example local layout = ui.YLayout.new({ spacing = 1 })
---@doc example assert(layout:count() == 0)
---@doc example assert(layout:set_contents_margins(1, 0, 1, 0))
---@doc example assert(layout:invalidate())
---@doc example layout:destroy()
---@doc see |YBoxLayout|, |YSizePolicy|, |YObject|.
local YLayout = setmetatable({}, { __index = YObject })
YLayout.__index = YLayout
local instances = setmetatable({}, { __mode = "k" })
local rects = setmetatable({}, { __mode = "k" })
---Recognize base and box layouts, including destroyed layouts.
---@param value any Value to inspect.
---@return boolean instance # Whether this value was allocated as a layout.
function YLayout.is_instance(value) return instances[value] == true end
---Validate a layout integer using the shared range; raise an assertion on failure.
---@param n integer Value to validate.
---@param minimum? integer [default: 0] Inclusive lower bound.
---@return nil result # No value is returned on success.
function YLayout.integer(n, minimum)
  assert(type(n) == "number" and n >= (minimum or 0) and n <= 2147483647
    and n == math.floor(n), "invalid layout integer")
end
---Read the last committed rectangle; return four zeros before the first commit.
---@param widget YWidget Widget to inspect.
---@return integer row # Zero-based top row.
---@return integer col # Zero-based left column.
---@return integer width # Width in cells.
---@return integer height # Height in cells.
function YLayout.rect(widget)
  local rect = rects[widget]
  if rect then return rect[1], rect[2], rect[3], rect[4] end
  return 0, 0, 0, 0
end
---Create an abstract layout; use YBoxLayout when you need activation.
---@param opts? YLayoutOptions [default: nil] Options, including inherited parent.
---@return YLayout layout # New empty layout.
function YLayout.new(opts)
  if opts == nil then opts = {} end
  assert(type(opts) == "table", "YLayout options required")
  local spacing, margins = opts.spacing, opts.margins
  if spacing == nil then spacing = 0 end
  if margins == nil then margins = {} end
  assert(type(margins) == "table", "invalid layout margins")
  YLayout.integer(spacing)
  local l, t, r, b = margins.left, margins.top, margins.right, margins.bottom
  if l == nil then l = 0 end
  if t == nil then t = 0 end
  if r == nil then r = 0 end
  if b == nil then b = 0 end
  YLayout.integer(l); YLayout.integer(t); YLayout.integer(r); YLayout.integer(b)
  local self = setmetatable(YObject.new(opts), YLayout)
  self._items, self._spacing, self._margins, self._dirty = {}, spacing, { l, t, r, b }, true
  instances[self] = true
  return self
end
---Mark the layout dirty and invalidate its containing layout, if any.
---@return boolean invalidated # True when live; false when destroyed.
---@return "destroyed"|nil reason # Destruction error, or nil.
function YLayout:invalidate()
  if self:is_destroyed() then return false, "destroyed" end
  self._dirty = true
  if self._container then self._container:invalidate() end
  return true
end
---Change spacing and invalidate the layout; unchanged values do nothing.
---@param value integer Gap in cells.
---@return boolean changed # True on change; false when unchanged or destroyed.
---@return "destroyed"|nil reason # Destruction error, or nil.
function YLayout:set_spacing(value)
  YLayout.integer(value)
  if self:is_destroyed() then return false, "destroyed" end
  if self._spacing == value then return false end
  self._spacing = value; self:invalidate(); return true
end
---Change the four cell insets and invalidate; unchanged values do nothing.
---@param l integer Left inset.
---@param t integer Top inset.
---@param r integer Right inset.
---@param b integer Bottom inset.
---@return boolean changed # True on change; false when unchanged or destroyed.
---@return "destroyed"|nil reason # Destruction error, or nil.
function YLayout:set_contents_margins(l, t, r, b)
  YLayout.integer(l); YLayout.integer(t); YLayout.integer(r); YLayout.integer(b)
  if self:is_destroyed() then return false, "destroyed" end
  local m = self._margins
  if m[1] == l and m[2] == t and m[3] == r and m[4] == b then return false end
  m[1], m[2], m[3], m[4] = l, t, r, b; self:invalidate(); return true
end
---Read the number of items, including hidden widgets and stretches.
---@return integer count # Current item count; zero after destruction.
function YLayout:count() return #self._items end
---Read an item without removing it; indices start at zero.
---@param index integer Zero-based item index.
---@return YLayoutItem|nil item # Stored item, or nil outside the list.
function YLayout:item_at(index) YLayout.integer(index); return self._items[index + 1] end
---Remove an item without destroying it. Widgets keep their parent; child layouts
---are detached from their parent and container. The remaining layout is invalidated.
---@param index integer Zero-based item index.
---@return YLayoutItem|false|nil item # Removed item; nil outside the list; false when destroyed.
---@return "destroyed"|nil reason # Destruction error, or nil.
function YLayout:take_at(index)
  YLayout.integer(index)
  if self:is_destroyed() then return false, "destroyed" end
  if index >= #self._items then return nil end
  local item = table.remove(self._items, index + 1)
  if not item then return nil end
  if item.kind == "widget" then
    if item.value._geometry_layout == self then item.value._geometry_layout = nil end
    item.value:disconnect(item.connection)
  elseif item.kind == "layout" then
    item.value:disconnect(item.connection)
    item.value._container = nil; item.value:set_parent(nil)
  end
  self:invalidate(); return item
end
local function remove_widget(self, widget)
  for i, item in ipairs(self._items) do
    if item.value == widget then self:take_at(i - 1); return end
  end
end
local function adopt_children(layout, parent, validate)
  if not parent then return end
  for _, item in ipairs(layout._items) do
    if item.kind == "widget" then
      if validate then
        local cursor = parent
        while cursor do assert(cursor ~= item.value, "YWidget adoption cycle"); cursor = cursor:parent() end
      else item.value:set_parent(parent) end
    elseif item.kind == "layout" then adopt_children(item.value, parent, validate) end
  end
end
local function parent_widget(layout)
  local parent = layout:parent()
  while parent and not YWidget.is_instance(parent) do parent = parent:parent() end
  return parent
end
function YLayout._append(self, item)
  if item.kind == "widget" then
    local widget = item.value
    assert(not widget:is_destroyed(), "cannot add destroyed YWidget")
    local parent = parent_widget(self)
    if parent then widget:set_parent(parent) end
    if widget._geometry_layout then remove_widget(widget._geometry_layout, widget) end
    widget._geometry_layout = self
    item.connection = widget:connect("destroyed", self, remove_widget)
  elseif item.kind == "layout" then
    local layout = item.value
    assert(not layout:is_destroyed() and layout ~= self and not layout:parent() and not layout._container, "YLayout already attached")
    local cursor = self
    while cursor do assert(cursor ~= layout, "YLayout cycle"); cursor = cursor:parent() end
    local parent = parent_widget(self)
    adopt_children(layout, parent, true)
    layout:set_parent(self); layout._container = self
    adopt_children(layout, parent, false)
    item.connection = layout:connect("destroyed", self, remove_widget)
  end
  self._items[#self._items + 1] = item; self:invalidate(); return true
end
---Attach a layout to a widget and adopt its descendant widgets. Attachment,
---foreign-parent and adoption-cycle conflicts raise assertions. Use YWidget:set_layout()
---to install the widget-side layout reference.
---@param layout YLayout Uncontained layout.
---@param widget YWidget Owning widget.
---@return nil result # No value is returned.
function YLayout.bind(layout, widget)
  assert(YLayout.is_instance(layout) and not layout._container, "YLayout already attached")
  assert(not layout:parent() or layout:parent() == widget, "YLayout has a foreign parent")
  adopt_children(layout, widget, true)
  layout:set_parent(widget)
  adopt_children(layout, widget, false)
end
function YLayout:_collect(row, col, width, height, plan)
  error("abstract YLayout cannot activate", 2)
end
---Calculate the full layout before publishing rectangles and requesting widget updates.
---Equal generations may reactivate; lower generations are refused.
---@param row integer Zero-based top row.
---@param col integer Zero-based left column.
---@param width integer Available width in cells.
---@param height integer Available height in cells.
---@param generation integer Positive generation, at most 2147483647.
---@return boolean activated # True after commit; false when destroyed or stale.
---@return "destroyed"|"stale"|nil reason # Refusal reason, or nil on success.
function YLayout:activate(row, col, width, height, generation)
  YLayout.integer(row); YLayout.integer(col); YLayout.integer(width); YLayout.integer(height); YLayout.integer(generation, 1)
  if self:is_destroyed() then return false, "destroyed" end
  if self._generation and generation < self._generation then return false, "stale" end
  local plan = {}
  self:_collect(row, col, width, height, plan)
  -- No rectangle is published until every nested calculation has succeeded.
  for _, candidate in ipairs(plan) do
    rects[candidate.widget] = candidate.rect
    candidate.widget:update()
  end
  self._generation, self._dirty = generation, false
  return true
end
function YLayout:_dispose()
  local parent = self:parent()
  if YWidget.is_instance(parent) then YWidget._release_layout(parent, self) end
  for _, item in ipairs(self._items) do
    if item.kind == "widget" then
      if item.value._geometry_layout == self then item.value._geometry_layout = nil end
      item.value:disconnect(item.connection)
    elseif item.kind == "layout" then
      item.value:disconnect(item.connection); item.value._container = nil
    end
  end
  self._items = {}
end
-- DOCS: YLayout example start
-- local ui = require("yana_ui")
-- local layout = ui.YLayout.new({ spacing = 1 })
-- assert(layout:count() == 0)
-- assert(layout:set_contents_margins(1, 0, 1, 0))
-- assert(layout:invalidate())
-- layout:destroy()
-- DOCS: YLayout example end
return YLayout
