-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-FileCopyrightText: 2016 The Qt Company Ltd
-- SPDX-License-Identifier: LGPL-3.0-only
-- Derived from Qt src/widgets/widgets/qtoolbutton.cpp:344-346 (qtbase v6.8.3).
-- Derived from Qt src/widgets/widgets/qtoolbarlayout.cpp:348-398,446-485 (qtbase v6.8.3).
-- Modified: Lua/Neovim adaptation by Usman Bashir; notice added 2026-10-08.
-- WIDGETS BTN-B: one ordered partition; YBoxLayout owns child rectangles.
local YWidget = require("yana_ui.widget")
local YPushButton = require("yana_ui.push_button")
local YToolButton = require("yana_ui.tool_button")
local YMenu = require("yana_ui.menu")
local YBoxLayout = require("yana_ui.box_layout")
local YLayout = require("yana_ui.layout")
local YPaintWriter = require("yana_ui.paint_writer")
local YTextMetrics = require("yana_ui.text_metrics")
---@class YToolBarOptions : YControlOptions
---@field actions? YAction[] [default: {}] Dense ordered array of distinct live borrowed actions.
---@field spacing? integer [default: 1] Nonnegative cell gap between buttons.
---@class YToolBar : YWidget
---@doc brief An ordered action strip with owned tool buttons and a suffix overflow menu.
---@doc qt QToolBar. This is a one-row cell control, not a movable or dockable native toolbar. Actions stay borrowed; YBoxLayout assigns button rectangles and a trailing extension opens a flat YMenu.
---@doc inherits |YWidget|; inherited properties and methods retain |YWidget| semantics. The constructor accepts parent and the listed control options, not YWidget callback or size options; minimum starts at 0x1 and maximum at 2147483647x1.
---@doc property actions|actions()|add_action(action), insert_action(before, action), remove_action(action), clear()|none|option:actions
---@doc property visible_actions|visible_actions()|none|none|{}
---@doc property overflow_actions|overflow_actions()|none|none|option:actions
---@doc property overflow_menu|overflow_menu()|none|none|owned YMenu
---@doc property spacing|spacing()|set_spacing(value)|none|option:spacing
---@signal action_triggered(action: YAction) | Forwarded during a member action's triggered emission, including external triggering and overflow selection. Action toggling precedes it; relative order with other listeners follows connection order. Removing membership disconnects forwarding.
---@doc errors Owners must satisfy YControlOptions; actions must be a dense array of distinct live YAction objects. Spacing uses YLayout's nonnegative integer validation. Invalid setter/action values raise before the destroyed check. Callback errors propagate; action getters return copies rather than mutable internal arrays.
---@doc destroyed set_spacing,insert_action,add_action,remove_action,clear,open_overflow,open_menu,prepare,update
---@doc exception prepare() also refuses a destroyed writer; prepare() and open_overflow() return a stale-target reason. Inherited getters stay readable; effective visible/enabled become false after destruction.
---@doc context lua/yana_ui/tool_bar.lua|YToolBar
---@doc setup Run this block in Neovim with yana-ui on runtimepath. It creates and removes its own canvas/float and manages borrowed actions without drawing a frame.
-- DOCS: YToolBar example start
---@doc example local ui = require("yana_ui")
---@doc example local owner = ui.YObject.new(); local root = ui.YWidget.new({ parent = owner })
---@doc example local buf = vim.api.nvim_create_buf(false, true)
---@doc example local win = vim.api.nvim_open_win(buf, false, { relative = "editor", row = 0, col = 0, width = 20, height = 1, style = "minimal" })
---@doc example local target = function() return win, buf, 1 end
---@doc example local focus = ui.YFocus.new({ parent = owner, current_target = target }); local style = ui.YStyle.new({ focus = focus })
---@doc example local writer = ui.YPaintWriter.new({ parent = owner, win = win, buf = buf, generation = 1, current_target = target })
---@doc example local dispatcher = ui.YEventDispatcher.new({ parent = owner, root = root, focus = focus, writer = writer, current_target = target })
---@doc example local action = ui.YAction.new({ parent = owner, label = "Run" })
---@doc example local bar = ui.YToolBar.new({ parent = root, style = style, focus = focus, dispatcher = dispatcher, current_target = target, actions = { action } })
---@doc example assert(bar:widget_for_action(action):action() == action)
---@doc example assert(bar:remove_action(action)); assert(not action:is_destroyed())
---@doc example owner:destroy()
---@doc example if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
---@doc example if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
-- DOCS: YToolBar example end
---@doc see |YAction|, |YToolButton|, |YMenu|, |YBoxLayout|, |yana-ui-tutorial-toolbar|.
local YToolBar = setmetatable({}, { __index = YWidget })
YToolBar.__index = YToolBar
local function copy(values) local out = {}; for i, value in ipairs(values) do out[i] = value end; return out end
local function index(self, action) for i, value in ipairs(self._actions) do if value == action then return i end end end
local function options(self, parent)
  return { parent = parent, style = self._style, focus = self._focus, dispatcher = self._dispatcher, current_target = self._target }
end
---Create the strip, its layout, buttons, extension and overflow menu.
---All supplied actions are borrowed and retain their existing parent.
---@param opts YToolBarOptions Required constructor options.
---@return YToolBar toolbar # New unshown one-row strip.
function YToolBar.new(opts)
  YPushButton._owners(opts); YMenu._validate_actions(opts.actions == nil and {} or opts.actions)
  YLayout.integer(opts.spacing == nil and 1 or opts.spacing)
  local self = setmetatable(YWidget.new({ parent = opts.parent,
    size_hint = { width = 0, height = 1 }, minimum_size_hint = { width = 0, height = 1 },
    maximum_size = { width = 2147483647, height = 1 } }), YToolBar)
  self._style, self._focus, self._dispatcher, self._target = opts.style, opts.focus, opts.dispatcher, opts.current_target
  self._actions, self._buttons, self._connections, self._visible, self._overflow = {}, {}, {}, {}, {}
  self._spacing = opts.spacing == nil and 1 or opts.spacing
  self._menu = YMenu.new(options(self, self))
  local extension = options(self, self); extension.icon, extension.auto_raise = "»", true
  self._extension = YToolButton.new(extension)
  self._extension._toolbar, self._extension._pointer_focus_disabled = self, true
  self._extension:set_menu(self._menu)
  self._menu._overflow_toolbar = self
  local box = YBoxLayout.new({ parent = self, spacing = self._spacing })
  function box:_collect(row, col, width, height, plan)
    self:parent():_partition(width)
    return self:parent():_collect_controls(row, col, width, height, plan)
  end
  self:set_layout(box)
  self._style:attach(self)
  for _, action in ipairs(opts.actions or {}) do self:add_action(action) end
  self:_structure()
  return self
end
---Read an action list; editing this copy does not change the toolbar.
---@return YAction[] actions # Copy of all actions in toolbar order.
function YToolBar:actions() return copy(self._actions) end
---Read an action list; editing this copy does not change the toolbar.
---@return YAction[] actions # Copy of the prefix admitted by the latest allocation/preparation.
function YToolBar:visible_actions() return copy(self._visible) end
---Read an action list; editing this copy does not change the toolbar.
---@return YAction[] actions # Copy of the remaining suffix, in toolbar order.
function YToolBar:overflow_actions() return copy(self._overflow) end
---Read the menu owned by this toolbar; it borrows the overflow actions.
---@return YMenu menu # Toolbar-owned overflow menu.
function YToolBar:overflow_menu() return self._menu end
---Find the owned tool button for a member action; a nonmember returns nil.
---@param action YAction Action to look up.
---@return YToolButton|nil button # Member presentation, or nil.
function YToolBar:widget_for_action(action) return self._buttons[action] end
---Read the stored cell gap between buttons.
---@return integer spacing # Nonnegative cell spacing.
function YToolBar:spacing() return self._spacing end
---Change spacing and rebuild the partition; this closes any overflow popup.
---@param value integer Nonnegative cell spacing.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YToolBar:set_spacing(value)
  YLayout.integer(value)
  if self:is_destroyed() then return false, "destroyed" end
  if value == self._spacing then return false end
  self._spacing = value; self._layout:set_spacing(value); self:_structure(); return true
end
---Insert or move a live action before another member; nil appends. A new
---member gets an owned tool button; moving a member preserves its button.
---A nonmember before raises an assertion. Structural changes close overflow.
---@param before? YAction [default: nil] Live member to insert before; nil appends.
---@param action YAction Live action to insert or move.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YToolBar:insert_action(before, action)
  YPushButton._action(action)
  if before ~= nil then YPushButton._action(before); assert(index(self, before), "foreign before YAction") end
  if self:is_destroyed() then return false, "destroyed" end
  if before == action then return false end
  local old = index(self, action)
  if old then
    local destination = before and index(self, before) or #self._actions + 1
    if old + 1 == destination then return false end
    table.remove(self._actions, old)
  else
    local opts = options(self, self); opts.action, opts.auto_raise = action, true
    local button = YToolButton.new(opts)
    button._toolbar, button._pointer_focus_disabled = self, true
    -- FIX-4: Qt src/widgets/widgets/qtoolbutton.cpp:344-346.
    local width = button:size_hint(); button:set_minimum_size_hint(width, 1); button:set_maximum_size(width, 1)
    self._buttons[action] = button
    self._connections[action] = {
      action:connect("triggered", self, function(bar)
        if index(bar, action) then bar:emit("action_triggered", action) end
      end),
      action:connect("destroyed", self, function(bar) bar:remove_action(action) end),
      action:connect("label_changed", self, function(bar)
        local width = button:size_hint()
        button:set_minimum_size_hint(width, 1); button:set_maximum_size(width, 1)
        local hint = 0
        for i, member in ipairs(bar._actions) do
          hint = hint + bar._buttons[member]:size_hint() + (i > 1 and bar._spacing or 0)
        end
        bar:set_size_hint(hint, 1)
        bar._partition_width, bar._cold_dirty = nil, true
        local row, col, extent, height = bar:rect()
        local _, _, generation = bar._target()
        bar._layout:activate(row, col, extent, height, generation)
        bar:update()
      end),
    }
  end
  table.insert(self._actions, before and index(self, before) or #self._actions + 1, action)
  self:_structure()
  return true
end
---Append or move an action to the end through insert_action(nil, action).
---@param action YAction Live action to append.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YToolBar:add_action(action) return self:insert_action(nil, action) end
---Remove a member and destroy its button, leaving the action alive. A
---destroyed YAction is accepted; a non-YAction raises an assertion. Action
---destruction also removes membership automatically. Changes close overflow.
---@param action YAction Member to remove; may already be destroyed.
---@return boolean changed # True when removed; false if absent or toolbar destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YToolBar:remove_action(action)
  assert(require("yana_ui.object").is_instance(action) and getmetatable(action) == require("yana_ui.action"), "expected YAction")
  if self:is_destroyed() then return false, "destroyed" end
  local i = index(self, action); if not i then return false end
  table.remove(self._actions, i)
  for _, token in ipairs(self._connections[action]) do action:disconnect(token) end
  self._connections[action] = nil
  self._buttons[action]:destroy(); self._buttons[action] = nil
  self:_structure(); return true
end
---Remove all memberships and owned buttons; borrowed actions survive.
---@return boolean changed # True when cleared; false if empty or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YToolBar:clear()
  if self:is_destroyed() then return false, "destroyed" end
  if #self._actions == 0 then return false end
  for _, action in ipairs(self:actions()) do self:remove_action(action) end
  return true
end
function YToolBar:_structure()
  self._menu:close()
  while self._layout:count() > 0 do self._layout:take_at(0) end
  local hint = 0
  for i, action in ipairs(self._actions) do
    local button = self._buttons[action]
    hint = hint + button:size_hint() + (i > 1 and self._spacing or 0)
    self._layout:add_widget(button)
  end
  -- FIX-4: Qt src/widgets/widgets/qtoolbarlayout.cpp:470-485.
  self._layout:add_stretch(0)
  self:set_size_hint(hint, 1)
  self._partition_width = nil
  local row, col, width, height = self:rect(); self:_partition(width)
  local _, _, generation = self._target()
  self._layout:activate(row, col, width, height, generation)
  if self._prepared_writer then self:prepare(self._prepared_writer) end
  self:update()
end
function YToolBar:_partition(width)
  if self._partition_width == width then return end
  self._partition_width = width
  -- FIX-4: Qt src/widgets/widgets/qtoolbarlayout.cpp:446-467:
  -- admit the first item, stop at the next non-fitting item, then reserve
  -- the extension by moving the last admitted item only if there were two.
  local count, used = 0, 0
  for i, action in ipairs(self._actions) do
    local next_width = used + (i > 1 and self._spacing or 0) + self._buttons[action]:minimum_size_hint()
    if i > 1 and next_width > width then
      if count > 1 and used + self._spacing + 3 > width then count = count - 1 end
      break
    end
    used, count = next_width, i
  end
  -- A cell canvas cannot expose a first control when reservation consumes it.
  if count < #self._actions and width <= 3 + self._spacing then count = 0 end
  self._visible, self._overflow = {}, {}
  for i, action in ipairs(self._actions) do
    local visible = i <= count
    self._buttons[action]:set_visible(visible)
    local values = visible and self._visible or self._overflow
    values[#values + 1] = action
  end
  local overflow = count < #self._actions
  self._extension:set_visible(overflow and width > 0)
  local extension_width = math.min(3, width)
  self._extension:set_minimum_size_hint(extension_width, 1)
  self._extension:set_size_hint(extension_width, 1)
  self._extension:set_maximum_size(extension_width, 1)
  local existing = self._menu:actions()
  if not vim.deep_equal(existing, self._overflow) then
    self._menu:clear()
    for _, action in ipairs(self._overflow) do self._menu:add_action(action) end
  end
  self._cold_dirty = true
end
function YToolBar:_collect_controls(row, col, width, height, plan)
  -- FIX-4: Qt src/widgets/widgets/qtoolbarlayout.cpp:348-398,483-485:
  -- allocate the prefix with its trailing stretch; place extension separately.
  local overflow = self._extension:is_visible()
  local extent = overflow and math.min(3, width) or 0
  YBoxLayout._collect(self._layout, row, col,
    math.max(0, width - extent - (overflow and self._spacing or 0)), height, plan)
  if overflow then plan[#plan + 1] = { widget = self._extension, rect = { row, col + width - extent, extent, math.min(1, height) } } end
end
---Open the suffix menu below the extension. Refuse without overflow, when
---hidden/disabled, with no extension width, or when the current host is stale.
---@return boolean opened # True when popup succeeds; false on refusal.
---@return string|nil reason # "destroyed" for a dead toolbar, "stale" for an invalid host, or a forwarded popup reason; nil on ordinary refusal.
function YToolBar:open_overflow()
  if self:is_destroyed() then return false, "destroyed" end
  if #self._overflow == 0 or not self:is_visible() or not self:is_enabled() then return false end
  local win, buf = self._target()
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then return false, "stale" end
  local r, c, w = self._extension:rect()
  if w == 0 then return false end
  return self._menu:popup_anchored(self._extension)
end
---Open a member's attached menu using its visible button or the overflow extension.
---A live nonmember raises; a disabled toolbar/action or absent menu refuses.
---@param action YAction Live member action with an attached menu.
---@return boolean opened # True when shown; false on refusal.
---@return string|nil reason # Destruction or forwarded popup refusal; nil otherwise.
function YToolBar:open_menu(action)
  YPushButton._action(action)
  if self:is_destroyed() then return false, "destroyed" end
  local button = assert(self._buttons[action], "foreign toolbar action")
  if not self:is_visible() or not self:is_enabled() or not action:is_enabled() or not button:menu() then return false end
  self._menu:close()
  for _, member in ipairs(self._actions) do
    local menu = self._buttons[member]:menu()
    if menu then menu:close() end
  end
  return button:menu():popup_anchored(button:is_visible() and button or self._extension)
end
---Partition the assigned width and prepare the strip and button rows.
---Tiny widths keep nonnegative rectangles; changing the partition closes an
---open overflow popup. A non-YPaintWriter raises before the destroyed check.
---@param writer YPaintWriter Writer for the current window, buffer and generation.
---@return boolean prepared # True after preparation; false on refusal.
---@return string|nil reason # "destroyed" for a dead toolbar/writer, "stale" for target mismatch, or a forwarded writer reason.
function YToolBar:prepare(writer)
  assert(YPaintWriter.is_instance(writer), "expected YPaintWriter")
  if self:is_destroyed() or writer:is_destroyed() then return false, "destroyed" end
  local win, buf, gen = self._target()
  if win ~= writer._win or buf ~= writer._buf or gen ~= writer._generation then return false, "stale" end
  local row, col, width = self:rect()
  self:_partition(width)
  -- Read the private YLayout's calculation; only YLayout publishes rectangles.
  local plan = {}
  self:_collect_controls(row, col, width, 1, plan)
  local text, cursor = "", 0
  for _, item in ipairs(plan) do
    local start, cells = item.rect[2] - col, item.rect[3]
    text = text .. string.rep(" ", math.max(0, start - cursor))
      .. YTextMetrics.cell_clip(" " .. YTextMetrics.elide(item.widget:_content(), math.max(0, cells - 2)) .. " ", cells)
    cursor = start + cells
  end
  text = YTextMetrics.cell_clip(text, width)
  local ok, reason = writer:prepare(self, { text }, {})
  if not ok then return ok, reason end
  self._prepared_writer, self._cold_dirty = writer, false
  for _, action in ipairs(self._actions) do self._buttons[action]:prepare(writer) end
  self._extension:prepare(writer)
  return true
end
---Reprepare structural changes with the attached writer, then request paint.
---@return boolean changed # True when requested; false if destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YToolBar:update()
  if self._prepared_writer and not self:is_destroyed() and self._cold_dirty then self:prepare(self._prepared_writer) end
  return YWidget.update(self)
end
function YToolBar:_dispose()
  for action, tokens in pairs(self._connections) do for _, token in ipairs(tokens) do action:disconnect(token) end end
end
return YToolBar
