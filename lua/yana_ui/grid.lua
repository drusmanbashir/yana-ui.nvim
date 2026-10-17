-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- yana-ui: reusable cell-grid controller.
-- Product meaning stays in callers; this module only renders and routes cells.
local support = require("yana_ui.grid_layout")
---@class YGridExports
---@field fit fun(lines: string[], spans: YGridSpan[], cap?: integer, opts?: YGridFitOptions): string[], YGridSpan[] Alias of the pure grid_layout.fit helper; mutates supplied lines/span positions.
---@field layout fun(rows: YGridCell[][]|YGridBand[], opts?: YGridLayoutOptions): string[], YGridSpan[]|YGridByteSpan[] Alias of the pure grid_layout.layout helper; bands returns byte spans.
local M = { fit = support.fit, layout = support.layout }
local NS = support.namespace
local input = require("yana_ui.input")
local resources = require("yana_ui.panel_host")
local valid_win = support.valid_win
local valid_buf = support.valid_buf
local transient_float = support.transient_float
local byte_at_display = support.byte_at_display
local metrics = require("yana_ui.text_metrics")
local style = require("yana_ui.style")
local next_id = 0

---@class YGridOptions
---@field state? table [default: {}] Your mutable selection/content state; render adds lines, spans and data_start.
---@field cells? fun(state: table): YGridCell[][] [default: nil] Supply rows of cells; missing or non-table results become empty rows.
---@field columns? string[]|fun(state: table): string[] [default: {}] Column names or a callback, used by column layout/navigation.
---@field layout? "columns"|"flow" [default: nil] Nil uses columns; bands is refused because pure layout() supplies byte spans.
---@field width? integer|fun(grid: YGrid): integer [default: attached window width or 40] Render width; open() uses a numeric width or its editor-size default.
---@field height? integer [default: min(24, max(8, floor(lines * 2 / 3)))] Initial open() float height.
---@field max_height? integer [default: nil] Render height cap; attach also caps to window height unless fit_buffer is false.
---@field fit_buffer? boolean [default: true] Allow the attached window height to cap rendered lines.
---@field title? string|fun(state: table): string [default: nil] Text line inserted before the grid.
---@field legend? string|fun(state: table): string [default: nil] Text appended after a rule line.
---@field wrap_legend? boolean [default: false] Wrap legend by byte count and reserve its lines under the height cap.
---@field pin_legend? boolean [default: false] Pad content to the height cap before appending the legend.
---@field rule_char? string [default: "─"] Character repeated across the legend rule.
---@field column_widths? table|fun(width: integer, columns: string[]): table [default: nil] Fixed widths keyed by column name or array index.
---@field column_separator? string|table [default: nil] Vertical separator and optional junction; a truthy value adds a rule for multiple columns.
---@field scroll_data? boolean [default: false] Retain headers when fitting column-layout data.
---@field header_lines? integer [default: 2] Header lines preserved by scroll_data.
---@field namespace? integer [default: yana_ui.grid namespace] Namespace cleared and used for cell marks on render.
---@field hl_groups? table<string,string> [default: nil] Override live, dim, flash, hover, current, marked and key; omitted roles use standard-linked YanaUiGrid groups.
---@field window_title? string [default: nil] Native floating-window title.
---@field title_pos? string [default: nil] Native title position.
---@field footer? string [default: nil] Native nonempty floating-window footer.
---@field footer_pos? string [default: "right"] Native footer position.
---@field float? boolean [default: false] Enable render-time float resizing; open() sets true.
---@field fixed_size? boolean [default: false] Prevent automatic float resizing.
---@field place_cursor? boolean [default: false] Place the native cursor at the active span after render.
---@field row_count? fun(state: table): integer [default: nil] Navigation row count; fallback is state.data_rows, then 1.
---@field column_count? fun(state: table, col: string): integer [default: nil] Limit the active row after moving to a column.
---@field value_at? fun(state: table, col: string, row: integer): any [default: nil] Resolve active_val after navigation.
---@field release_anywhere? boolean [default: false] Allow an armed release away from the pressed identity.
---@field flash_ms? integer [default: 0] Nonnegative milliseconds <=2147483647; flash a matching live release, cancelled by press/attach/close.
---@field global_mouse? boolean [default: false] Compatibility option; attached grids share target-checked native mouse intake.
---@field map_desc? string [default: nil] Description passed to compatibility global mouse acquisition.
---@field focus_guard? boolean [default: false] Cancel on entry into another ordinary window.
---@field type_to_filter? boolean [default: false] Map unreserved printable ASCII keys through key().
---@field reserved_keys? table<string,boolean> [default: { h=true, j=true, k=true, l=true, q=true }] Printable keys excluded from filtering maps.
---@field mark_key? string [default: "m"] Key invoking on_mark when supplied.
---@field close_window? boolean [default: true] close() closes the attached window unless false; open() forces true.
---@field delete_buffer? boolean [default: true] close() deletes the attached buffer unless false; open() forces true.
---@field on_cursor? fun(grid: YGrid, row: integer) [default: nil] Called after cursor-to-row selection and before render.
---@field on_move? fun(grid: YGrid) [default: nil] Called after navigation state changes and before render.
---@field on_press? fun(grid: YGrid, span: YGridSpan|nil) [default: nil] Called after arming; live cells first update selection, dim/non-live cells do not.
---@field on_release? fun(grid: YGrid, span: YGridSpan|nil, pressed: YGridSpan) [default: nil] Called with the press snapshot after clearing armed state when the release matches or release_anywhere is set.
---@field on_hover? fun(grid: YGrid, span: YGridSpan|nil) [default: nil] Called after hover identity changes and before render.
---@field on_key? fun(grid: YGrid, key: string): boolean [default: nil] Run before keyboard defaults; true consumes the key. Mouse keys bypass it.
---@field on_enter? fun(grid: YGrid) [default: nil] Called for Enter; no automatic render or close.
---@field on_space? fun(grid: YGrid, span: YGridSpan|nil) [default: nil] Called for Space before render.
---@field on_mark? fun(grid: YGrid, span: YGridSpan|nil) [default: nil] Called for mark_key before render.
---@field on_delete? fun(grid: YGrid, span: YGridSpan|nil) [default: nil] Called for Delete before render.
---@field on_back? fun(grid: YGrid) [default: nil] Called for Backspace; without it Backspace is inert.
---@field on_cancel? fun(grid: YGrid) [default: nil] Called after resource cleanup only when cancelled is truthy.
---@class YGridRenderOptions
---@field place_cursor? boolean [default: false] Request cursor placement for this render.
---@class YGrid
---@field opts YGridOptions Shared options table; open() updates resource flags.
---@field state table Shared mutable state table.
---@field id integer Allocated controller identity.
---@field buf? integer Attached buffer handle.
---@field win? integer Attached window handle.
---@field lines string[] Most recent rendered lines.
---@field spans YGridSpan[] Most recent cell spans.
---@field data_start integer One-based first data line.
---@field closed? boolean True after close(); initially nil.
---@doc brief Render caller-provided cells and route selection, pointer and keyboard callbacks.
---@doc qt QAbstractItemView. You own models and actions in a Lua state table; native buffers/windows provide scrolling and cursor movement. This compatibility controller is separate from YWidget and YObject.
---@doc inherits none; options contain callbacks, not YObject signals. Callbacks run synchronously at the points listed in the option table; their errors propagate.
---@doc property state|state (mutable shared field)|none|none|option:state
---@doc property lines|lines (read-only field)|render(render_opts), refresh(opts)|none|empty list
---@doc property spans|spans (read-only field)|render(render_opts), refresh(opts)|none|empty list
---@doc property closed|closed (read-only field)|close(cancelled)|none|nil
---@doc errors There is no shared option validator or destroyed return. Native calls, malformed data and callback failures can raise; some mark/window updates and cleanup calls are protected. Supply row_count greater than zero for wraparound navigation. close() is repeatable; render() does nothing after closure and retires an invalid native window before reading cells. render() requires flow/column spans with display-column fields; bands output has a different byte-span shape.
---@doc context lua/yana_ui/grid.lua|YGrid
---@doc setup With your checkout on runtimepath, run this excerpt in Neovim. It creates and closes its own grid float and scratch buffer.
---@doc example local ui = require("yana_ui")
---@doc example local grid = ui.YGrid.open({ layout = "columns", columns = { "Name" },
---@doc example   state = { data_rows = 1 }, cells = function()
---@doc example     return { { { col = "Name", row_i = 1, text = "Alpha", value = "alpha" } } }
---@doc example   end })
---@doc example assert(#grid.lines >= 2 and #grid.spans == 1)
---@doc example grid:close(false)
---@doc see |YPanelHost|, |YTextMetrics|, |geometry|.
local YGrid = {}
YGrid.__index = YGrid
local function same_span(a,b)
  if not a or not b then return false end
  if a.action and b.action then return a.action==b.action end
  return a.col==b.col and a.value==b.value and a.row_i==b.row_i
end
local function clear_flash(g)
  g._flash=nil
  g._flash_deadline=nil
  if g._flash_timer then g._flash_timer:stop() end
end
local function flash_target(g)
  if g.closed then return 0,0 end
  if not g.win then return g.id,0 end
  if valid_win(g.win) and valid_buf(g.buf) and vim.api.nvim_win_get_buf(g.win)==g.buf then return g.win,g.buf end
  return 0,0
end
local function start_flash(g,span)
  local ms=g.opts.flash_ms or 0
  if ms==0 or g.closed then return end
  if not g._flash_timer then
    g._flash_owner=require("yana_ui.object").new()
    g._flash_timer=require("yana_ui.timer").new{parent=g._flash_owner,single_shot=true,
      current_target=function()return flash_target(g)end}
    g._flash_timer:connect("timeout",g._flash_owner,function()
      g._flash=nil
      g._flash_deadline=nil
      if not g.closed then g:render() end
    end)
  end
  local id,generation=flash_target(g)
  if id==0 then return end
  g._flash=vim.tbl_extend("force",{},span)
  g._flash_deadline=vim.uv.hrtime()+ms*1000000
  g._flash_timer:bind(id,generation)
  g._flash_timer:start(ms)
end
local function columns(g)
	return type(g.opts.columns) == "function" and g.opts.columns(g.state) or g.opts.columns or {}
end
local function rows(g)
	local result = g.opts.cells and g.opts.cells(g.state) or {}
	return type(result) == "table" and result or {}
end
local function active_span(g)
	for _, span in ipairs(g.spans or {}) do
		if span.row_i == g.state.active_row and (g.state.active_col == nil or span.col == g.state.active_col) then return span end
	end
	for _, span in ipairs(g.spans or {}) do if span.active then return span end end
end
local cursor_span, select_span
---Recompute lines/spans, mirror them into state and update the attached buffer.
---Without a valid buffer only the computed state is updated. With a live window,
---request title/footer/float geometry and optional cursor placement.
---@param render_opts? YGridRenderOptions [default: nil] Per-render cursor request.
---@return YGrid grid # This controller for chaining.
function YGrid:render(render_opts)
  -- A callback may retire its native target while input is being dispatched.
  -- Retire the controller before consulting caller-owned cell/width providers.
  if self.closed then return self end
  if self.win and not valid_win(self.win) then self:close(false); return self end
  assert(self.opts.layout ~= "bands", "YGrid requires display spans; bands supplies byte spans")
	render_opts = render_opts or {}
	local cells = rows(self)
	local cap = self.opts.fit_buffer == false and nil or self.opts.max_height
	if self.opts.fit_buffer ~= false and valid_win(self.win) then cap = math.min(cap or 999, vim.api.nvim_win_get_height(self.win)) end
	local title = type(self.opts.title) == "function" and self.opts.title(self.state) or self.opts.title
	local width = type(self.opts.width) == "function" and self.opts.width(self) or (tonumber(self.opts.width) or (valid_win(self.win) and vim.api.nvim_win_get_width(self.win) or 40))
	local legend = type(self.opts.legend) == "function" and self.opts.legend(self.state) or self.opts.legend
	local legend_lines = {}
	if self.opts.wrap_legend and legend and legend ~= "" then
		local remaining = legend
		while #remaining > width do
			local cut = width
			local space = remaining:sub(1, width):match("^.*() ")
			if space and space > math.floor(width / 2) then cut = space end
			legend_lines[#legend_lines + 1], remaining = remaining:sub(1, cut), remaining:sub(cut + 1)
		end
		legend_lines[#legend_lines + 1] = remaining
	elseif legend and legend ~= "" then
		legend_lines[1] = legend
	end
	local layout_cap = cap
	if self.opts.wrap_legend and cap then
		layout_cap = math.max(1, cap - (title and title ~= "" and 1 or 0) - (#legend_lines > 0 and #legend_lines + 1 or 0))
	end
	local lines, spans = M.layout(cells, {
		layout = self.opts.layout,
		columns = columns(self),
		width = width, max_height = layout_cap,
		column_widths = self.opts.column_widths,
		column_separator = self.opts.column_separator,
		scroll_data = self.opts.scroll_data, header_lines = self.opts.header_lines,
		reveal_row = self.state.reveal_row,
		active_row = self.state.active_row,
	})
	if title and title ~= "" then
		table.insert(lines, 1, title)
		for _, span in ipairs(spans) do span.line = span.line + 1 end
	end
	if self.opts.pin_legend and cap and #legend_lines > 0 then
		local legend_space = #legend_lines + 1
		local content_cap = math.max(1, cap - legend_space)
		while #lines < content_cap do lines[#lines + 1] = "" end
	end
	if legend and legend ~= "" then
		lines[#lines + 1] = string.rep(self.opts.rule_char or "─", math.max(1, width))
		for _, line in ipairs(legend_lines) do lines[#lines + 1] = line end
	end
	if self._flash and self._flash_deadline and vim.uv.hrtime()>=self._flash_deadline then
		self._flash=nil
		self._flash_deadline=nil
	end
	for _, span in ipairs(spans) do
		span.armed = same_span(span,self.armed) or span.armed
		span.flash = same_span(span,self._flash) or span.flash
		span.hover = self.hover and span.action == self.hover.action and span.value == self.hover.value and span.row_i == self.hover.row_i and span.col == self.hover.col or span.hover
	end
	self.lines, self.spans = lines, spans
	local extra_header = self.opts.layout == "columns" and self.opts.column_separator and 1 or 0
	self.data_start = (title and title ~= "" and self.opts.layout == "columns") and 3 + extra_header or (title and title ~= "" and 2 or 1)
	if self.opts.layout == "columns" and not (title and title ~= "") then self.data_start = 2 end
	if type(self.state) == "table" then
		self.state.lines, self.state.spans, self.state.data_start = lines, spans, self.data_start
	end
	if not valid_buf(self.buf) then return self end
	vim.bo[self.buf].modifiable = true
	vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
	local ns = self.opts.namespace or NS
	vim.api.nvim_buf_clear_namespace(self.buf, ns, 0, -1)
	local hl_groups = vim.tbl_extend("force", {}, style._grid_groups, self.opts.hl_groups or {})
	for _, span in ipairs(spans) do
		span.byte_start = byte_at_display(lines[span.line], span.col_start)
		span.byte_end = byte_at_display(lines[span.line], span.col_end)
		span.key_byte_start = byte_at_display(lines[span.line], span.key_col_start)
		span.key_byte_end = byte_at_display(lines[span.line], span.key_col_end)
		local group = hl_groups.live
		if span.dim then group = hl_groups.dim
		elseif span.armed or span.flash then group = hl_groups.flash
		elseif span.hover or span.active then group = hl_groups.hover
		elseif span.current then group = hl_groups.current
		elseif span.fixed then group = hl_groups.flash end
		if group then pcall(vim.api.nvim_buf_set_extmark, self.buf, ns, span.line - 1, span.byte_start, { end_col = span.byte_end, hl_group = group, priority = 0 }) end
		local marked = hl_groups.marked
		if span.marked and marked then
			pcall(vim.api.nvim_buf_set_extmark, self.buf, ns, span.line - 1, span.byte_start, {
				end_col = span.byte_end, hl_group = marked, priority = 20, hl_mode = "combine",
			})
		end
		local key = hl_groups.key
		if key and span.key_col_end > span.key_col_start then pcall(vim.api.nvim_buf_set_extmark, self.buf, ns, span.line - 1, span.key_byte_start, { end_col = span.key_byte_end, hl_group = key, priority = 10 }) end
	end
	vim.bo[self.buf].modifiable = false
	if valid_win(self.win) then
		local cfg = { title = self.opts.window_title, title_pos = self.opts.title_pos }
		if self.opts.footer and self.opts.footer ~= "" then cfg.footer, cfg.footer_pos = self.opts.footer, self.opts.footer_pos or "right" end
		local max_height = math.max(1, tonumber(self.opts.max_height) or vim.api.nvim_win_get_height(self.win))
		if self.opts.float and not self.opts.fixed_size then
			local title_lines = title and title ~= "" and 1 or 0
			cfg.width, cfg.height = math.min(72, math.max(40, vim.o.columns - 4)), math.min(max_height, math.max(1, #lines - title_lines))
		end
		pcall(resources.place, self.win, cfg)
		if render_opts.place_cursor or self.opts.place_cursor then
			local span = active_span(self)
			local line = span and span.line or self.data_start
			pcall(vim.api.nvim_win_set_cursor, self.win, { math.max(1, math.min(line, #lines)), span and span.byte_start or 0 })
		end
	end
	return self
end
---Read the native cursor's rendered item span, update selection, call on_cursor and render on change.
---An absent window, header, rule or unchanged selection does nothing.
---@return nil result # No value is returned.
function YGrid:sync_cursor()
	if not valid_win(self.win) or self.closed then return end
	local span = cursor_span(self)
	if not span or (self.state.active_row == span.row_i and self.state.active_col == span.col) then return end
	if not select_span(self, span) then return end
	if self.opts.on_cursor then self.opts.on_cursor(self, span.row_i) end
	self:render()
end
---Wrap active column/row, resolve active_val, call on_move and render with cursor placement.
---With no columns this does nothing; unknown directions still normalize selection and render.
---@param direction string "left", "right", "tab", "up", "down", "j" or "k"; j/k clamp at the native list ends.
---@return nil result # No value is returned.
function YGrid:move(direction)
	local cols = columns(self)
	if #cols == 0 then return end
	local row_count = tonumber(self.opts.row_count and self.opts.row_count(self.state) or self.state.data_rows) or 1
	self.state.active_col_i = math.min(math.max(1, self.state.active_col_i or 1), math.max(1, #cols))
	self.state.active_row = math.min(math.max(1, self.state.active_row or 1), math.max(1, row_count))
	if direction == "left" then self.state.active_col_i = ((self.state.active_col_i - 2) % #cols) + 1
	elseif direction == "right" or direction == "tab" then self.state.active_col_i = (self.state.active_col_i % #cols) + 1
	elseif direction == "up" then self.state.active_row = ((self.state.active_row - 2) % row_count) + 1
	elseif direction == "down" then self.state.active_row = (self.state.active_row % row_count) + 1
	elseif direction == "j" then self.state.active_row = math.min(self.state.active_row + 1, row_count)
	elseif direction == "k" then self.state.active_row = math.max(self.state.active_row - 1, 1) end
	self.state.active_col = cols[self.state.active_col_i]
	local column_count = self.opts.column_count and self.opts.column_count(self.state, self.state.active_col)
	if column_count then self.state.active_row = math.min(self.state.active_row, math.max(1, column_count)) end
	if self.opts.value_at then self.state.active_val = self.opts.value_at(self.state, self.state.active_col, self.state.active_row) end
	if self.opts.on_move then self.opts.on_move(self) end
	self:render({ place_cursor = true })
end
---Find a span using one-based line and display-cell coordinates; its end is exclusive.
---@param line integer One-based rendered line.
---@param col integer One-based display column.
---@return YGridSpan|nil span # First containing span, or nil.
function YGrid:span_at(line, col)
	for _, span in ipairs(self.spans or {}) do if span.line == line and col >= span.col_start and col < span.col_end then return span end end
end
cursor_span = function(grid)
  if not valid_win(grid.win) then return nil end
  local cursor = vim.api.nvim_win_get_cursor(grid.win)
  local text = grid.lines[cursor[1]] or ""
  return grid:span_at(cursor[1], metrics.cell_at_byte(text, cursor[2]))
end
select_span = function(grid, span)
  if not span or span.dim or span.live == false then return false end
  grid.state.active_col, grid.state.active_val, grid.state.active_row = span.col, span.value, span.row_i
  for i, col in ipairs(columns(grid)) do if col == span.col then grid.state.active_col_i = i end end
  return true
end
---Arm a span, update selection only for live non-dim cells, call on_press and render.
---Nil clears the armed span and still calls on_press and renders.
---@param span? YGridSpan [default: nil] Pressed cell span, or nil for empty space.
---@return nil result # No value is returned.
function YGrid:press(span)
	clear_flash(self)
	if not span then
		self.armed = nil
		if self.opts.on_press then self.opts.on_press(self, nil) end
		if not self.closed then self:render() end
		return
	end
	if span.dim or span.live == false then
		self.armed = vim.tbl_extend("force",{},span)
		if self.opts.on_press then self.opts.on_press(self, span) end
		if not self.closed then self:render() end
		return
	end
	select_span(self, span)
	self.armed = vim.tbl_extend("force",{},span)
	if self.opts.on_press then self.opts.on_press(self, span) end
	if not self.closed then self:render({ place_cursor = true }) end
end
---Clear the armed span; invoke on_release only for matching identities or release_anywhere.
---Action ids take precedence over column/value/row matching. With no armed span, do nothing.
---Dim and non-live press snapshots are retained; you decide callback eligibility.
---@param span? YGridSpan [default: nil] Released span, or nil outside cells.
---@return nil result # No value is returned.
function YGrid:release(span)
	local armed = self.armed
	self.armed = nil
	if not armed then return end
	local same = same_span(span,armed)
	if same and armed.live~=false and not armed.dim and span.live~=false and not span.dim then start_flash(self,span) end
	if (same or self.opts.release_anywhere) and self.opts.on_release then self.opts.on_release(self, span, armed) end
	if not self.closed then self:render() end
end
local function hover_identity(span)
	if not span then return nil end
	if span.action then return ("a:%s:%s"):format(tostring(span.action), tostring(span.row_i or 0)) end
	return ("c:%s:%s"):format(tostring(span.col), tostring(span.value))
end
---Update hover state, call on_hover and render only when the hover identity changes.
---Identity uses action plus row, or column plus value.
---@param span? YGridSpan [default: nil] Hovered span, or nil outside cells.
---@return nil result # No value is returned.
function YGrid:mouse_move(span)
	if hover_identity(self.hover) == hover_identity(span) then return end
	self.state.hover_col, self.state.hover_val = span and span.col, span and span.value
	self.hover = span
	if self.opts.on_hover then self.opts.on_hover(self, span) end
	self:render()
end
---Route on_key and default keyboard navigation/actions; pointer intake belongs to input.
---Escape/q cancel; Enter and Backspace call their callbacks without automatic rendering.
---Space/mark/Delete render after their callbacks.
---@param key string Native key spelling such as "<CR>" or "q".
---@return nil result # No value is returned.
function YGrid:key(key)
	if self.opts.on_key and self.opts.on_key(self, key) then return end
	if key == "<Esc>" or key == "q" then return self:close(true) end
	if key == "<CR>" then
		if select_span(self, cursor_span(self)) and self.opts.on_enter then self.opts.on_enter(self) end
		return
	end
	if key == "<Space>" then if self.opts.on_space then self.opts.on_space(self, active_span(self)) end; self:render(); return end
	if key == (self.opts.mark_key or "m") and self.opts.on_mark then
		self.opts.on_mark(self, active_span(self)); self:render(); return
	end
	if key == "<Del>" and self.opts.on_delete then
		self.opts.on_delete(self, active_span(self)); self:render(); return
	end
	-- Optional back: fires only when the caller supplied on_back. Without it,
	-- Backspace is inert: it never cancels and never errors.
	if key == "<BS>" then if self.opts.on_back then self.opts.on_back(self) end; return end
	local dirs = { h = "left", ["<Left>"] = "left", l = "right", ["<Right>"] = "right", ["<Tab>"] = "tab", ["<S-Tab>"] = "left", ["<Up>"] = "up", ["<Down>"] = "down" }
	if dirs[key] then self:move(dirs[key]); return end
	if key == "j" or key == "k" then
		self:move(key)
	end
end
local function dispatch_mouse(grid, kind, pos)
	if not valid_win(grid.win) then return false end
	if pos.winid ~= grid.win or not pos.content then
		if kind == "release" and grid.armed then grid:release(nil); return true end
		if kind == "move" then grid:mouse_move(nil) end
		return false
	end
	local span = grid:span_at(pos.content.line, pos.content.display_col)
	if kind == "press" then grid:press(span)
	elseif kind == "release" then grid:release(span)
	elseif kind == "move" then grid:mouse_move(span)
	else return false end
	return true
end
---Borrow the supplied handles and install controller mappings/autocmds, then render.
---Set close_window=false and delete_buffer=false to preserve borrowed resources on close.
---Use one attachment per controller; repeated attachment does not first clean the old target.
---@param buf integer Buffer handle.
---@param win integer Window handle displaying that buffer.
---@return YGrid grid # This controller for chaining.
function YGrid:attach(buf, win)
	clear_flash(self);self.armed=nil
	self.buf, self.win = buf, win
	input.acquire(self, function(kind, pos) return dispatch_mouse(self, kind, pos) end, self.opts.map_desc,
		function() return self.armed and 1 or 0, valid_win(self.win) and (vim.api.nvim_win_get_config(self.win).zindex or 0) or 0 end)
	if self.opts.focus_guard or valid_buf(buf) then
		self.augroup = vim.api.nvim_create_augroup("ToolkitGrid" .. self.id, { clear = true })
	end
	if valid_win(win) then
		vim.api.nvim_create_autocmd("WinClosed", { group = self.augroup, pattern = tostring(win),
			callback = function() self:close(false) end })
	end
	if self.opts.focus_guard then
		vim.api.nvim_create_autocmd("WinEnter", { group = self.augroup, callback = function()
			if not self.closed and valid_win(self.win) and vim.api.nvim_get_current_win() ~= self.win and not transient_float(vim.api.nvim_get_current_win()) then self:close(true) end
		end })
	end
	if valid_buf(buf) then
		local map = function(lhs, key, desc) input.map(self, "n", lhs, function() self:key(key) end, { buffer = buf, nowait = true, silent = true, desc = desc }) end
		map("<Esc>", "<Esc>", "yana-ui: grid cancel"); map("q", "q", "yana-ui: grid cancel"); map("<CR>", "<CR>", "yana-ui: grid apply"); map("<Space>", "<Space>", "yana-ui: grid activate")
		map("<BS>", "<BS>", "yana-ui: grid back")
		if self.opts.on_mark then map(self.opts.mark_key or "m", self.opts.mark_key or "m", "yana-ui: grid mark") end
		if self.opts.on_delete then map("<Del>", "<Del>", "yana-ui: grid delete") end
		for _, key in ipairs({ "h", "l", "<Left>", "<Right>", "<Up>", "<Down>", "<Tab>", "<S-Tab>", "j", "k" }) do map(key, key, "yana-ui: grid navigation") end
		if self.opts.type_to_filter then
			local reserved = self.opts.reserved_keys or { h = true, j = true, k = true, l = true, q = true }
			for byte = 33, 126 do
				local ch = string.char(byte)
				if not reserved[ch] then map(ch, ch, "yana-ui: grid filter") end
			end
		end
		vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, { group = self.augroup, buffer = buf, callback = function() self:sync_cursor() end })
	end
	self:render({ place_cursor = true })
	return self
end
---Mark closed, release input and autocmds, then close/delete enabled resources.
---Call on_cancel after cleanup only when cancelled is truthy. Repeated calls do nothing.
---@param cancelled? boolean [default: nil] Whether to notify cancellation.
---@return nil result # No value is returned.
function YGrid:close(cancelled)
	if self.closed then return end
	self.closed = true
	clear_flash(self);self.armed=nil
	if self._flash_owner then self._flash_owner:destroy();self._flash_owner,self._flash_timer=nil,nil end
	if self.augroup then pcall(vim.api.nvim_del_augroup_by_id, self.augroup); self.augroup = nil end
	input.release(self)
	if valid_win(self.win) and self.opts.close_window ~= false then pcall(resources.close, self.win) end
	if valid_buf(self.buf) and self.opts.delete_buffer ~= false then pcall(vim.api.nvim_buf_delete, self.buf, { force = true }) end
	if cancelled and self.opts.on_cancel then self.opts.on_cancel(self) end
end
---Render again using the same controller options and state.
---@param opts? YGridRenderOptions [default: nil] Per-render cursor request.
---@return YGrid grid # This controller for chaining.
function YGrid:refresh(opts) return self:render(opts) end
---Resolve a rendered cell by line/col_start and pass it to press().
---@param cell? YGridSpan [default: nil] Cell position, or nil to clear the press.
---@return nil result # No value is returned.
function YGrid:test_press(cell) self:press(cell and self:span_at(cell.line, cell.col_start) or nil) end
---Resolve a rendered cell by line/col_start and pass it to release().
---@param cell? YGridSpan [default: nil] Cell position, or nil for an outside release.
---@return nil result # No value is returned.
function YGrid:test_release(cell) self:release(cell and self:span_at(cell.line, cell.col_start) or nil) end
---Create an unattached controller; options and state tables are shared, not copied.
---@param opts? YGridOptions [default: nil] Cell data, callbacks and resource choices.
---@return YGrid grid # New controller without native resources.
function M.new(opts)
  assert(not opts or opts.layout ~= "bands", "YGrid requires display spans; bands supplies byte spans")
  local ms=opts and opts.flash_ms
  if ms==nil then ms=0 end
  assert(type(ms)=="number" and ms>=0 and ms<=2147483647 and ms==math.floor(ms),"flash_ms must be nonnegative integer milliseconds <=2147483647")
	next_id = next_id + 1
	return setmetatable({ opts = opts or {}, state = (opts and opts.state) or {}, id = next_id, data_start = 1, lines = {}, spans = {} }, YGrid)
end
---Create a scratch buffer and focused editor-relative float, then attach a new controller.
---The supplied options table is changed to float=true, close_window=true and delete_buffer=true.
---If attachment fails after opening, resources are not automatically rolled back.
---@param opts? YGridOptions [default: nil] Content, callbacks and initial float options.
---@return YGrid grid # Attached controller owning its new buffer/window.
function M.open(opts)
	opts = opts or {}
	local g = M.new(opts)
	local width = tonumber(opts.width) or math.min(72, math.max(40, vim.o.columns - 4))
	local height = tonumber(opts.height) or math.min(24, math.max(8, math.floor(vim.o.lines * 2 / 3)))
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden, vim.bo[buf].modifiable = "wipe", false
	local win_opts = { relative = "editor", row = math.max(1, math.floor((vim.o.lines - height) / 3)), col = math.max(1, math.floor((vim.o.columns - width) / 2)), width = width, height = height, style = "minimal", border = "rounded", title = opts.window_title, title_pos = opts.title_pos }
	if opts.footer and opts.footer ~= "" then win_opts.footer, win_opts.footer_pos = opts.footer, opts.footer_pos or "right" end
	local win = resources.open(buf, true, win_opts)
	resources.options(win, { winhighlight = "NormalFloat:Pmenu,FloatBorder:Pmenu", cursorline = true })
	g.opts.float, g.opts.close_window, g.opts.delete_buffer = true, true, true
	return g:attach(buf, win)
end
M._test = {
  namespace = function() return NS end,
  span_at = function(grid, line, column) return grid and grid:span_at(line, column) or nil end,
  press_at = function(grid, line, column)
    local span = M._test.span_at(grid, line, column)
    if not span then return nil end
    grid:press(span)
    return span
  end,
}
-- DOCS: YGrid example start
-- local ui = require("yana_ui")
-- local grid = ui.YGrid.open({ layout = "columns", columns = { "Name" },
--   state = { data_rows = 1 }, cells = function()
--     return { { { col = "Name", row_i = 1, text = "Alpha", value = "alpha" } } }
--   end })
-- assert(#grid.lines >= 2 and #grid.spans == 1)
-- grid:close(false)
-- DOCS: YGrid example end
return M
