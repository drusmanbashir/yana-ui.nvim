-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-FileCopyrightText: 2016 The Qt Company Ltd
-- SPDX-License-Identifier: LGPL-3.0-only
-- Derived from Qt src/widgets/widgets/qtoolbutton.cpp:657-686,693-738,779-816 (qtbase v6.8.3).
-- Modified: Lua/Neovim adaptation by Usman Bashir; notice added 2026-10-12.
-- WIDGETS BTN-T: YPushButton command semantics and YStyle-owned flat idle.
local YPushButton = require("yana_ui.push_button")
local YObject = require("yana_ui.object")
local YWidget = require("yana_ui.widget")
---@class YToolButtonOptions : YPushButtonOptions
---@field auto_raise? boolean [default: false] Use tool_button appearance for flat idle styling; otherwise use button appearance.
---@class YToolButton : YPushButton
---@doc brief An icon-first button with optional flat idle appearance.
---@doc qt QToolButton. It uses borrowed action state and supports an attached instant menu. An icon replaces the label when nonempty. Delayed/split-button popup modes and auto-repeat are not supported.
---@doc inherits |YPushButton|; its options, properties, methods and signals retain their semantics. auto_raise selects the YStyle role rather than adding a native window.
---@doc property auto_raise|auto_raise()|set_auto_raise(value)|none|option:auto_raise
---@doc property menu|menu()|set_menu(value)|none|nil
---@doc property popup_mode|popup_mode()|set_popup_mode(value)|none|instant
---@signal triggered(action: YAction) | Forwarded synchronously whenever the attached action emits triggered, including external action:trigger() calls. In a button activation this precedes released and clicked; toggled comes first for a checkable action.
---@doc errors auto_raise and set_auto_raise() require booleans. set_menu() requires a live YMenu or nil; set_popup_mode() requires "instant". Invalid values raise before the destroyed check. Remaining validation follows |YPushButton|.
---@doc destroyed set_auto_raise,set_menu,set_popup_mode
---@doc exception Inherited methods keep |YPushButton| destruction and action-owned errors.
---@doc context lua/yana_ui/tool_button.lua|YToolButton
---@doc setup Run this block in Neovim with yana-ui on runtimepath. It creates and removes its own canvas/float; external action triggering exercises the forwarded signal without drawing.
-- DOCS: YToolButton example start
---@doc example local ui = require("yana_ui")
---@doc example local owner = ui.YObject.new(); local root = ui.YWidget.new({ parent = owner })
---@doc example local buf = vim.api.nvim_create_buf(false, true)
---@doc example local win = vim.api.nvim_open_win(buf, false, { relative = "editor", row = 0, col = 0, width = 20, height = 1, style = "minimal" })
---@doc example local target = function() return win, buf, 1 end
---@doc example local focus = ui.YFocus.new({ parent = owner, current_target = target }); local style = ui.YStyle.new({ focus = focus })
---@doc example local writer = ui.YPaintWriter.new({ parent = owner, win = win, buf = buf, generation = 1, current_target = target })
---@doc example local dispatcher = ui.YEventDispatcher.new({ parent = owner, root = root, focus = focus, writer = writer, current_target = target })
---@doc example local action = ui.YAction.new({ parent = owner, label = "Refresh" })
---@doc example local button = ui.YToolButton.new({ parent = root, style = style, focus = focus, dispatcher = dispatcher, current_target = target, action = action, icon = "↻", auto_raise = true })
---@doc example button:connect("triggered", owner, function(_, command) assert(command == action) end)
---@doc example assert(action:trigger()); assert(button:auto_raise())
---@doc example owner:destroy()
---@doc example if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
---@doc example if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
-- DOCS: YToolButton example end
---@doc see |YPushButton|, |YAction|, |YToolBar|, |YStyle|.
local YToolButton = setmetatable({}, { __index = YPushButton })
YToolButton.__index = YToolButton
---Create an unshown tool button using the required push-button owners.
---@param opts YToolButtonOptions Required constructor options.
---@return YToolButton button # New tool button.
function YToolButton.new(opts)
  assert(type(opts) == "table", "YToolButton options required")
  if opts.auto_raise ~= nil then YObject.boolean(opts.auto_raise) end
  local self = setmetatable(YPushButton.new(opts), YToolButton)
  self._tool_button, self._auto_raise = true, opts.auto_raise == true
  self:_cold()
  return self
end
function YToolButton:_content() return self:icon() ~= "" and self:icon() or self:label() end
---Read which style role the button uses.
---@return boolean auto_raise # True for tool_button appearance.
function YToolButton:auto_raise() return self._auto_raise end
---Read the borrowed attached menu.
---@return YMenu|nil menu # Attached menu, or nil.
function YToolButton:menu() return self._menu end
---Read the supported popup policy.
---@return "instant" mode # Attached menus open on press.
function YToolButton:popup_mode() return "instant" end
---Select the only supported popup mode; unsupported modes raise before mutation.
---@param value "instant" Supported popup mode.
---@return boolean changed # False because instant is the sole mode.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YToolButton:set_popup_mode(value)
  assert(value == "instant", "unsupported popup mode")
  if self:is_destroyed() then return false, "destroyed" end
  return false
end
---Attach or detach a borrowed menu; its ownership does not change.
---@param value? YMenu [default: nil] Live menu; nil detaches.
---@return boolean changed # True on replacement, false otherwise.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YToolButton:set_menu(value)
  assert(value == nil or (YWidget.is_instance(value) and not value:is_destroyed()
    and type(value.popup_anchored) == "function"), "expected live YMenu")
  if self:is_destroyed() then return false, "destroyed" end
  if value == self._menu then return false end
  self:_cancel()
  if self._menu and self._menu_connection then self._menu:disconnect(self._menu_connection) end
  self._menu, self._menu_connection = value, nil
  if value then
    self._menu_connection = value:connect("destroyed", self, function(button)
      button._menu, button._menu_connection = nil, nil; button:update()
    end)
  end
  self:update(); return true
end
---Read command press state or the down state of an open attached popup.
---@return boolean pressed # True while this control's popup is open or its command is pressed.
function YToolButton:is_pressed()
  return (self._popup_menu and self._popup_menu:is_open()) or YPushButton.is_pressed(self)
end
function YToolButton:_cancel()
  if self._popup_menu then self._popup_menu:close() end
  return YPushButton._cancel(self)
end
---Open an attached menu on left press or focused Enter/Space; otherwise use command gestures.
---@param kind string Input event kind.
---@param row integer Host-relative row.
---@param col integer Host-relative display column.
---@param button integer Pointer button.
---@param key string Normalized key.
---@param mods? any Modifier state.
---@param pos? table Native pointer position.
---@return boolean accepted # True if handled.
---@return string|nil reason # Refusal reason, or nil.
function YToolButton:event(kind, row, col, button, key, mods, pos)
  local r, c, w, h = self:rect()
  local pointer = kind == "press" and button == 1 and row >= r and row < r+h and col >= c and col < c+w
  local keyboard = kind == "key" and (key == "<CR>" or key == "<Space>") and self._focus:focus_widget() == self
  if self._menu and (pointer or keyboard) then
    if self:is_destroyed() or not self:is_visible() or not self:is_enabled() then return false end
    self:_cancel()
    local opened, reason = self._menu:popup_anchored(self)
    if opened and pointer then self._menu._opening_pointer = {row=row, col=col, pos=pos} end
    if not opened and pointer then self._dispatcher:_swallow_gesture(button) end
    return true, reason
  end
  return YPushButton.event(self, kind, row, col, button, key)
end
function YToolButton:_dispose()
  self:_cancel()
  if self._menu and self._menu_connection then self._menu:disconnect(self._menu_connection) end
  self._menu, self._menu_connection = nil, nil
  YPushButton._dispose(self)
end
---Choose tool_button or button appearance and request paint on a change.
---@param value boolean True selects tool_button appearance.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YToolButton:set_auto_raise(value)
  YObject.boolean(value)
  if self:is_destroyed() then return false, "destroyed" end
  if self._auto_raise == value then return false end
  self._auto_raise = value; self:update(); return true
end
return YToolButton
