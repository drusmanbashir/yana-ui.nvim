-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-FileCopyrightText: 2016 The Qt Company Ltd
-- SPDX-License-Identifier: LGPL-3.0-only
-- Derived from Qt src/widgets/kernel/qlayoutengine.cpp:291-350 (qtbase v6.8.3).
-- Derived from Qt src/widgets/kernel/qlayoutengine_p.h:83-98 (qtbase v6.8.3).
-- Derived from Qt src/widgets/kernel/qboxlayout.cpp:218-350 (qtbase v6.8.3).
-- Modified: Lua/Neovim adaptation by Usman Bashir; notice added 2026-10-08.
-- WIDGETS B: constraints and tree traversal; layout_axis alone allocates cells.
local YLayout = require("yana_ui.layout")
local YWidget = require("yana_ui.widget")
local Axis = require("yana_ui.layout_axis")
---@class YBoxAlignment
---@field horizontal "start"|"center"|"end"|"fill" Horizontal placement.
---@field vertical "start"|"center"|"end"|"fill" Vertical placement.
---@class YBoxLayoutOptions : YLayoutOptions
---@field axis? "horizontal"|"vertical" [default: "horizontal"] Main allocation axis.
---@class YBoxLayout : YLayout
---@doc brief Arrange visible virtual widgets and child layouts along one axis.
---@doc qt QBoxLayout. Allocation uses integer text cells, not pixels or native splits. Hidden widgets keep membership but receive no new rectangle; stretches do not add spacing gaps.
---@doc inherits |YLayout| and |YObject|; spacing, margins, parent and lifetime options are inherited. There are no new signals.
---@doc property axis|none|none|none|option:axis
---@doc errors Stretch factors and indices use YLayout's integer range. Widgets must be live YWidgets; child layouts must be live, unattached and acyclic. Alignment tables require both horizontal and vertical names. Type, integer and alignment validation precedes destruction checks; attachment conflicts are checked on insertion. Inherited layout errors still apply.
---@doc destroyed add_widget,add_layout,add_stretch,set_stretch
---@doc context lua/yana_ui/box_layout.lua|YBoxLayout
---@doc setup With your checkout on runtimepath, run this excerpt in Neovim. It creates virtual objects only and destroys its owner.
---@doc example local ui = require("yana_ui")
---@doc example local owner = ui.YObject.new()
---@doc example local row = ui.YBoxLayout.new({ parent = owner, spacing = 1 })
---@doc example local child = ui.YWidget.new({ parent = owner })
---@doc example child:show()
---@doc example assert(row:add_widget(child))
---@doc example assert(row:add_stretch(1))
---@doc example assert(row:activate(0, 0, 20, 2, 1))
---@doc example owner:destroy()
---@doc see |YLayout|, |YSizePolicy|, |YWidget|.
local YBoxLayout = setmetatable({}, { __index = YLayout })
YBoxLayout.__index = YBoxLayout
local limit = 2147483647
local alignments = { start = true, center = true, ["end"] = true, fill = true }
local function align(value)
  if value == nil then value = { horizontal = "fill", vertical = "fill" } end
  assert(type(value) == "table" and alignments[value.horizontal] and alignments[value.vertical], "invalid alignment")
  return { horizontal = value.horizontal, vertical = value.vertical }
end
local function widget_constraints(widget, horizontal, aligned)
  local hw, hh = widget:size_hint()
  local mw, mh = widget:minimum_size_hint()
  local xw, xh = widget:maximum_size()
  local hint, minimum, maximum = horizontal and hw or hh, horizontal and mw or mh, horizontal and xw or xh
  local policy = widget._policy
  local name = policy and (horizontal and policy:horizontal_policy() or policy:vertical_policy()) or "preferred"
  local stretch = policy and (horizontal and policy:horizontal_stretch() or policy:vertical_stretch()) or 0
  if name == "fixed" or name == "minimum" then minimum = math.max(minimum, hint) end
  minimum = math.min(minimum, maximum)
  hint = math.min(maximum, math.max(hint, minimum))
  if name == "fixed" or name == "maximum" then maximum = math.min(maximum, hint) end
  if aligned then maximum = limit end
  return minimum, hint, maximum, stretch, name == "expanding"
end
local constraints
local function item_constraints(item, horizontal)
  if item.kind == "stretch" then return 0, 0, limit, item.stretch, true end
  if item.kind == "layout" then
    local minimum, hint, maximum, expansive = constraints(item.value, horizontal)
    return minimum, hint, maximum, item.stretch, expansive
  end
  local alignment = horizontal and item.alignment.horizontal or item.alignment.vertical
  local minimum, hint, maximum, stretch, expansive = widget_constraints(item.value, horizontal, alignment ~= "fill")
  stretch = item.stretch > 0 and item.stretch or stretch
  return minimum, hint, maximum, stretch, expansive
end
local function visible(item)
  return item.kind ~= "widget" or item.value:is_visible()
end
constraints = function(layout, horizontal)
  local main = horizontal == (layout._axis == "horizontal")
  local minimum, hint, maximum, expansive, count = 0, 0, main and 0 or limit, false, 0
  for _, item in ipairs(layout._items) do
    if visible(item) then
      local mn, hn, mx, _, ex = item_constraints(item, horizontal)
      if item.kind == "stretch" then ex = main end
      if main then minimum, hint, maximum = minimum + mn, hint + hn, math.min(limit, maximum + mx)
      else
        minimum, hint = math.max(minimum, mn), math.max(hint, hn)
        -- qMaxExpCalc: an expansive cross-axis child wins over fixed siblings.
        if expansive then
          if ex then maximum = math.max(maximum, mx) end
        elseif ex or item.kind ~= "stretch" then maximum = mx
        else maximum = math.min(maximum, mx) end
      end
      expansive = expansive or ex or (main and item.stretch > 0)
      if item.kind ~= "stretch" then count = count + 1 end
    end
  end
  local margins = layout._margins
  local padding = horizontal and margins[1] + margins[3] or margins[2] + margins[4]
  if main then padding = padding + math.max(0, count - 1) * layout._spacing end
  maximum = math.max(minimum, maximum)
  hint = math.min(maximum, math.max(minimum, hint))
  return minimum + padding, hint + padding, math.min(limit, maximum + padding), expansive
end
---Create a horizontal or vertical box; other axis names raise an assertion.
---@param opts? YBoxLayoutOptions [default: nil] Axis and inherited layout/parent options.
---@return YBoxLayout layout # New box layout.
function YBoxLayout.new(opts)
  if opts == nil then opts = {} end
  assert(type(opts) == "table", "YBoxLayout options required")
  local axis = opts.axis
  if axis == nil then axis = "horizontal" end
  assert(axis == "horizontal" or axis == "vertical", "invalid YBoxLayout axis")
  local self = setmetatable(YLayout.new(opts), YBoxLayout)
  self._axis = axis
  return self
end
---Append a widget, moving it out of any previous layout. A containing widget
---adopts it. A positive item stretch overrides the size-policy stretch.
---@param widget YWidget Live widget.
---@param stretch? integer [default: 0] Main-axis weight.
---@param alignment? YBoxAlignment [default: fill on both axes] Placement within its allocated rectangle.
---@return boolean added # True on insertion; false when destroyed.
---@return "destroyed"|nil reason # Destruction error, or nil.
function YBoxLayout:add_widget(widget, stretch, alignment)
  assert(YWidget.is_instance(widget) and not widget:is_destroyed(), "invalid layout YWidget")
  if stretch == nil then stretch = 0 end
  YLayout.integer(stretch)
  local prepared = align(alignment)
  if self:is_destroyed() then return false, "destroyed" end
  return YLayout._append(self, { kind = "widget", value = widget, stretch = stretch, alignment = prepared })
end
---Append an unattached child layout, parent it to this layout and adopt its widgets.
---Attachment and ownership-cycle conflicts raise assertions.
---@param layout YLayout Live unattached child; use a concrete layout for activation.
---@param stretch? integer [default: 0] Main-axis weight.
---@return boolean added # True on insertion; false when destroyed.
---@return "destroyed"|nil reason # Destruction error, or nil.
function YBoxLayout:add_layout(layout, stretch)
  assert(YLayout.is_instance(layout), "invalid child YLayout")
  if stretch == nil then stretch = 0 end
  YLayout.integer(stretch)
  if self:is_destroyed() then return false, "destroyed" end
  return YLayout._append(self, { kind = "layout", value = layout, stretch = stretch })
end
---Append flexible empty space; the stretch argument is required.
---@param stretch integer Main-axis weight; zero is allowed.
---@return boolean added # True on insertion; false when destroyed.
---@return "destroyed"|nil reason # Destruction error, or nil.
function YBoxLayout:add_stretch(stretch)
  YLayout.integer(stretch)
  if self:is_destroyed() then return false, "destroyed" end
  return YLayout._append(self, { kind = "stretch", stretch = stretch })
end
---Change an existing item weight and invalidate. A missing item index raises
---an assertion when the layout is live.
---@param index integer Zero-based item index.
---@param stretch integer New main-axis weight.
---@return boolean changed # True on change; false when unchanged or destroyed.
---@return "destroyed"|nil reason # Destruction error, or nil.
function YBoxLayout:set_stretch(index, stretch)
  YLayout.integer(index); YLayout.integer(stretch)
  if self:is_destroyed() then return false, "destroyed" end
  local item = self:item_at(index); assert(item, "invalid stretch index")
  if item.stretch == stretch then return false end
  item.stretch = stretch; self:invalidate(); return true
end
local function child_axis(widget, horizontal, available, alignment)
  local _, hint, maximum = widget_constraints(widget, horizontal, false)
  local size = math.min(available, maximum)
  if alignment ~= "fill" then size = math.min(size, hint) end
  local offset = 0
  if alignment == "end" then offset = available - size
  elseif alignment == "center" or alignment == "fill" then offset = math.floor((available - size) / 2) end
  return size, offset
end
function YBoxLayout:_collect(row, col, width, height, plan)
  assert(not self:is_destroyed(), "destroyed nested YLayout")
  local m = self._margins
  row, col = row + m[2], col + m[1]
  width, height = math.max(0, width - m[1] - m[3]), math.max(0, height - m[2] - m[4])
  local horizontal = self._axis == "horizontal"
  local chain = {}
  for _, item in ipairs(self._items) do
    if visible(item) then
      local minimum, hint, maximum, stretch, expansive = item_constraints(item, horizontal)
      chain[#chain + 1] = { item = item, minimum = minimum, hint = stretch > 0 and minimum or hint,
        maximum = maximum, stretch = stretch, expansive = expansive or stretch > 0, empty = item.kind == "stretch" }
    end
  end
  Axis.allocate(chain, horizontal and col or row, horizontal and width or height, self._spacing)
  for _, data in ipairs(chain) do
    local item = data.item
    if item.kind ~= "stretch" then
      local cr, cc = horizontal and row or data.position, horizontal and data.position or col
      local cw, ch = horizontal and data.size or width, horizontal and height or data.size
      if item.kind == "layout" then item.value:_collect(cr, cc, cw, ch, plan)
      else
        local xw, xo = child_axis(item.value, true, cw, item.alignment.horizontal)
        local xh, yo = child_axis(item.value, false, ch, item.alignment.vertical)
        local rectangle = { cr + yo, cc + xo, xw, xh }
        plan[#plan + 1] = { widget = item.value, rect = rectangle }
        if item.value._layout then item.value._layout:_collect(rectangle[1], rectangle[2], xw, xh, plan) end
      end
    end
  end
end
-- DOCS: YBoxLayout example start
-- local ui = require("yana_ui")
-- local owner = ui.YObject.new()
-- local row = ui.YBoxLayout.new({ parent = owner, spacing = 1 })
-- local child = ui.YWidget.new({ parent = owner })
-- child:show()
-- assert(row:add_widget(child))
-- assert(row:add_stretch(1))
-- assert(row:activate(0, 0, 20, 2, 1))
-- owner:destroy()
-- DOCS: YBoxLayout example end
return YBoxLayout
