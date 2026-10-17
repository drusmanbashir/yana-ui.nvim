-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-FileCopyrightText: 2020 The Qt Company Ltd
-- SPDX-License-Identifier: LGPL-3.0-only
-- Derived from Qt src/gui/kernel/qaction.cpp:834-900,1079-1106 (qtbase v6.8.3).
-- Modified: Lua/Neovim adaptation by Usman Bashir; notice added 2026-10-08.
-- WIDGETS Stage2: one command state shared by its buttons and menu rows.
local YObject = require("yana_ui.object")
---@class YActionOptions : YObjectOptions
---@field label? string [default: ""] Button and menu-row text.
---@field key? string [default: ""] Display hint only; no Neovim keymap is installed.
---@field tooltip? string [default: ""] Button and menu-row tooltip.
---@field enabled? boolean [default: true] Whether trigger() runs the command.
---@field checkable? boolean [default: false] Whether the tick is shown.
---@field checked? boolean [default: false] Keeps its tick even when not checkable.

---@class YAction : YObject
---@doc brief One command sharing its state across buttons and menu rows.
---@doc qt QAction. Direct Lua callbacks replace Qt connections; key is a display hint, not a shortcut. There is no visibility property or generic changed signal.
---@doc inherits |YObject|; inherited methods and the destroyed signal retain |YObject| semantics.
---@doc property label|label()|set_label(value)|label_changed|option:label
---@doc property key|key()|none|none|option:key
---@doc property tooltip|tooltip()|none|none|option:tooltip
---@doc property enabled|is_enabled()|set_enabled(value)|enabled_changed|option:enabled
---@doc property checkable|is_checkable()|set_checkable(value)|checkable_changed|option:checkable
---@doc property checked|is_checked()|set_checked(value), toggle()|toggled (only while checkable)|option:checked
---@signal enabled_changed(value: boolean) | Emitted after enabled changes; unchanged values emit nothing.
---@signal checkable_changed(value: boolean) | Emitted after checkable changes, before toggled; unchanged values emit nothing.
---@signal toggled(value: boolean) | Emitted when the tick changes while checkable. With a stored tick, changing checkable emits its new value after checkable_changed, unless that callback destroys the action.
---@signal triggered(checked: boolean) | Emitted by enabled trigger(), after toggled if checkable. Carries the stored tick even when not checkable. Suppressed if a toggled callback destroys the action.
---@doc errors Boolean options and setters reject non-booleans with an assertion, even after destruction. Getters remain readable.
---@signal label_changed() | Emitted after label changes; read the current label through label(). Unchanged values emit nothing; attached presentations retain the action identity.
---@doc destroyed set_label,set_enabled,set_checkable,set_checked,toggle,trigger
---@doc exception trigger() also refuses when a toggled callback destroys the action; callback errors propagate.
---@doc context examples/disable_button.lua|YAction
---@doc setup That file supplies owner, action, its button and status(). The callback disables the button while the job runs.
---@doc example local job
---@doc example action:connect("triggered", owner, function()
---@doc example   action:set_enabled(false); status("running")
---@doc example   job = vim.system({ vim.v.progpath, "--clean", "--headless",
---@doc example     "-c", "sleep 2", "-c", "qa!" }, {},
---@doc example     vim.schedule_wrap(function(result)
---@doc example       if owner:is_destroyed() then return end
---@doc example       action:set_enabled(true); status(result.code == 0 and "done" or "failed")
---@doc example       job = nil
---@doc example     end))
---@doc example end)
---@doc see |YObject|, |yana-ui-howto-disable-button|, |yana-ui-tutorial-toolbar|.
local YAction = setmetatable({}, { __index = YObject })
YAction.__index = YAction

---Create an action. Invalid option tables or non-string text fields raise
---assertions. Boolean validation follows the class note; parent validation
---uses |YObject.new()|.
---@param opts? YActionOptions [default: nil] Constructor options.
---@return YAction action # New action.
function YAction.new(opts)
  if opts == nil then opts = {} end
  assert(type(opts) == "table", "YAction options must be a table")
  for _, name in ipairs({ "label", "key", "tooltip" }) do
    assert(opts[name] == nil or type(opts[name]) == "string", name .. " must be a string")
  end
  for _, name in ipairs({ "enabled", "checkable", "checked" }) do
    if opts[name] ~= nil then YObject.boolean(opts[name]) end
  end
  local self = setmetatable(YObject.new(opts), YAction)
  self._label, self._key, self._tooltip = opts.label or "", opts.key or "", opts.tooltip or ""
  self._enabled, self._checkable = opts.enabled ~= false, opts.checkable == true
  self._checked = opts.checked == true
  return self
end

---Read the current shared label.
---@return string label # Stored label.
function YAction:label() return self._label end
---Store a label without replacing the action or its attached presentations.
---Invalid non-string values raise an assertion before lifetime checks.
---@param value string New button and menu-row text.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YAction:set_label(value)
  assert(type(value) == "string", "label must be a string")
  if self:is_destroyed() then return false, "destroyed" end
  if self._label == value then return false end
  self._label = value
  self:emit("label_changed")
  return true
end
---Read the display hint set at creation; this does not create a keymap.
---@return string key # Stored display hint.
function YAction:key() return self._key end
---Read the tooltip set at creation.
---@return string tooltip # Stored tooltip.
function YAction:tooltip() return self._tooltip end
---Read whether the action is enabled.
---@return boolean enabled # Stored enabled state.
function YAction:is_enabled() return self._enabled end
---Read whether the action is checkable.
---@return boolean checkable # Stored checkable state.
function YAction:is_checkable() return self._checkable end
---Read the tick; false when not checkable, without clearing the stored tick.
---@return boolean checked # True only when checked and checkable.
function YAction:is_checked() return self._checked and self._checkable end

---Store enabled state and emit |YAction-enabled_changed| on a change.
---@param value boolean New enabled state.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YAction:set_enabled(value)
  YObject.boolean(value)
  if self:is_destroyed() then return false, "destroyed" end
  if self._enabled == value then return false end
  self._enabled = value
  self:emit("enabled_changed", value)
  return true
end

---Change whether a tick is shown, without clearing the stored tick.
---See |YAction-checkable_changed| and |YAction-toggled| for signal ordering.
---@param value boolean New checkable state.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YAction:set_checkable(value)
  YObject.boolean(value)
  if self:is_destroyed() then return false, "destroyed" end
  if self._checkable == value then return false end
  self._checkable = value
  self:emit("checkable_changed", value)
  if not self:is_destroyed() and self._checked then self:emit("toggled", value) end
  return true
end

---Store the tick even when not checkable; emit |YAction-toggled| only
---while checkable.
---@param value boolean New stored tick.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YAction:set_checked(value)
  YObject.boolean(value)
  if self:is_destroyed() then return false, "destroyed" end
  if self._checked == value then return false end
  self._checked = value
  if self._checkable then self:emit("toggled", value) end
  return true
end

---Invert the stored tick through |YAction:set_checked()|.
---@return boolean changed # True on change; false if destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YAction:toggle() return self:set_checked(not self._checked) end

---Invoke an enabled action, toggling first if checkable. See
---|YAction-triggered| for signal arguments and ordering.
---@return boolean triggered # True after emitting; false if disabled or destroyed.
---@return "destroyed"|nil reason # "destroyed" if dead before or during toggling; nil otherwise.
function YAction:trigger()
  if self:is_destroyed() then return false, "destroyed" end
  if not self._enabled then return false end
  if self._checkable then self:toggle() end
  if self:is_destroyed() then return false, "destroyed" end
  self:emit("triggered", self._checked)
  return true
end

return YAction
