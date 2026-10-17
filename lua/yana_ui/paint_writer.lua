-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-FileCopyrightText: 2016 The Qt Company Ltd
-- SPDX-FileCopyrightText: 2017 The Qt Company Ltd
-- SPDX-FileCopyrightText: 2016 Intel Corporation
-- SPDX-License-Identifier: LGPL-3.0-only
-- Derived from Qt src/widgets/widgets/qmenu.cpp:1119-1157 (qtbase v6.8.3).
-- Derived from Qt src/widgets/kernel/qwidget.cpp:1532,5659-5661,5747-5798 (qtbase v6.8.3).
-- Derived from Qt src/widgets/kernel/qwidgetrepaintmanager.cpp:292-307,882-907,1207-1255 (qtbase v6.8.3).
-- Modified: Lua/Neovim adaptation by Usman Bashir; notice added 2026-10-08.
-- WIDGETS P: explicitly owned canvas writes, retained native marks and frames.
local YObject = require("yana_ui.object")
local YWidget = require("yana_ui.widget")
local YTextMetrics = require("yana_ui.text_metrics")
---@alias YPaintMark {slot: integer, row: integer, start_byte: integer, end_byte: integer, appearance: integer}
---@class YPaintWriterOptions
---@field parent YObject [default: required] Live owner; destroying it releases this writer.
---@field win integer [default: required] Valid native window displaying buf.
---@field buf integer [default: required] Canvas buffer you explicitly transfer for writes; only one live writer may claim it.
---@field generation integer [default: required] Positive integer identifying this target lifetime.
---@field current_target fun():integer,integer,integer [default: required] Return the current win, buf and generation before every flush.
---@field content_height? integer [default: nil] Positive complete canvas height; nil clips to the native window height.
--
---@class YPaintWriter : YObject
---@doc brief Prepare widget content and commit changed canvas text and highlights.
---@doc qt QPainter/QBackingStore. Text cells, buffer writes and retained Neovim extmarks replace pixels. You transfer write authority for a canvas; native windows and buffers remain your cleanup responsibility.
---@doc inherits |YObject|; inherited properties, methods and destroyed signal retain |YObject| semantics.
---@doc property target|none|retarget(win, buf, generation)|none|win, buf and generation constructor options
---@signal flushed() | Emitted after text composition and retained-mark reconciliation while the target is still current, including an unchanged successful frame. No emission occurs for a refused flush or a target invalidated during paint.
---@doc errors Invalid arguments raise assertions. Window, buffer and generation must be positive finite integers naming a valid window-buffer pair; each buffer has one live writer. Widget arguments must be YWidget identities. Mark slots are positive integers unique across this writer; rows and byte columns are nonnegative integers, end_byte is exclusive and cannot precede start_byte, and appearance is a positive highlight id. Callback and native API errors propagate.
---@doc destroyed prepare,request,flush,retarget,set_content_size
---@doc exception prepare() and request() also refuse a destroyed widget. request() returns false with stale for a widget not prepared by this writer; flush() returns false with stale when the target callback no longer matches. line() and mark() require an active paint callback rather than returning a destruction error.
---@doc context lua/yana_ui/paint_writer.lua|YPaintWriter
---@doc setup Copy the Lua comments between the DOCS markers, remove their leading --, and run them in Neovim with yana-ui on runtimepath. You create a scratch canvas and float, then close only those resources after releasing the writer.
---@doc example local ui = require("yana_ui")
---@doc example local owner, buf = ui.YObject.new(), vim.api.nvim_create_buf(false, true)
---@doc example local win = vim.api.nvim_open_win(buf, false,
---@doc example   { relative = "editor", row = 1, col = 1, width = 8, height = 1, style = "minimal" })
---@doc example local target = function() return win, buf, 1 end
---@doc example local writer = ui.YPaintWriter.new({ parent = owner, win = win, buf = buf,
---@doc example   generation = 1, current_target = target })
---@doc example local widget = ui.YWidget.new({ parent = owner })
---@doc example local layout = ui.YBoxLayout.new({ parent = owner })
---@doc example layout:add_widget(widget); widget:show(); layout:activate(0, 0, 8, 1, 1)
---@doc example writer:prepare(widget, { "Ready" }, {}); writer:request(widget); writer:flush()
---@doc example owner:destroy()
---@doc example vim.api.nvim_win_close(win, true); vim.api.nvim_buf_delete(buf, { force = true })
---@doc see |YWidget|, |YLayout|, |paint|.
local YPaintWriter = setmetatable({}, { __index = YObject })
YPaintWriter.__index = YPaintWriter
local claims = {}
---Recognize an allocated object with exactly the YPaintWriter metatable,
---including a destroyed writer.
---@param value any Value to inspect.
---@return boolean instance # True for a YPaintWriter identity.
function YPaintWriter.is_instance(value) return YObject.is_instance(value) and getmetatable(value) == YPaintWriter end
local function integer(n, minimum)
  assert(type(n) == "number" and n >= minimum and n < math.huge and n == math.floor(n), "invalid paint coordinate")
end
local function target(win, buf, generation)
  integer(win, 1); integer(buf, 1); integer(generation, 1)
  assert(vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_win_get_buf(win) == buf, "invalid paint target")
end
local function valid(self)
  if self:is_destroyed() or claims[self._buf] ~= self then return false end
  if self._frame_epoch and self._frame_epoch ~= self._epoch then return false end
  local win, buf, generation = self._target()
  return win == self._win and buf == self._buf and generation == self._generation
    and vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_win_get_buf(win) == buf
end
local function delivery(self)
  local epoch = self._epoch
  self._deliver = function()
    if self._epoch == epoch and self._queued and not self:is_destroyed() then self:flush() end
  end
end
---Claim a transferred canvas and create its private highlight namespace.
---Invalid options, a missing live parent or an already claimed canvas raise
---assertions. Construction does not write text or open a native window.
---@param opts YPaintWriterOptions Required owner and native target options.
---@return YPaintWriter writer # New canvas writer.
function YPaintWriter.new(opts)
  assert(type(opts) == "table" and YObject.is_instance(opts.parent), "YPaintWriter parent required")
  assert(type(opts.current_target) == "function", "paint target callback required")
  target(opts.win, opts.buf, opts.generation)
  if opts.content_height ~= nil then integer(opts.content_height, 1) end
  assert(not claims[opts.buf], "buffer already has a live writer")
  local self = setmetatable(YObject.new(opts), YPaintWriter)
  self._buf, self._win, self._generation, self._target = opts.buf, opts.win, opts.generation, opts.current_target
  -- FIX-7: Qt src/widgets/widgets/qmenu.cpp:1119-1157; Neovim's
  -- viewport scrolls over complete owned content, not a screen-height canvas.
  self._content_height = opts.content_height
  self._namespace = vim.api.nvim_create_namespace("yana_ui.writer." .. self.id)
  self._records, self._slots, self._damage, self._epoch = {}, {}, {}, 1
  claims[self._buf] = self
  delivery(self)
  return self
end
---Copy widget-local text and marks, binding the widget to this writer.
---Replacing a preparation retains surviving slots and removes omitted marks;
---a pending widget update requests a frame. Invalid text/marks or a widget
---already bound to another live writer raise assertions.
---@param widget YWidget Widget to bind.
---@param lines string[] Prepared text rows in array order, relative to the widget rectangle.
---@param marks YPaintMark[] Prepared highlight ranges in widget-local zero-based rows and byte columns.
---@return boolean prepared # True after binding; false if writer or widget is dead.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YPaintWriter:prepare(widget, lines, marks)
  assert(YWidget.is_instance(widget) and type(lines) == "table" and type(marks) == "table", "invalid preparation")
  if self:is_destroyed() or widget:is_destroyed() then return false, "destroyed" end
  assert(not widget._writer or widget._writer == self or widget._writer:is_destroyed(), "YWidget already has a live writer")
  local prepared_lines, prepared_marks, seen = {}, {}, {}
  for i, text in ipairs(lines) do assert(type(text) == "string", "invalid prepared line"); prepared_lines[i] = text end
  for _, mark in ipairs(marks) do
    assert(type(mark) == "table", "invalid prepared mark")
    integer(mark.slot, 1); integer(mark.row, 0); integer(mark.start_byte, 0); integer(mark.end_byte, 0)
    integer(mark.appearance, 1)
    assert(mark.end_byte >= mark.start_byte and not seen[mark.slot], "invalid mark slot/range")
    assert(not self._slots[mark.slot] or self._slots[mark.slot].widget == widget, "foreign mark slot")
    seen[mark.slot] = true
    prepared_marks[#prepared_marks + 1] = { slot = mark.slot, row = mark.row,
      start_byte = mark.start_byte, end_byte = mark.end_byte, appearance = mark.appearance }
  end
  local record = self._records[widget]
  if not record then
    record = { widget = widget, lines = {}, marks = {}, rows = {}, dirty = false }
    self._records[widget] = record
    -- Qt src/widgets/kernel/qwidget.cpp:1532; qwidgetrepaintmanager.cpp:292-307.
    widget:connect("destroyed", self, function(writer) writer:_retire(widget) end)
  end
  for slot, mark in pairs(record.marks) do
    if not seen[slot] then
      if mark.id and vim.api.nvim_buf_is_valid(self._buf) then vim.api.nvim_buf_del_extmark(self._buf, self._namespace, mark.id) end
      record.marks[slot], self._slots[slot] = nil, nil
    end
  end
  record.lines = prepared_lines
  for _, mark in ipairs(prepared_marks) do
    local retained = record.marks[mark.slot]
    if retained then
      retained.row, retained.start_byte, retained.end_byte, retained.appearance = mark.row, mark.start_byte, mark.end_byte, mark.appearance
    else
      mark.widget, mark.options = widget, { right_gravity = false, end_right_gravity = false, strict = false }
      record.marks[mark.slot], self._slots[mark.slot] = mark, mark
    end
  end
  widget._writer = self
  if widget._paint_pending then self:request(widget) end
  return true
end
---Mark prepared content dirty and schedule one coalesced main-loop flush.
---Repeated requests reuse the pending delivery; invalid widget values raise
---an assertion. Preparation must already belong to this writer.
---@param widget YWidget Prepared widget to update.
---@return boolean queued # True when marked dirty; false if dead or unprepared.
---@return "destroyed"|"stale"|nil reason # Destruction or preparation refusal, or nil.
function YPaintWriter:request(widget)
  assert(YWidget.is_instance(widget), "paint YWidget required")
  if self:is_destroyed() or widget:is_destroyed() then return false, "destroyed" end
  local record = self._records[widget]
  if not record or widget._writer ~= self then return false, "stale" end
  record.dirty, widget._paint_pending = true, true
  if not self._queued then self._queued = true; vim.schedule(self._deliver) end
  return true
end
---Replace one prepared text row during widget:paint(writer). This records
---intent; flush performs native writes. Invalid arguments or a call outside
---the active paint callback raise assertions.
---@param row integer Nonnegative zero-based widget-local row.
---@param text string Replacement row text.
---@return boolean stored # Always true after storing.
function YPaintWriter:line(row, text)
  integer(row, 0); assert(type(text) == "string", "paint line must be a string")
  assert(self._context, "line outside paint context")
  self._context.lines[row + 1] = text
  return true
end
---Change one already prepared mark during widget:paint(writer). Invalid
---arguments, an unprepared slot or a slot belonging to another widget raise
---assertions. Native mark identity is retained while the range stays visible.
---@param slot integer Positive slot owned by the active widget preparation.
---@param row integer Nonnegative zero-based widget-local row.
---@param start_byte integer Nonnegative inclusive widget-local byte column.
---@param end_byte integer Nonnegative exclusive byte column, at least start_byte.
---@param appearance integer Positive native highlight group id.
---@return boolean stored # Always true after recording the range.
function YPaintWriter:mark(slot, row, start_byte, end_byte, appearance)
  integer(slot, 1); integer(row, 0); integer(start_byte, 0); integer(end_byte, 0); integer(appearance, 1)
  assert(end_byte >= start_byte, "invalid paint mark range")
  local record = self._context
  assert(record and record.marks[slot], "unprepared/foreign paint slot")
  local mark = record.marks[slot]
  mark.row, mark.start_byte, mark.end_byte, mark.appearance = row, start_byte, end_byte, appearance
  return true
end
local function byte_at(text, cell)
  -- YTextMetrics' legacy helper is one-based in cells; canvas cells are zero-based.
  return YTextMetrics.byte_at_display(text, cell + 1)
end
local function intersects(damage, row, first, last)
  for _, span in ipairs(damage[row] or {}) do
    if first < span[2] and span[1] < last then return true end
  end
  return false
end
local function damage_row(damage, row, first, last)
  if last <= first then return end
  damage[row] = damage[row] or {}
  damage[row][#damage[row] + 1] = { first, last }
end
local function damage_rect(damage, rect)
  if not rect then return end
  for row = rect[1], rect[1] + rect[4] - 1 do damage_row(damage, row, rect[2], rect[2] + rect[3]) end
end
function YPaintWriter:_retire(widget)
  local record = self._records[widget]
  if not record then return end
  damage_rect(self._damage, record.bounds)
  for slot, mark in pairs(record.marks) do
    if mark.id and vim.api.nvim_buf_is_valid(self._buf) then
      vim.api.nvim_buf_del_extmark(self._buf, self._namespace, mark.id)
    end
    self._slots[slot] = nil
  end
  self._records[widget] = nil
  if widget._writer == self then widget._writer = nil end
  if not self._queued then self._queued = true; vim.schedule(self._deliver) end
end
---Opt into a complete scrollable canvas, repainting preparations on size changes.
---The next valid flush owns exactly these rows and display cells; native windows
---remain borrowed. Existing viewport/content_height clipping applies until used.
---Retarget retains the extent. Invalid values assert before the destruction check.
---@param width integer Positive finite canvas width in display cells.
---@param height integer Positive finite canvas row count.
---@return boolean changed # True for a new extent; false if unchanged or destroyed.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YPaintWriter:set_content_size(width, height)
  integer(width, 1); integer(height, 1)
  if self:is_destroyed() then return false, "destroyed" end
  if self._content_width == width and self._content_height == height then return false end
  self._content_width, self._content_height, self._resize_pending = width, height, true
  for _, record in pairs(self._records) do
    damage_rect(self._damage, record.bounds)
    record.rows, record.bounds = {}, nil
    self:request(record.widget)
  end
  if not self._queued then self._queued = true; vim.schedule(self._deliver) end
  return true
end
local function canvas_width(self)
  return self._content_width or vim.api.nvim_win_get_width(self._win)
end
local function resize_canvas(self)
  if not self._resize_pending then return end
  local width, height = self._content_width, self._content_height
  for row = 0, height - 1 do
    if not valid(self) then return end
    local old = vim.api.nvim_buf_get_lines(self._buf, row, row + 1, false)[1]
    local clipped, _, used = YTextMetrics.prefix_cells(old or "", width, 0)
    local line = clipped .. string.rep(" ", width - used)
    if line ~= old then
      vim.api.nvim_buf_set_lines(self._buf, row, row + 1, false, {line})
    end
  end
  if not valid(self) then return end
  if vim.api.nvim_buf_line_count(self._buf) > height then
    vim.api.nvim_buf_set_lines(self._buf, height, -1, false, {})
  end
  self._resize_pending = false
end
local function bounds(self, widget)
  if not widget:is_visible() then return nil end
  local row, col, width, height = widget:rect()
  local right = math.min(col + width, canvas_width(self))
  local bottom = math.min(row + height, self._content_height or vim.api.nvim_win_get_height(self._win))
  row, col = math.max(0, row), math.max(0, col)
  if right <= col or bottom <= row then return nil end
  return { row, col, right - col, bottom - row }
end
local function affected(damage, rect)
  if not rect then return false end
  for row = rect[1], rect[1] + rect[4] - 1 do
    if intersects(damage, row, rect[2], rect[2] + rect[3]) then return true end
  end
  return false
end
local function render_lines(self, record, row, col, width, height, damage)
  local native_height = self._content_height or vim.api.nvim_win_get_height(self._win)
  local native_width = canvas_width(self)
  -- A vanished/off-canvas row must not supply yesterday's mark clipping.
  for i, cached in pairs(record.rows) do
    if i > height or row + i - 1 >= native_height or width <= 0 or col >= native_width then
      record.rows[i] = nil
    end
  end
  for i = 1, math.min(height, native_height - row) do
    if not valid(self) then return end
    local text = record.lines[i] or ""
    local cached = record.rows[i]
    local available = math.max(0, math.min(width, native_width - col))
    if col >= 0 and row + i - 1 >= 0 and available > 0 and
      (not cached or cached.text ~= text or cached.row ~= row + i - 1 or cached.col ~= col or cached.width ~= available) then
      local clipped, _, used = YTextMetrics.prefix_cells(text, available, col)
      clipped = clipped .. string.rep(" ", available - used)
      local canvas_row = row + i - 1
      local old = vim.api.nvim_buf_get_lines(self._buf, canvas_row, canvas_row + 1, false)[1]
      if old == nil then
        local count = vim.api.nvim_buf_line_count(self._buf)
        local blanks = {}
        for _ = count, canvas_row do blanks[#blanks + 1] = string.rep(" ", native_width) end
        vim.api.nvim_buf_set_lines(self._buf, count, count, false, blanks)
        if not valid(self) then return end
        for added = count, canvas_row do damage_row(damage, added, 0, native_width) end
        old = blanks[#blanks]
      end
      if YTextMetrics.width(old) < col + available then
        local old_width = YTextMetrics.width(old)
        old = YTextMetrics.pad(old, col + available)
        vim.api.nvim_buf_set_lines(self._buf, canvas_row, canvas_row + 1, false, { old })
        if not valid(self) then return end
        damage_row(damage, canvas_row, old_width, col + available)
      end
      local first, last = byte_at(old, col), byte_at(old, col + available)
      if old:sub(first + 1, last) ~= clipped then
        vim.api.nvim_buf_set_text(self._buf, canvas_row, first, canvas_row, last, { clipped })
        if not valid(self) then return end
        damage_row(damage, canvas_row, col, col + available)
      end
      local current = vim.api.nvim_buf_get_lines(self._buf, canvas_row, canvas_row + 1, false)[1]
      if col == 0 and available == native_width and YTextMetrics.width(current) > native_width then
        local cut = byte_at(current, native_width)
        vim.api.nvim_buf_set_text(self._buf, canvas_row, cut, canvas_row, #current, {})
        if not valid(self) then return end
        damage_row(damage, canvas_row, native_width, YTextMetrics.width(current))
      end
      cached = cached or {}; record.rows[i] = cached
      cached.text, cached.row, cached.col, cached.width = text, canvas_row, col, available
      cached.clipped = clipped
    end
  end
end
local function render_marks(self, record, row, col, width, height)
  for _, mark in pairs(record.marks) do
    -- Neovim nvim_buf_get_extmark_by_id: shared text writes move retained marks.
    local native = mark.id and vim.api.nvim_buf_get_extmark_by_id(self._buf, self._namespace,
      mark.id, { details = true, hl_name = false }) or {}
    local text = record.lines[mark.row + 1] or ""
    local clipped = record.rows[mark.row + 1]
    local last = math.min(mark.end_byte, clipped and #clipped.clipped or 0, #text)
    local first = math.min(mark.start_byte, last)
    if width > 0 and mark.row < height and clipped and clipped.row == row + mark.row
      and clipped.col == col and last > first then
      local canvas_row = row + mark.row
      local canvas = vim.api.nvim_buf_get_lines(self._buf, canvas_row, canvas_row + 1, false)[1]
      local offset = byte_at(canvas, col)
      local start_col, end_col = offset + first, offset + last
      local details = native[3]
      if native[1] ~= canvas_row or native[2] ~= start_col or not details
        or details.end_row ~= canvas_row or details.end_col ~= end_col or details.hl_group ~= mark.appearance then
        local options = mark.options
        options.id, options.end_row, options.end_col, options.hl_group = mark.id, canvas_row, end_col, mark.appearance
        mark.id = vim.api.nvim_buf_set_extmark(self._buf, self._namespace, canvas_row, start_col, options)
      end
    elseif #native > 0 then
      vim.api.nvim_buf_del_extmark(self._buf, self._namespace, mark.id)
    end
  end
end
local function paint(self, record, damage)
  self._context = record
  local ok, reason = pcall(record.widget.paint, record.widget, self)
  self._context = nil
  if not ok then error(reason, 0) end
  if not valid(self) or record.widget:is_destroyed() then return end
  local row, col, width, height = record.widget:rect()
  render_lines(self, record, row, col, width, height, damage)
end
local function flush_frame(self)
  resize_canvas(self)
  if not valid(self) then return true end
  local dirty, records, damage = {}, {}, self._damage
  self._damage = {}
  local roots = {}
  for widget, record in pairs(self._records) do
    if record.dirty then
      record.dirty, widget._paint_pending = false, false
      dirty[record] = true
    end
    local current = bounds(self, widget)
    -- Qt src/widgets/kernel/qwidgetrepaintmanager.cpp:1207-1255:
    -- exposure belongs to both the previously painted and current regions.
    if not vim.deep_equal(record.bounds, current) then
      damage_rect(damage, record.bounds); damage_rect(damage, current)
      record.rows, record.bounds = {}, current
      dirty[record] = true
    end
    if not widget:is_visible() then
      record.rows = {}; render_marks(self, record, 0, 0, 0, 0)
    end
    local root = widget
    while root:parent() do root = root:parent() end
    roots[root] = true
  end
  -- Qt src/widgets/kernel/qwidget.cpp:5659-5661,5747-5798:
  -- traverse the current ownership tree, including each sibling's subtree.
  local function visit(widget)
    local record = self._records[widget]
    if record and widget:is_visible() then records[#records + 1] = record end
    local child = widget._child_head
    while child do visit(child); child = child._next_sibling end
  end
  local ordered = vim.tbl_keys(roots)
  table.sort(ordered, function(a, b) return a.id < b.id end)
  for _, root in ipairs(ordered) do visit(root) end
  -- Erase exposed cells even when no surviving layer covers them.
  for row, spans in pairs(damage) do
    if not valid(self) then break end
    local line = vim.api.nvim_buf_get_lines(self._buf, row, row + 1, false)[1]
    if line then
      for _, span in ipairs(spans) do
        if not valid(self) then break end
        local start_cell, end_cell = span[1], span[2]
        if self._content_width then
          start_cell, end_cell = math.min(start_cell,self._content_width), math.min(end_cell,self._content_width)
        end
        local first, last = byte_at(line, start_cell), byte_at(line, end_cell)
        local blank = string.rep(" ", end_cell - start_cell)
        if line:sub(first + 1, last) ~= blank then
          vim.api.nvim_buf_set_text(self._buf, row, first, row, last, { blank })
          line = vim.api.nvim_buf_get_lines(self._buf, row, row + 1, false)[1]
        end
      end
    end
  end
  -- Qt src/widgets/kernel/qwidgetrepaintmanager.cpp:882-907: compose damage.
  for _, record in ipairs(records) do
    if not valid(self) then break end
    local exposed = affected(damage, record.bounds)
    for i, cached in pairs(record.rows) do
      if intersects(damage, cached.row, cached.col, cached.col + cached.width) then
        record.rows[i], exposed = nil, true
      end
    end
    if dirty[record] or exposed then paint(self, record, damage) end
  end
  -- Reconcile only after every text write; later records can move earlier marks.
  if valid(self) then
    for _, record in ipairs(records) do
      if not valid(self) then break end
      if not record.widget:is_destroyed() and record.widget:is_visible() then
        render_marks(self, record, record.widget:rect())
      end
    end
  end
  return true
end
local function finish_write_scope(self, scope)
  if not scope or scope.finished then return end
  scope.finished = true
  if self._write_scope == scope then self._write_scope = nil end
  if scope.restore and vim.api.nvim_buf_is_valid(scope.buf) and vim.bo[scope.buf].modifiable then
    vim.bo[scope.buf].modifiable = false
  end
end
---Compose dirty and exposed regions, then reconcile retained highlights.
---Restore temporary writability even on paint errors, destruction or retarget.
---Full-canvas frames preserve the native viewport. A callback-invalidated frame
---may return true without emitting flushed; reentrant flush is refused as stale.
---@return boolean flushed # True after processing a valid starting target; false on refusal.
---@return "destroyed"|"stale"|nil reason # Destruction, reentrancy or native target refusal, or nil.
function YPaintWriter:flush()
  if self:is_destroyed() then return false, "destroyed" end
  if self._frame_epoch then return false, "stale" end
  self._queued = false
  if not valid(self) then return false, "stale" end
  local view = self._content_width and vim.api.nvim_win_call(self._win, vim.fn.winsaveview)
  local scope = {buf=self._buf,restore=not vim.bo[self._buf].modifiable}
  self._write_scope, self._frame_epoch = scope, self._epoch
  local ok, result = pcall(function()
    if scope.restore then vim.bo[scope.buf].modifiable = true end
    return flush_frame(self)
  end)
  local view_ok, view_error = pcall(function()
    if view and valid(self) then
      vim.api.nvim_win_call(self._win, function() if valid(self) then vim.fn.winrestview(view) end end)
    end
  end)
  local scope_ok, scope_error = pcall(finish_write_scope,self,scope)
  local completed = valid(self)
  self._frame_epoch = nil
  if not ok then error(result,0) end
  if not view_ok then error(view_error,0) end
  if not scope_ok then error(scope_error,0) end
  if completed then self:emit("flushed") end
  return result
end
---Transfer the claim to a valid canvas, clear this writer's old highlights,
---cancel old scheduled delivery and request every preparation for the new
---target. Invalid or foreign-claimed targets raise assertions, even after
---destruction. Update your current_target callback to match the new triple.
---@param win integer Positive valid native window displaying buf.
---@param buf integer Positive valid transferred canvas buffer.
---@param generation integer Positive integer for the new target lifetime.
---@return boolean changed # True on target change; false if unchanged or dead.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YPaintWriter:retarget(win, buf, generation)
  target(win, buf, generation)
  if self:is_destroyed() then return false, "destroyed" end
  assert(not claims[buf] or claims[buf] == self, "buffer already has a live writer")
  if win == self._win and buf == self._buf and generation == self._generation then return false end
  finish_write_scope(self,self._write_scope)
  if claims[self._buf] == self then claims[self._buf] = nil end
  if vim.api.nvim_buf_is_valid(self._buf) then vim.api.nvim_buf_clear_namespace(self._buf, self._namespace, 0, -1) end
  self._epoch, self._queued, self._damage = self._epoch + 1, false, {}
  self._win, self._buf, self._generation = win, buf, generation
  if self._content_width then self._resize_pending = true end
  claims[buf] = self
  delivery(self)
  for _, record in pairs(self._records) do
    record.rows, record.bounds = {}, nil
    for _, mark in pairs(record.marks) do
      mark.id = nil
    end
    self:request(record.widget)
  end
  return true
end
function YPaintWriter:_dispose()
  finish_write_scope(self,self._write_scope)
  self._epoch, self._queued = self._epoch + 1, false
  for widget in pairs(self._records) do if widget._writer == self then widget._writer = nil end end
  if vim.api.nvim_buf_is_valid(self._buf) then vim.api.nvim_buf_clear_namespace(self._buf, self._namespace, 0, -1) end
  if claims[self._buf] == self then claims[self._buf] = nil end
end
return YPaintWriter
-- DOCS: YPaintWriter example start
-- local ui = require("yana_ui")
-- local owner, buf = ui.YObject.new(), vim.api.nvim_create_buf(false, true)
-- local win = vim.api.nvim_open_win(buf, false,
--   { relative = "editor", row = 1, col = 1, width = 8, height = 1, style = "minimal" })
-- local target = function() return win, buf, 1 end
-- local writer = ui.YPaintWriter.new({ parent = owner, win = win, buf = buf,
--   generation = 1, current_target = target })
-- local widget = ui.YWidget.new({ parent = owner })
-- local layout = ui.YBoxLayout.new({ parent = owner })
-- layout:add_widget(widget); widget:show(); layout:activate(0, 0, 8, 1, 1)
-- writer:prepare(widget, { "Ready" }, {}); writer:request(widget); writer:flush()
-- owner:destroy()
-- vim.api.nvim_win_close(win, true); vim.api.nvim_buf_delete(buf, { force = true })
-- DOCS: YPaintWriter example end
