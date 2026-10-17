-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- WIDGETS BTN-P: borrowed YAction state; YEventDispatcher/YWidget owns pointer appearance.
local YWidget = require("yana_ui.widget")
local YObject = require("yana_ui.object")
local YAction = require("yana_ui.action")
local YFocus = require("yana_ui.focus")
local YStyle = require("yana_ui.style")
local YPaintWriter = require("yana_ui.paint_writer")
local YTextMetrics = require("yana_ui.text_metrics")
---@class YControlOptions : YObjectOptions
---@field style YStyle Shared style; must be a YStyle instance.
---@field focus YFocus Live shared focus owner.
---@field dispatcher YEventDispatcher Live shared input owner with dispatch().
---@field current_target fun(): integer, integer, integer Returns current window, buffer and generation.
---@class YPushButtonOptions : YControlOptions
---@field action? YAction [default: nil] Borrowed live command; owns label, tooltip, checkable and checked when supplied.
---@field label? string [default: ""] Standalone button text; omit with action.
---@field icon? string [default: ""] Single-line icon displayed before the label.
---@field tooltip? string [default: ""] Delayed native tooltip text; omit with action.
---@field tooltip_delay? integer [default: 700] Consumer-set hover delay in milliseconds; nil uses the style hint.
---@field checkable? boolean [default: false] Standalone tick support; omit with action.
---@field checked? boolean [default: false] Initial standalone tick; requires checkable=true; omit with action.
---@class YPushButton : YWidget
---@doc brief A one-row button using a shared action or its own command state.
---@doc qt QPushButton. Enter and Space activate the focused control; click() invokes it directly. Nonempty tooltip text uses an internal non-focusable float after tooltip_delay, cancelled by target, gesture, popup or lifetime changes. No default-button or auto-repeat is provided. With an action, action toggling and triggering precede released and clicked.
---@doc inherits |YWidget|; inherited properties, methods and pointer_target_changed retain |YWidget| semantics. The constructor accepts parent and the listed control options, not YWidget callback or size options; initial minimum is 2x1 and maximum is 2147483647x1.
---@doc property action|action()|set_action(action)|none|option:action
---@doc property label|label()|set_label(value)|none|option:label
---@doc property tooltip|tooltip()|set_tooltip(value)|none|option:tooltip
---@doc property tooltip_delay|tooltip_delay()|set_tooltip_delay(value)|none|option:tooltip_delay
---@doc property icon|icon()|set_icon(value)|none|option:icon
---@doc property checkable|is_checkable()|set_checkable(value)|none|option:checkable
---@doc property checked|is_checked()|set_checked(value), toggle()|toggled|option:checked
---@doc property enabled|is_enabled()|set_enabled(value)|pointer_target_changed (local state only)|true, further constrained by ancestors and action
---@doc property visible|is_visible()|set_visible(value), show(), hide()|pointer_target_changed|false (unshown)
---@signal pressed() | Emitted when a press is armed, when a held pointer re-enters, or by click() before activation.
---@signal released() | Emitted when a held pointer leaves or a press is cancelled. Successful activation emits it after toggled and action.triggered, before clicked; callbacks may cancel the remaining sequence.
---@signal toggled(checked: boolean) | Emitted after a standalone checked change, or forwarded synchronously from the action. Making a standalone button non-checkable clears its tick without this signal.
---@signal clicked(checked: boolean) | Emitted after released on successful activation; false for non-checkable buttons. Destruction, disabling or gesture replacement in a callback can suppress it.
---@doc errors Text options/setters require single-line UTF-8 strings without CR, LF or NUL; boolean options/setters require booleans. Action arguments must be live YAction objects, except nil in set_action(). These checks raise before the destroyed check. Owner and parent validation is shared with YControlOptions; callback errors propagate.
---@doc destroyed set_action,set_label,set_icon,set_tooltip,set_tooltip_delay,set_checkable,set_checked,toggle,set_enabled,set_visible,click,event,prepare,update,paint
---@doc exception set_label() and set_tooltip() return false, "action-owned" while attached to an action. prepare() also refuses a destroyed writer or stale target. click() can return false without a reason if a callback destroys the button; getters remain readable except effective enabled becomes false.
---@doc context lua/yana_ui/push_button.lua|YPushButton
---@doc setup Run this block in Neovim with yana-ui on runtimepath. It creates and cleans up its canvas and float; it tests command state without flushing a frame.
-- DOCS: YPushButton example start
---@doc example local ui = require("yana_ui")
---@doc example local owner = ui.YObject.new(); local root = ui.YWidget.new({ parent = owner })
---@doc example local buf = vim.api.nvim_create_buf(false, true)
---@doc example local win = vim.api.nvim_open_win(buf, false, { relative = "editor", row = 0, col = 0, width = 20, height = 1, style = "minimal" })
---@doc example local target = function() return win, buf, 1 end
---@doc example local focus = ui.YFocus.new({ parent = owner, current_target = target }); local style = ui.YStyle.new({ focus = focus })
---@doc example local writer = ui.YPaintWriter.new({ parent = owner, win = win, buf = buf, generation = 1, current_target = target })
---@doc example local dispatcher = ui.YEventDispatcher.new({ parent = owner, root = root, focus = focus, writer = writer, current_target = target })
---@doc example local button = ui.YPushButton.new({ parent = root, style = style, focus = focus, dispatcher = dispatcher, current_target = target, label = "Pin", checkable = true })
---@doc example button:connect("toggled", owner, function(_, checked) print("Pinned: " .. tostring(checked)) end)
---@doc example assert(button:set_checked(true)); assert(button:is_checked())
---@doc example owner:destroy()
---@doc example if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
---@doc example if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
-- DOCS: YPushButton example end
---@doc see |YAction|, |YToolButton|, |yana-ui-howto-disable-button|, |yana-ui-tutorial-toolbar|.
local YPushButton = setmetatable({}, { __index = YWidget })
YPushButton.__index = YPushButton
local instances = setmetatable({}, { __mode = "k" })
---Recognize allocated push-button identities, including tool buttons and
---destroyed buttons.
---@param value any Value to inspect.
---@return boolean instance # True for a push-button identity.
function YPushButton.is_instance(value) return instances[value] == true end
function YPushButton._text(value)
  assert(type(value) == "string" and not value:find("[\r\n%z]"), "expected single-line text")
  assert(pcall(vim.str_utfindex, value, "utf-32"), "invalid UTF-8 text")
  return value
end
function YPushButton._action(value)
  assert(YObject.is_instance(value) and getmetatable(value) == YAction and not value:is_destroyed(), "expected live YAction")
end
function YPushButton._owners(opts)
  assert(type(opts) == "table" and getmetatable(opts.style) == YStyle
    and YFocus.is_instance(opts.focus) and not opts.focus:is_destroyed()
    and YObject.is_instance(opts.dispatcher) and not opts.dispatcher:is_destroyed()
    and type(opts.dispatcher.dispatch) == "function" and type(opts.current_target) == "function", "invalid widget owners")
  if opts.parent ~= nil then assert(YObject.is_instance(opts.parent) and not opts.parent:is_destroyed(), "invalid parent") end
end
function YPushButton:_content()
  local icon, label = self:icon(), self:label()
  return icon .. (icon ~= "" and label ~= "" and " " or "") .. label
end
function YPushButton:_appearance()
  local mask = self._style:state(self, self:is_checked(), false)
  return self._style:appearance(self._auto_raise and "tool_button" or "button", mask, "active")
end
function YPushButton:_cold()
  self:set_size_hint(YTextMetrics.width(self:_content()) + 2, 1)
  if self._prepared_writer and not self._preparing then return self:prepare(self._prepared_writer) end
  return true
end
---Create an unshown button. Options are required; style, focus, dispatcher
---and current_target must satisfy the shared control options. With an action,
---supplying label, tooltip, checkable or checked raises an assertion. Standalone
---checked=true requires checkable=true. The action is borrowed, not reparented.
---@param opts YPushButtonOptions Required constructor options.
---@return YPushButton button # New button.
function YPushButton.new(opts)
  YPushButton._owners(opts)
  for _, key in ipairs({ "label", "icon", "tooltip" }) do if opts[key] ~= nil then YPushButton._text(opts[key]) end end
  if opts.tooltip_delay ~= nil then assert(type(opts.tooltip_delay) == "number" and opts.tooltip_delay >= 0
    and opts.tooltip_delay <= 2147483647 and opts.tooltip_delay == math.floor(opts.tooltip_delay), "invalid tooltip delay") end
  for _, key in ipairs({ "checkable", "checked" }) do if opts[key] ~= nil then YObject.boolean(opts[key]) end end
  if opts.action ~= nil then
    YPushButton._action(opts.action)
    for _, key in ipairs({ "label", "tooltip", "checkable", "checked" }) do assert(opts[key] == nil, "YAction owns " .. key) end
  else assert(opts.checked ~= true or opts.checkable == true, "checked requires checkable") end
  local self = setmetatable(YWidget.new({ parent = opts.parent,
    size_hint = { width = 2, height = 1 }, minimum_size_hint = { width = 2, height = 1 },
    maximum_size = { width = 2147483647, height = 1 } }), YPushButton)
  instances[self] = true
  self._style, self._focus, self._dispatcher, self._target = opts.style, opts.focus, opts.dispatcher, opts.current_target
  self._icon, self._label, self._tooltip = opts.icon or "", opts.label or "", opts.tooltip or ""
  self._tooltip_delay = opts.tooltip_delay
  self._checkable, self._checked, self._epoch = opts.checkable == true, opts.checked == true, 0
  self._style:attach(self)
  if opts.action then self:set_action(opts.action) end
  self:_cold()
  return self
end
---Read the current property value.
---@return YAction|nil value # Borrowed action, or nil for standalone state.
function YPushButton:action() return self._action_owner end
---Read the current property value.
---@return string value # Action label or standalone text.
function YPushButton:label() return self._action_owner and self._action_owner:label() or self._label end
---Read the current property value.
---@return string value # Action tooltip or standalone tooltip.
function YPushButton:tooltip() return self._action_owner and self._action_owner:tooltip() or self._tooltip end
---Read the consumer delay, falling back to the style's native hint.
---@return integer milliseconds # Tooltip hover delay.
function YPushButton:tooltip_delay() return self._tooltip_delay or self._style:style_hint("tooltip_wake_up_delay") end
---Set the presentation's hover delay; an action does not own this value.
---@param milliseconds integer Nonnegative integer delay no greater than 2147483647.
---@return boolean changed # True on change, false when unchanged or destroyed.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YPushButton:set_tooltip_delay(milliseconds)
  assert(type(milliseconds) == "number" and milliseconds >= 0 and milliseconds <= 2147483647
    and milliseconds == math.floor(milliseconds), "invalid tooltip delay")
  if self:is_destroyed() then return false,"destroyed" end
  if self._tooltip_delay == milliseconds then return false end
  self._tooltip_delay = milliseconds; self:update(); return true
end
---Read the current property value.
---@return string value # Button-owned icon.
function YPushButton:icon() return self._icon end
---Read the current property value.
---@return boolean value # Current action or standalone checkable state.
function YPushButton:is_checkable() return self._action_owner and self._action_owner:is_checkable() or self._checkable == true end
---Read the current property value.
---@return boolean value # Tick; false when not checkable.
function YPushButton:is_checked()
  if self._action_owner then return self._action_owner:is_checked() end
  return self._checkable and self._checked
end
---Read the current property value.
---@return boolean value # True only when the widget and any action are enabled and live.
function YPushButton:is_enabled()
  return YWidget.is_enabled(self) and (not self._action_owner or
    (not self._action_owner:is_destroyed() and self._action_owner:is_enabled()))
end
function YPushButton:_cancel()
  local armed = self._armed
  self._armed, self._epoch = nil, self._epoch + 1
  local epoch = self._epoch
  self._dispatcher:_cancel_grab(self)
  if armed and armed.down and not self:is_destroyed() then self:emit("released") end
  return epoch
end
function YPushButton:_grab_cancelled()
  if self._armed then self:_cancel() end
end
---Attach a borrowed action and cancel any current press. Nil detaches and
---copies the previous action's label, tooltip, checkable and visible tick into
---standalone state; the icon stays button-owned. Rebinding during a released
---callback can cancel this change. A destroyed action disables the button.
---@param action? YAction [default: nil] Live action, or nil to detach.
---@return boolean changed # True on attachment change; false if unchanged, destroyed or superseded.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YPushButton:set_action(action)
  if action ~= nil then YPushButton._action(action) end
  if self:is_destroyed() then return false, "destroyed" end
  if self._action_owner == action then return false end
  local epoch = self:_cancel()
  if self:is_destroyed() then return false, "destroyed" end
  if self._epoch ~= epoch then return false end
  local previous = self._action_owner
  if previous then
    if action == nil then
      self._label, self._tooltip = previous:label(), previous:tooltip()
      self._checkable, self._checked = previous:is_checkable(), previous:is_checked()
    end
    for _, token in ipairs(self._action_connections) do previous:disconnect(token) end
  end
  self._action_owner, self._action_connections = action, {}
  if action then
    self._label, self._tooltip, self._checkable, self._checked = nil, nil, nil, nil
    local function connect(name, slot)
      self._action_connections[#self._action_connections + 1] = action:connect(name, self, slot)
    end
    connect("toggled", function(button, checked) button:update(); button:emit("toggled", checked) end)
    connect("checkable_changed", function(button) button:update() end)
    connect("label_changed", function(button) button:_cold(); button:update() end)
    connect("enabled_changed", function(button) if not button:is_enabled() then button:_cancel() end; button:update() end)
    connect("destroyed", function(button) button:_cancel(); button:update() end)
    connect("triggered", function(button) if button._tool_button then button:emit("triggered", action) end end)
  end
  self:_cold(); self:update()
  return true
end
local function set_text(self, key, value)
  YPushButton._text(value)
  if self:is_destroyed() then return false, "destroyed" end
  if key ~= "_icon" and self._action_owner then return false, "action-owned" end
  if self[key] == value then return false end
  self[key] = value; self:_cold(); self:update(); return true
end
---Store text and refresh the size hint and prepared presentation.
---@param value string Single-line UTF-8 text.
---@return boolean changed # True on change; false if unchanged, action-owned or destroyed.
---@return "destroyed"|"action-owned"|nil reason # "destroyed" when dead; "action-owned" while attached; nil otherwise.
function YPushButton:set_label(value) return set_text(self, "_label", value) end
---Store text and refresh the size hint and prepared presentation.
---@param value string Single-line UTF-8 text.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YPushButton:set_icon(value) return set_text(self, "_icon", value) end
---Store text and refresh the size hint and prepared presentation.
---@param value string Single-line UTF-8 text.
---@return boolean changed # True on change; false if unchanged, action-owned or destroyed.
---@return "destroyed"|"action-owned"|nil reason # "destroyed" when dead; "action-owned" while attached; nil otherwise.
function YPushButton:set_tooltip(value) return set_text(self, "_tooltip", value) end
---Forward to the action when attached. Standalone changes clear the tick
---without emitting toggled; an unchanged value preserves the tick.
---@param value boolean Whether a tick is supported.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" for a dead button or attached action; nil otherwise.
function YPushButton:set_checkable(value)
  YObject.boolean(value)
  if self:is_destroyed() then return false, "destroyed" end
  if self._action_owner then return self._action_owner:set_checkable(value) end
  if self._checkable == value then return false end
  self._checkable, self._checked = value, false; self:update(); return true
end
---Forward to the action when attached; otherwise change a checkable tick
---and emit toggled. A standalone non-checkable button refuses with false.
---@param value boolean New tick.
---@return boolean changed # True on change; false if unchanged, standalone non-checkable or destroyed.
---@return "destroyed"|nil reason # "destroyed" for a dead button or attached action; nil otherwise.
function YPushButton:set_checked(value)
  YObject.boolean(value)
  if self:is_destroyed() then return false, "destroyed" end
  if self._action_owner then return self._action_owner:set_checked(value) end
  if not self._checkable or self._checked == value then return false end
  self._checked = value; self:update(); self:emit("toggled", value); return true
end
---Invert the action's stored tick or this button's standalone tick.
---@return boolean changed # True on change; false if standalone non-checkable or destroyed.
---@return "destroyed"|nil reason # "destroyed" for a dead button or attached action; nil otherwise.
function YPushButton:toggle()
  if self:is_destroyed() then return false, "destroyed" end
  if self._action_owner then return self._action_owner:toggle() end
  return self:set_checked(not self._checked)
end
---Set local enabled through YWidget; false also cancels any held press.
---@param value boolean New local state.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YPushButton:set_enabled(value)
  YObject.boolean(value)
  if self:is_destroyed() then return false, "destroyed" end
  local changed = YWidget.set_enabled(self, value)
  if not value then self:_cancel() end
  return changed
end
---Set local visibility through YWidget; false also cancels any held press.
---@param value boolean New local state.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YPushButton:set_visible(value)
  YObject.boolean(value)
  if self:is_destroyed() then return false, "destroyed" end
  local changed = YWidget.set_visible(self, value)
  if not value then self:_cancel() end
  return changed
end
local function still(self, epoch)
  return not self:is_destroyed() and self._epoch == epoch and self:is_enabled()
end
function YPushButton:_activate(epoch)
  if not still(self, epoch) then return false end
  if self._action_owner then self._action_owner:trigger()
  elseif self:is_checkable() then self:set_checked(not self:is_checked()) end
  if not still(self, epoch) then return false end
  self._dispatcher:_button_state(self, false)
  self:emit("released")
  if not still(self, epoch) then return false end
  self:emit("clicked", self:is_checkable() and self:is_checked() or false)
  return true
end
---Activate an enabled button directly, even if hidden. Emit pressed, then
---follow the signal ordering above; callbacks may cancel activation.
---@return boolean clicked # True after clicked; false if disabled, destroyed or cancelled.
---@return "destroyed"|nil reason # "destroyed" only when dead on entry; nil otherwise.
function YPushButton:click()
  if self:is_destroyed() then return false, "destroyed" end
  if not self:is_enabled() then return false end
  self:_cancel()
  local epoch = self._epoch
  self._dispatcher:_button_state(self, true)
  self:emit("pressed")
  if not still(self, epoch) then self._dispatcher:_button_state(self, false); return false end
  return self:_activate(epoch)
end
local function inside(self, row, col)
  local r, c, w, h = self:rect()
  return row >= r and col >= c and row < r + h and col < c + w
end
---Handle focused Enter/Space or a left-button gesture inside the visible rectangle.
---A held pointer leaving/re-entering changes released/pressed; release outside
---cancels activation. Pass this through YEventDispatcher for pointer state.
---@param kind string Event kind: key, press, move, leave, enter or release.
---@param row integer Zero-based canvas row.
---@param col integer Zero-based canvas display column.
---@param button integer Mouse button; 1 selects the left button.
---@param key string Normalized key, including <CR> and <Space>.
---@return boolean accepted # True when handled; false when ignored, cancelled or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead on entry; nil otherwise.
function YPushButton:event(kind, row, col, button, key)
  if self:is_destroyed() then return false, "destroyed" end
  if kind == "key" then
    if key == '<Esc>' and self._armed then self:_cancel();return true end
    if (key == "<Space>" or key == "<CR>") and self._focus:focus_widget() == self then return self:click() end
    return false
  end
  if kind == "press" and button == 1 and self:is_visible() and self:is_enabled() and inside(self, row, col) then
    if not self._pointer_focus_disabled and not self._focus:set_focus(self, "pointer") then return false end
    self:_cancel()
    self._dispatcher:_arm_button(self)
    self._armed = { epoch = self._epoch, down = true }
    self:emit("pressed"); return true
  end
  local armed = self._armed
  if not armed then return false end
  if kind == "move" or kind == "leave" or kind == "enter" then
    local down = self:is_visible() and self:is_enabled() and inside(self, row, col)
    if armed.down ~= down then armed.down = down; self:emit(down and "pressed" or "released") end
    return true
  end
  if kind == "release" and button == 1 then
    self._armed = nil
    if self:is_visible() and inside(self, row, col) and still(self, armed.epoch) then return self:_activate(armed.epoch) end
    if armed.down then self:emit("released") end
    return true
  end
  return false
end
---Prepare one cell-clipped row and its highlight slot before flushing.
---A non-YPaintWriter raises an assertion before the destroyed check.
---@param writer YPaintWriter Writer for the exact current window, buffer and generation.
---@return boolean prepared # True when prepared; false on refusal.
---@return string|nil reason # "destroyed" for a dead button/writer, "stale" for target mismatch; otherwise the writer's reason.
function YPushButton:prepare(writer)
  assert(YPaintWriter.is_instance(writer), "expected YPaintWriter")
  if self:is_destroyed() or writer:is_destroyed() then return false, "destroyed" end
  local win, buf, gen = self._target()
  if win ~= writer._win or buf ~= writer._buf or gen ~= writer._generation
    or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then return false, "stale" end
  local _, _, width = self:rect()
  local text = YTextMetrics.cell_clip(" " .. YTextMetrics.elide(self:_content(), math.max(0, width - 2)) .. " ", width)
  self._slot = self._slot or self.id
  while writer._slots[self._slot] and writer._slots[self._slot].widget ~= self do self._slot = self._slot + 1 end
  local appearance = self:_appearance() or vim.api.nvim_get_hl_id_by_name("Normal")
  self._preparing = true
  local ok, reason = writer:prepare(self, { text }, {
    { slot = self._slot, row = 0, start_byte = 0, end_byte = #text, appearance = appearance } })
  self._preparing = false
  if ok then self._prepared_writer, self._prepared_width, self._prepared_text = writer, width, text end
  return ok, reason
end
---Reprepare a changed width when a writer is attached, then request paint.
---@return boolean changed # True when requested; false if destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YPushButton:update()
  if not self:is_destroyed() and self._prepared_writer then
    local _, _, width = self:rect()
    if width ~= self._prepared_width then self:prepare(self._prepared_writer) end
  end
  return YWidget.update(self)
end
---Update the prepared row's appearance. Call prepare() before the first
---flush; this method does not construct text or write a buffer directly.
---@param writer YPaintWriter Writer holding this button's prepared slot.
---@return boolean painted # True after updating appearance or when no row is prepared; false if destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YPushButton:paint(writer)
  if self:is_destroyed() then return false, "destroyed" end
  local appearance = self:_appearance() or vim.api.nvim_get_hl_id_by_name("Normal")
  if appearance and self._prepared_text and writer._slots[self._slot] then
    writer:mark(self._slot, 0, 0, #self._prepared_text, appearance)
  end
  return true
end
function YPushButton:_dispose() self:_cancel() end
return YPushButton
