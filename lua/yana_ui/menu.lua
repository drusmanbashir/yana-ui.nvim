-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-FileCopyrightText: 2016 The Qt Company Ltd
-- SPDX-License-Identifier: LGPL-3.0-only
-- Derived from Qt src/widgets/widgets/qmenu.cpp:1119-1157,2718-2735,2921-2951,3232-3237,3298-3312,3450-3505 (qtbase v6.8.3).
-- Modified: Lua/Neovim adaptation by Usman Bashir; notice added 2026-10-08.
-- WIDGETS BTN-M: flat borrowed YAction objects, owned native popup resources.
local YWidget = require("yana_ui.widget")
local YPushButton = require("yana_ui.push_button")
local YLayout = require("yana_ui.layout")
local YPaintWriter = require("yana_ui.paint_writer")
local YTextMetrics = require("yana_ui.text_metrics")
local geometry = require("yana_ui.geometry")
local context_anchor = require("yana_ui.context_anchor")
---@class YMenuOptions : YControlOptions
---@field actions? YAction[] [default: {}] Dense ordered array of distinct live borrowed actions.
---@class YMenu : YWidget
---@doc brief A flat action popup owning its scratch buffer, float and popup input.
---@doc qt QMenu. You pass zero-based editor cells to popup(). Native buffer scrolling keeps long menus accessible; actions supply labels, ticks and key hints. There are no submenus, separators, blocking exec() or shortcut installation.
---@doc inherits |YWidget|; inherited properties and methods retain |YWidget| semantics. The constructor accepts parent and the listed control options, not YWidget callback or size options; popup() manages its own visibility and rectangle.
---@doc property actions|actions()|add_action(action), insert_action(before, action), remove_action(action), clear()|none|option:actions
---@doc property active_action|active_action()|set_active_action(action)|hovered (non-nil changes only)|nil
---@doc property open|is_open()|popup(row, col), close()|about_to_show, about_to_hide (before changes)|false
---@doc property native_target|native_target()|none|none|nil window, nil buffer, generation 0
---@signal about_to_show() | Emitted after closing any previous popup and checking the host, before creating popup resources. A callback may clear actions or destroy the menu to cancel opening; target changes cause a stale refusal.
---@signal about_to_hide() | Emitted by close() before input/focus release, selection clearing and resource removal. Destruction suppresses this ordinary signal under YObject rules; cleanup still runs.
---@signal hovered(action: YAction) | Emitted after changing to a non-nil enabled member and moving the native cursor when open. Clearing selection and unchanged selections emit nothing; popup selects the first eligible action.
---@signal triggered(action: YAction) | Forwarded during a member action's triggered emission, including external triggering. Menu activation closes the popup before triggering; a checkable action emits toggled first. Relative order with other listeners follows connection order.
---@doc errors Owners must satisfy YControlOptions; actions must be a dense array of distinct live YAction objects. Action setters require live members, except nil in set_active_action(); remove_action() also accepts destroyed actions. Invalid arguments raise before the destroyed check. Callback errors propagate; getters remain readable after destruction.
---@doc destroyed set_active_action,insert_action,add_action,remove_action,clear,paint,popup
---@doc exception popup() can return false without a reason if about_to_show destroys or empties the menu. close() returns only a boolean, including during cleanup; event() closes an invalid session and returns true even after destruction.
---@doc context lua/yana_ui/menu.lua|YMenu
---@doc setup Run this block in Neovim with yana-ui on runtimepath. It creates and removes its own host canvas/float; the menu creates and removes a separate popup.
-- DOCS: YMenu example start
---@doc example local ui = require("yana_ui")
---@doc example local owner = ui.YObject.new(); local root = ui.YWidget.new({ parent = owner })
---@doc example local buf = vim.api.nvim_create_buf(false, true)
---@doc example local win = vim.api.nvim_open_win(buf, false, { relative = "editor", row = 0, col = 0, width = 20, height = 1, style = "minimal" })
---@doc example local target = function() return win, buf, 1 end
---@doc example local focus = ui.YFocus.new({ parent = owner, current_target = function(widget) if widget.native_target then return widget:native_target() end return target() end }); local style = ui.YStyle.new({ focus = focus })
---@doc example local writer = ui.YPaintWriter.new({ parent = owner, win = win, buf = buf, generation = 1, current_target = target })
---@doc example local dispatcher = ui.YEventDispatcher.new({ parent = owner, root = root, focus = focus, writer = writer, current_target = target })
---@doc example local action = ui.YAction.new({ parent = owner, label = "Run" })
---@doc example local menu = ui.YMenu.new({ parent = root, style = style, focus = focus, dispatcher = dispatcher, current_target = target, actions = { action } })
---@doc example root:show(); assert(menu:popup(2, 0)); assert(menu:active_action() == action)
---@doc example assert(menu:close()); assert(not menu:is_open())
---@doc example owner:destroy()
---@doc example if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
---@doc example if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
-- DOCS: YMenu example end
---@doc see |YAction|, |YToolBar|, |YEventDispatcher|, |YFocus|.
local YMenu = setmetatable({}, { __index = YWidget })
YMenu.__index = YMenu
local popup_keys = { "<Tab>", "<S-Tab>", "<CR>", "<Space>", "<Esc>", "<Up>", "<Down>", "<Home>", "<End>" }
local function copy(values) local out = {}; for i, value in ipairs(values) do out[i] = value end; return out end
local function index(self, action) for i, value in ipairs(self._actions) do if value == action then return i end end end
local function eligible(action) return action and not action:is_destroyed() and action:is_enabled() end
local function validate_actions(actions)
  assert(type(actions) == "table", "actions must be an array")
  local seen = {}
  for _, action in ipairs(actions) do YPushButton._action(action); assert(not seen[action], "duplicate YAction"); seen[action] = true end
  for key in pairs(actions) do assert(type(key) == "number" and key >= 1 and key <= #actions and key == math.floor(key), "actions must be an array") end
end
YMenu._validate_actions = validate_actions
---Create a closed menu with owned row widgets and lifecycle checks. Actions
---are borrowed; the popup buffer and float are created only by popup().
---@param opts YMenuOptions Required constructor options.
---@return YMenu menu # New closed menu.
function YMenu.new(opts)
  YPushButton._owners(opts); validate_actions(opts.actions == nil and {} or opts.actions)
  local self = setmetatable(YWidget.new({ parent = opts.parent }), YMenu)
  self._style, self._focus, self._dispatcher, self._target = opts.style, opts.focus, opts.dispatcher, opts.current_target
  self._actions, self._connections, self._rows, self._generation = {}, {}, {}, 0
  self._style:attach(self)
  local layout = YLayout.new({ parent = self })
  function layout:_collect(row, col, width, height, plan)
    plan[#plan + 1] = { widget = self:parent(), rect = { row, col, width, height } }
    for i, item in ipairs(self._items) do
      plan[#plan + 1] = { widget = item.value, rect = { row + i - 1, col, width, i <= height and 1 or 0 } }
    end
  end
  self:set_layout(layout)
  self._dispatcher._root:connect("destroyed", self, function(menu) menu:close() end)
  self._dispatcher:connect("destroyed", self, function(menu) menu:close() end)
  self._autocmd = vim.api.nvim_create_autocmd({ "WinClosed", "BufWipeout", "WinEnter", "BufWinEnter", "FocusLost" }, {
    callback = function(event)
      if self:is_open() and (event.event == "FocusLost" or not self:_valid()) then self:close() end
    end,
  })
  for _, action in ipairs(opts.actions or {}) do self:add_action(action) end
  return self
end
---Read membership in menu order; editing the copy does not change the menu.
---@return YAction[] actions # Copy of the borrowed action list.
function YMenu:actions() return copy(self._actions) end
---Read the selected action; close() clears it.
---@return YAction|nil action # Selected member, or nil.
function YMenu:active_action() return self._active end
---Read the owned popup target, not the borrowed host. Each open/close
---changes generation so delayed input can reject a replaced popup.
---@return integer|nil win # Popup window id, or nil when closed.
---@return integer|nil buf # Popup buffer id, or nil when closed.
---@return integer generation # Popup lifetime generation.
function YMenu:native_target() return self._win, self._buf, self._generation end
---Read whether the menu currently holds a popup window id.
---@return boolean open # True until close() releases the popup.
function YMenu:is_open() return self._win ~= nil end
function YMenu:_valid()
  if not self:is_open() or self:is_destroyed() then return false end
  local win, buf, generation = self._target()
  return not self._dispatcher:is_destroyed() and not self._focus:is_destroyed()
    and (not self._context_invocation or context_anchor.valid(self._context_invocation,self._dispatcher))
    and win == self._host_win and buf == self._host_buf and generation == self._host_generation
    and vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_get_buf(win) == buf
    and vim.api.nvim_win_is_valid(self._win) and vim.api.nvim_buf_is_valid(self._buf)
    and vim.api.nvim_win_get_buf(self._win) == self._buf
end
function YMenu:_first(backward)
  for n = 1, #self._actions do
    local action = self._actions[backward and #self._actions - n + 1 or n]
    if eligible(action) then return action end
  end
end
---Select an enabled live member, or clear with nil; invalid or foreign
---actions raise assertions. Disabled actions are refused with false. An open
---popup scrolls its native viewport to the selected action.
---@param action? YAction [default: nil] Live member to select, or nil to clear.
---@return boolean changed # True on change; false if unchanged, disabled or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YMenu:set_active_action(action)
  if action ~= nil then YPushButton._action(action); assert(index(self, action), "foreign YAction") end
  if self:is_destroyed() then return false, "destroyed" end
  if action and not eligible(action) then return false end
  if self._active == action then return false end
  self._active = action; self:update()
  -- FIX-7: Qt src/widgets/widgets/qmenu.cpp:1119-1157,3232-3237.
  -- Neovim api.txt:4224-4226 scrolls a native viewport to its cursor.
  if action and self:is_open() then vim.api.nvim_win_set_cursor(self._win, { index(self, action), 0 }) end
  if action then self:emit("hovered", action) end
  return true
end
---Insert or move an action before a live member; nil appends. A foreign
---before raises an assertion. Existing row identity survives a move. If open,
---membership changes close and reopen the popup at its current position.
---@param before? YAction [default: nil] Live member before which to insert; nil appends.
---@param action YAction Live action to insert or move.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YMenu:insert_action(before, action)
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
    local row = YWidget.new({ parent = self }); row:show(); self._rows[action] = row
    self._style:attach(row)
    local tokens = {}; self._connections[action] = tokens
    tokens[#tokens + 1] = action:connect("destroyed", self, function(menu) menu:remove_action(action) end)
    tokens[#tokens + 1] = action:connect("triggered", self, function(menu)
      if index(menu, action) then menu:emit("triggered", action) end
    end)
    tokens[#tokens + 1] = action:connect("label_changed", self, function(menu)
      if not menu:is_open() then return end
      if not menu:_valid() then menu:close(); return end
      local width = 3
      for _, member in ipairs(menu._actions) do
        width = math.max(width, YTextMetrics.width(member:label()) + YTextMetrics.width(member:key()) + 5)
      end
      width = math.min(width, vim.o.columns)
      local col = math.max(0, math.min(menu._position[2], vim.o.columns - width))
      vim.api.nvim_win_set_config(menu._win, { width = width, col = col, row = menu._position[1], relative = "editor" })
      menu._position[2] = col
      menu._layout:activate(0, 0, width, #menu._actions, menu._generation)
      menu:_prepare(); menu._native_writer:flush()
    end)
    for _, signal in ipairs({ "enabled_changed", "checkable_changed", "toggled" }) do
      tokens[#tokens + 1] = action:connect(signal, self, function(menu)
        if menu._active == action and not eligible(action) then menu:set_active_action(menu:_first(false)) end
        menu:update()
      end)
    end
  end
  table.insert(self._actions, before and index(self, before) or #self._actions + 1, action)
  self:_membership()
  return true
end
---Append or move to the end through insert_action(nil, action).
---@param action YAction Live action to append.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YMenu:add_action(action) return self:insert_action(nil, action) end
---Remove membership and destroy its owned row; the action survives. A
---non-YAction raises an assertion. Destroyed member actions are allowed and
---remove themselves automatically. Empty menus close their popup.
---@param action YAction Member to remove; may already be destroyed.
---@return boolean changed # True when removed; false if absent or menu destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YMenu:remove_action(action)
  assert(require("yana_ui.object").is_instance(action) and getmetatable(action) == require("yana_ui.action"), "expected YAction")
  if self:is_destroyed() then return false, "destroyed" end
  local i = index(self, action); if not i then return false end
  table.remove(self._actions, i)
  for _, token in ipairs(self._connections[action]) do action:disconnect(token) end
  self._connections[action] = nil
  self._rows[action]:destroy(); self._rows[action] = nil
  if self._active == action then self._active = nil; self:set_active_action(self:_first(false)) end
  self._armed = nil
  self:_membership()
  return true
end
---Remove every membership and row, leaving borrowed actions alive.
---@return boolean changed # True when cleared; false if empty or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YMenu:clear()
  if self:is_destroyed() then return false, "destroyed" end
  if #self._actions == 0 then return false end
  for _, action in ipairs(self:actions()) do self:remove_action(action) end
  return true
end
function YMenu:_membership()
  while self._layout:count() > 0 do self._layout:take_at(0) end
  for _, action in ipairs(self._actions) do YLayout._append(self._layout, { kind = "widget", value = self._rows[action] }) end
  if #self._actions == 0 then self:close()
  elseif self:is_open() then
    local row, col = self._position[1], self._position[2]
    self:popup(row, col)
  end
end
---Resolve a zero-based cell in the popup's visible viewport, including
---native scrolling. Disabled actions may be returned. Non-number or fractional
---coordinates raise assertions; negative/outside coordinates return nil.
---@param row integer Zero-based viewport row.
---@param col integer Zero-based viewport column.
---@return YAction|nil action # Action in that cell, or nil if closed/outside.
function YMenu:action_at(row, col)
  assert(type(row) == "number" and row == math.floor(row) and type(col) == "number" and col == math.floor(col), "invalid popup cell")
  if row < 0 or col < 0 then return nil end
  local _, _, width = self:rect()
  if not self:is_open() or row >= vim.api.nvim_win_get_height(self._win) or col >= width then return nil end
  local top = vim.api.nvim_win_call(self._win, function() return vim.fn.line("w0") end)
  return self._actions[top + row]
end
function YMenu:_line(action, width, checked)
  local key = action:key()
  local text = " " .. (checked and "✓" or " ") .. " " .. action:label()
  if key ~= "" then
    local room = math.max(0, width - YTextMetrics.width(key) - 1)
    if room >= 3 then text = YTextMetrics.cell_clip(text, room) .. " " .. key end
  end
  return YTextMetrics.cell_clip(text, width)
end
function YMenu:_appearance(action)
  local row = self._rows[action]
  local mask = self._style:state(row, action:is_checked(), self._active == action)
  if not eligible(action) then mask = bit.band(mask, bit.bnot(require("yana_ui.style").enabled)) end
  return self._style:appearance("item", mask, "active") or vim.api.nvim_get_hl_id_by_name("Normal")
end
function YMenu:_prepare()
  if not self._native_writer then return end
  local _, _, width = self:rect()
  local lines, marks = {}, {}
  self._variants = {}
  for i, action in ipairs(self._actions) do
    self._variants[action] = { self:_line(action, width, false), self:_line(action, width, true) }
    lines[i] = self._variants[action][action:is_checked() and 2 or 1]
    marks[i] = { slot = self._rows[action].id, row = i - 1, start_byte = 0,
      end_byte = #lines[i], appearance = self:_appearance(action) }
  end
  self._native_writer:prepare(self, lines, marks)
  self._prepared_lines = lines
  self:update()
end
---Write prepared action-row variants and marks through the supplied writer.
---Use popup() to prepare the menu before asking it to paint.
---@param writer YPaintWriter Writer holding the prepared menu rows.
---@return boolean painted # True after paint; false if destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YMenu:paint(writer)
  if self:is_destroyed() then return false, "destroyed" end
  for i, action in ipairs(self._actions) do
    local line = self._variants[action][action:is_checked() and 2 or 1]
    writer:line(i - 1, line)
    writer:mark(self._rows[action].id, i - 1, 0, #line, self:_appearance(action))
  end
  return true
end
---Open or reopen at zero-based editor cells, clamped to the screen. Coordinates
---use YLayout's nonnegative integer validation before the destroyed check.
---Enter/Space activates selection; Escape closes; Up/Down wrap through enabled
---actions, Home/End select an eligible endpoint, and Tab/Shift-Tab are consumed.
---Outside presses dismiss; a held left-button release activates the current
---eligible row, including a drag from another row in the same live gesture.
---@param row integer Nonnegative editor row.
---@param col integer Nonnegative editor column.
---@return boolean opened # True when open; false if empty, reentrant, cancelled or refused.
---@return string|nil reason # "destroyed" if dead before showing, "stale" for host/session mismatch, or a forwarded popup-input reason; nil on ordinary cancellation.
function YMenu:popup(row, col)
  YLayout.integer(row); YLayout.integer(col)
  return self:_popup(row, col)
end
local function anchor_rectangle(widget)
  if widget:is_destroyed() or not widget:is_visible() or type(widget._target) ~= "function" then return nil end
  local win, buf = widget._target()
  if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf)
    or vim.api.nvim_win_get_buf(win) ~= buf then return nil end
  local r,c,w,h = widget:rect()
  if w < 1 or h < 1 then return nil end
  local text = vim.api.nvim_buf_get_lines(buf,r,r+1,false)[1]
  if not text or YTextMetrics.width(text) <= c then return nil end
  local byte = YTextMetrics.byte_at_display(text,c+1)
  local point, bounds = geometry.screenpos(win,r+1,byte+1), geometry.get(win)
  if not point or point.row < bounds.row or point.row >= bounds.row+bounds.height
    or point.col < bounds.col or point.col >= bounds.col+bounds.width then return nil end
  return {top=point.row-1, left=point.col-1, bottom=point.row-1+h}
end
---Open below a visible control, flipping above and clamping after final population.
---@param widget YWidget Visible control borrowing the host canvas.
---@return boolean opened # True when shown, false on refusal.
---@return string|nil reason # "stale" for an unavailable anchor, or popup refusal.
function YMenu:popup_anchored(widget)
  assert(YWidget.is_instance(widget), "expected anchor YWidget")
  if not anchor_rectangle(widget) then return false, "stale" end
  return self:_popup(0,0,widget)
end
---Open at a checked context request, or capture the current registered source cursor.
---@param invocation? table [default: nil] Unmodified invocation from bind_context(); nil captures keyboard context.
---@return boolean opened # True when open, false on refusal.
---@return string|nil reason # "stale" for an unavailable source, or popup refusal.
function YMenu:popup_context(invocation)
  if invocation == nil then invocation = self._dispatcher:_context_invocation() end
  if not context_anchor.valid(invocation,self._dispatcher) then return false,"stale" end
  return self:_popup(0,0,nil,invocation)
end
function YMenu:_popup(row, col, anchor, invocation)
  if self:is_destroyed() then return false, "destroyed" end
  if self._closing or self._showing then return false end
  self:close()
  if self:is_destroyed() then return false, "destroyed" end
  local hw, hb, hg = self._target()
  if self._dispatcher:is_destroyed() or self._focus:is_destroyed() or not vim.api.nvim_win_is_valid(hw)
    or not vim.api.nvim_buf_is_valid(hb) or vim.api.nvim_win_get_buf(hw) ~= hb then return false, "stale" end
  self._showing = true
  local shown, error_message = pcall(self.emit, self, "about_to_show")
  self._showing = false
  if not shown then error(error_message, 0) end
  if self:is_destroyed() or #self._actions == 0 then return false end
  local nw, nb, ng = self._target()
  if nw ~= hw or nb ~= hb or ng ~= hg then return false, "stale" end
  local width = 3
  for _, action in ipairs(self._actions) do width = math.max(width, YTextMetrics.width(action:label()) + YTextMetrics.width(action:key()) + 5) end
  local available = vim.o.lines - vim.o.cmdheight
  if available < 1 then return false end
  width = math.min(width, vim.o.columns)
  local height = math.min(#self._actions,available)
  if anchor or invocation then
    local rect
    if invocation then rect = context_anchor.rectangle(invocation,self._dispatcher)
    else rect = anchor_rectangle(anchor) end
    if not rect then return false, "stale" end
    row, col = rect.bottom+height <= available and rect.bottom or rect.top-height, rect.left
  end
  row, col = math.max(0,math.min(row,available-height)), math.max(0,math.min(col,vim.o.columns-width))
  self._opener = anchor
  self._context_invocation = invocation
  self._popup_opener = invocation and context_anchor.opener(invocation,self._dispatcher) or nil
  self._generation, self._host_win, self._host_buf, self._host_generation = self._generation + 1, hw, hb, hg
  self._position = { row, col }
  self._buf = vim.api.nvim_create_buf(false, true)
  vim.bo[self._buf].bufhidden = "wipe"
  self._win = vim.api.nvim_open_win(self._buf, false, { relative = "editor", row = row, col = col,
    width = width, height = height, style = "minimal", focusable = true, zindex = 60, noautocmd = true })
  vim.wo[self._win].wrap = false
  vim.wo[self._win].scrolloff = 0
  self:show()
  self._layout:activate(0, 0, width, #self._actions, self._generation)
  self._native_writer = YPaintWriter.new({ parent = self, win = self._win, buf = self._buf, generation = self._generation, content_height = #self._actions,
    current_target = function() return self:native_target() end })
  self:_prepare(); self._native_writer:flush()
  -- Menu keys own Normal-mode navigation even when its opener was editing.
  vim.cmd("stopinsert")
  self._focus:register(self, self._win, self._buf, self._generation)
  local token, reason = self._dispatcher:push_popup(self)
  if not token then self:close(); return false, reason end
  self._popup_token = token
  if not self:_valid() then self:close(); return false, "stale" end
  -- FIX-3: Qt src/widgets/widgets/qmenu.cpp:3298-3312; popup input
  -- belongs to this session rather than the host's selected shortcut list.
  self._key_token = self._dispatcher:bind_keys(self._buf, function() return self:native_target() end, popup_keys)
  self._armed = nil
  if anchor then anchor._popup_menu=self; anchor:update() end
  if not eligible(self._active) then self:set_active_action(self:_first(false)) end
  return true
end
---Close an owned popup, release its mappings/focus and clear selection.
---The host buffer/window and borrowed actions survive. Repeated or reentrant
---close is allowed; callback errors propagate.
---@return boolean closed # True when closed; false if already closed or closing.
function YMenu:close()
  if not self:is_open() or self._closing then return false end
  self._closing = true
  self:emit("about_to_hide")
  local opener = self._opener
  self._opener, self._opening_pointer = nil, nil
  if opener and opener._popup_menu == self then opener._popup_menu=nil; opener:update() end
  local win, buf, writer = self._win, self._buf, self._native_writer
  if self._key_token then self._dispatcher:unbind_keys(self._key_token); self._key_token = nil end
  if self._popup_token then self._dispatcher:pop_popup(self._popup_token); self._popup_token = nil end
  self._context_invocation, self._popup_opener = nil, nil
  self._focus:release(self)
  -- FIX-6: Qt src/widgets/widgets/qmenu.cpp:2718-2735.
  self._win, self._buf, self._native_writer, self._armed, self._active, self._dismiss_button = nil, nil, nil, nil, nil, nil
  self._generation = self._generation + 1
  if writer and not writer:is_destroyed() then writer:destroy() end
  if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  if buf and vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
  self:hide()
  self._closing = false
  return true
end
function YMenu:_activate(action, generation)
  if not self:_valid() or generation ~= self._generation or not index(self, action) or not eligible(action) then return false end
  local invocation = self._context_invocation
  local hw,hb,hg = self._host_win,self._host_buf,self._host_generation
  self:close()
  if self:is_destroyed() or not index(self, action) or not eligible(action) then return false end
  if invocation then
    local win,buf,gen = self._target()
    if not context_anchor.source_valid(invocation,self._dispatcher)
      or win ~= hw or buf ~= hb or gen ~= hg or not vim.api.nvim_win_is_valid(win)
      or not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_win_get_buf(win) ~= buf then return false end
  end
  if self._overflow_toolbar then
    local bar = self._overflow_toolbar
    local button = bar:widget_for_action(action)
    if button and button:menu() then return bar:open_menu(action) end
  end
  return action:trigger()
end
---Handle popup keys or host-relative pointer coordinates. An invalid
---session is closed and consumed. Native mouse information, when supplied,
---identifies the top window and its buffer row for scrolled popup hit-testing.
---@param kind string Event kind, including key, press, move and release.
---@param row integer Zero-based host-relative row.
---@param col integer Zero-based host-relative column.
---@param button integer Mouse button; 1 arms/activates the left-button gesture.
---@param key string Normalized key name.
---@param mods any Modifier state; unused by this implementation.
---@param pos? table [default: nil] Native mouse position with winid and line fields.
---@return boolean accepted # False for an unhandled key; true for pointer events or invalid sessions.
function YMenu:event(kind, row, col, button, key, mods, pos)
  if not self:_valid() then self:close(); return true end
  if kind == "key" then
    if key == "<Esc>" then self:close(); return true end
    if key == "<Tab>" or key == "<S-Tab>" then return true end
    if key == "<CR>" or key == "<Space>" then self:_activate(self._active, self._generation); return true end
    if key == "<Home>" or key == "<End>" then self:set_active_action(self:_first(key == "<End>")); return true end
    if key == "<Up>" or key == "<Down>" then
      local start = index(self, self._active) or (key == "<Up>" and 1 or 0)
      local step = key == "<Up>" and -1 or 1
      for offset = 1, #self._actions do
        local action = self._actions[(start - 1 + offset * step) % #self._actions + 1]
        if eligible(action) then self:set_active_action(action); break end
      end
      return true
    end
    return false
  end
  local host_row, host_col = row, col
  local host, origin = vim.fn.win_screenpos(self._host_win), vim.fn.win_screenpos(self._win)
  row, col = row + host[1] - origin[1], col + host[2] - origin[2]
  local _, _, width = self:rect()
  local height = vim.api.nvim_win_get_height(self._win)
  local within = row >= 0 and col >= 0 and row < height and col < width
  local action = within and self:action_at(row, col) or nil
  -- FIX-5/7: vimfn.txt:3855-3881 reports the top native float and buffer row.
  if pos then
    within = pos.winid == self._win and pos.content ~= nil
    action = within and pos.line > 0 and self._actions[pos.line] or nil
  end
  -- Qt XCB does not replay an outside dismissal (qxcbintegration.cpp:500).
  -- Restore the editor at once; shared input owns the remaining gesture.
  if (kind == "press" or kind == "right") and not within then
    local opener = self._opener
    local sibling = kind == "press" and button == 1 and opener and opener._toolbar
      and self._dispatcher:_widget_at(host_row,host_col) or nil
    if sibling and sibling ~= opener and sibling._toolbar == opener._toolbar and sibling:menu() then
      self:close()
      return sibling:event(kind,host_row,host_col,button,key,mods,pos)
    end
    self:close()
    self._dispatcher:_swallow_gesture(button)
    return true
  end
  if kind == "press" then
    self._armed = button == 1 and eligible(action) and { generation = self._generation } or nil
    if eligible(action) then self:set_active_action(action) end
    return true
  elseif kind == "move" then
    if self._opening_pointer and button == 1 and within then
      self._armed = {generation=self._generation}
      self._opening_pointer = nil
    end
    -- FIX-6: Qt src/widgets/widgets/qmenu.cpp:3450-3505, flat-menu exit.
    self:set_active_action(eligible(action) and action or nil)
    return true
  elseif kind == "release" then
    self._opening_pointer = nil
    local armed = self._armed; self._armed = nil
    -- FIX-6: Qt src/widgets/widgets/qmenu.cpp:2921-2951: a live
    -- gesture releases the current item, including a drag from another item.
    if button == 1 and armed and action == self._active then self:_activate(action, armed.generation) end
    return true
  end
  return true
end
function YMenu:_dispose()
  self:close()
  if self._autocmd then vim.api.nvim_del_autocmd(self._autocmd); self._autocmd = nil end
  for action, tokens in pairs(self._connections) do for _, token in ipairs(tokens) do action:disconnect(token) end end
end
return YMenu
