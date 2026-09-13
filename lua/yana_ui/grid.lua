-- yana-ui: reusable cell-grid controller.
-- Product meaning stays in callers; this module only renders and routes cells.
local support = require("yana_ui.grid_layout")
local M = { fit = support.fit, layout = support.layout }
local NS = support.namespace
local MOUSE_MODES = support.mouse_modes
local shared = support.shared
local valid_win = support.valid_win
local valid_buf = support.valid_buf
local transient_float = support.transient_float
local byte_at_display = support.byte_at_display
local next_id = 0

local Grid = {}
Grid.__index = Grid
local function columns(g)
	return type(g.opts.columns) == "function" and g.opts.columns(g.state) or g.opts.columns or {}
end
local function rows(g)
	local result = g.opts.cells and g.opts.cells(g.state) or {}
	return type(result) == "table" and result or {}
end
local function active_span(g)
	for _, span in ipairs(g.spans or {}) do if span.active then return span end end
end
function Grid:render(render_opts)
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
	for _, span in ipairs(spans) do
		span.armed = self.armed and span.action == self.armed.action and span.value == self.armed.value and span.row_i == self.armed.row_i and span.col == self.armed.col or span.armed
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
	for _, span in ipairs(spans) do
		span.byte_start = byte_at_display(lines[span.line], span.col_start)
		span.byte_end = byte_at_display(lines[span.line], span.col_end)
		span.key_byte_start = byte_at_display(lines[span.line], span.key_col_start)
		span.key_byte_end = byte_at_display(lines[span.line], span.key_col_end)
		local group = self.opts.hl_groups and self.opts.hl_groups.live
		if span.dim then group = self.opts.hl_groups and self.opts.hl_groups.dim
		elseif span.armed or span.flash then group = self.opts.hl_groups and self.opts.hl_groups.flash
		elseif span.hover or span.active then group = self.opts.hl_groups and self.opts.hl_groups.hover
		elseif span.current then group = self.opts.hl_groups and (self.opts.hl_groups.current or self.opts.hl_groups.flash)
		elseif span.fixed then group = self.opts.hl_groups and self.opts.hl_groups.flash end
		if group then pcall(vim.api.nvim_buf_set_extmark, self.buf, ns, span.line - 1, span.byte_start, { end_col = span.byte_end, hl_group = group, priority = 0 }) end
		local marked = self.opts.hl_groups and self.opts.hl_groups.marked
		if span.marked and marked then
			pcall(vim.api.nvim_buf_set_extmark, self.buf, ns, span.line - 1, span.byte_start, {
				end_col = span.byte_end, hl_group = marked, priority = 20, hl_mode = "combine",
			})
		end
		local key = self.opts.hl_groups and self.opts.hl_groups.key
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
		pcall(vim.api.nvim_win_set_config, self.win, cfg)
		if render_opts.place_cursor or self.opts.place_cursor then
			local span = active_span(self)
			local line = span and span.line or self.data_start
			pcall(vim.api.nvim_win_set_cursor, self.win, { math.max(1, math.min(line, #lines)), span and span.byte_start or 0 })
		end
	end
	return self
end
function Grid:sync_cursor()
	if not valid_win(self.win) then return end
	local line = vim.api.nvim_win_get_cursor(self.win)[1]
	local row = line - self.data_start + 1
	if row < 1 then return end
	self.state.active_row = row
	if self.opts.on_cursor then self.opts.on_cursor(self, row) end
	self:render()
end
function Grid:move(direction)
	local cols = columns(self)
	if #cols == 0 then return end
	local row_count = tonumber(self.opts.row_count and self.opts.row_count(self.state) or self.state.data_rows) or 1
	self.state.active_col_i = math.min(math.max(1, self.state.active_col_i or 1), math.max(1, #cols))
	self.state.active_row = math.min(math.max(1, self.state.active_row or 1), math.max(1, row_count))
	if direction == "left" then self.state.active_col_i = ((self.state.active_col_i - 2) % #cols) + 1
	elseif direction == "right" or direction == "tab" then self.state.active_col_i = (self.state.active_col_i % #cols) + 1
	elseif direction == "up" then self.state.active_row = ((self.state.active_row - 2) % row_count) + 1
	elseif direction == "down" then self.state.active_row = (self.state.active_row % row_count) + 1 end
	self.state.active_col = cols[self.state.active_col_i]
	local column_count = self.opts.column_count and self.opts.column_count(self.state, self.state.active_col)
	if column_count then self.state.active_row = math.min(self.state.active_row, math.max(1, column_count)) end
	if self.opts.value_at then self.state.active_val = self.opts.value_at(self.state, self.state.active_col, self.state.active_row) end
	if self.opts.on_move then self.opts.on_move(self) end
	self:render({ place_cursor = true })
end
function Grid:span_at(line, col)
	for _, span in ipairs(self.spans or {}) do if span.line == line and col >= span.col_start and col < span.col_end then return span end end
end
function Grid:press(span)
	if not span then
		self.armed = nil
		if self.opts.on_press then self.opts.on_press(self, nil) end
		self:render()
		return
	end
	if span.dim or span.live == false then
		self.armed = span
		if self.opts.on_press then self.opts.on_press(self, span) end
		self:render()
		return
	end
	self.state.active_col, self.state.active_val, self.state.active_row = span.col, span.value, span.row_i
	for i, col in ipairs(columns(self)) do if col == span.col then self.state.active_col_i = i end end
	self.armed = span
	if self.opts.on_press then self.opts.on_press(self, span) end
	self:render()
end
function Grid:release(span)
	local armed = self.armed
	self.armed = nil
	if not armed then return end
	local same = false
	if span and armed then
		if span.action and armed.action then same = span.action == armed.action
		else same = span.col == armed.col and span.value == armed.value and span.row_i == armed.row_i end
	end
	if armed and (same or self.opts.release_anywhere) and self.opts.on_release then self.opts.on_release(self, span) end
	self:render()
end
local function hover_identity(span)
	if not span then return nil end
	if span.action then return ("a:%s:%s"):format(tostring(span.action), tostring(span.row_i or 0)) end
	return ("c:%s:%s"):format(tostring(span.col), tostring(span.value))
end
function Grid:mouse_move(span)
	if hover_identity(self.hover) == hover_identity(span) then return end
	self.state.hover_col, self.state.hover_val = span and span.col, span and span.value
	self.hover = span
	if self.opts.on_hover then self.opts.on_hover(self, span) end
	self:render()
end
function Grid:key(key)
	if key == "<LeftMouse>" or key == "<LeftRelease>" or key == "<MouseMove>" then
		local pos = vim.fn.getmousepos()
		local span = pos.winid == self.win and self:span_at(pos.line, pos.column) or nil
		if key == "<LeftMouse>" then self:press(span)
		elseif key == "<LeftRelease>" then self:release(span)
		else self:mouse_move(span) end
		return
	end
	if self.opts.on_key and self.opts.on_key(self, key) then return end
	if key == "<Esc>" or key == "q" then return self:close(true) end
	if key == "<CR>" then if self.opts.on_enter then self.opts.on_enter(self) end; return end
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
		if valid_win(self.win) then
			local cursor = vim.api.nvim_win_get_cursor(self.win)
			local bottom = self.data_start + (tonumber(self.opts.row_count and self.opts.row_count(self.state) or self.state.data_rows) or 1) - 1
			local line = key == "j" and math.min(cursor[1] + 1, bottom) or math.max(cursor[1] - 1, self.data_start)
			pcall(vim.api.nvim_win_set_cursor, self.win, { line, cursor[2] })
		end
		self:sync_cursor()
	end
end
local function dispatch_mouse(kind)
	local pos = vim.fn.getmousepos()
	for _, grid in pairs(shared.grids) do
		if valid_win(grid.win) and pos.winid == grid.win then
			local span = grid:span_at(pos.line, pos.column)
			if kind == "press" then grid:press(span)
			elseif kind == "release" then grid:release(span)
			else grid:mouse_move(span) end
			return
		end
	end
  return
end
local function install_shared(map_desc)
	map_desc = map_desc or {}
	for _, mode in ipairs(MOUSE_MODES) do
		vim.keymap.set(mode, "<LeftMouse>", function() dispatch_mouse("press") end, { nowait = true, silent = true, desc = map_desc["<LeftMouse>"] or "yana: grid press" })
		vim.keymap.set(mode, "<LeftRelease>", function() dispatch_mouse("release") end, { nowait = true, silent = true, desc = map_desc["<LeftRelease>"] or "yana: grid release" })
		vim.keymap.set(mode, "<MouseMove>", function() dispatch_mouse("move") end, { nowait = true, silent = true, desc = map_desc["<MouseMove>"] or "yana: grid hover" })
	end
end
local function acquire(g)
	if shared.refs == 0 then
		shared.mouse, shared.mousemoveevent = vim.o.mouse, vim.o.mousemoveevent
		if not vim.o.mouse:find("a", 1, true) then
			for _, mode in ipairs(MOUSE_MODES) do if not vim.o.mouse:find(mode, 1, true) then vim.o.mouse = vim.o.mouse .. mode end end
		end
		pcall(vim.api.nvim_set_option_value, "mousemoveevent", true, { scope = "global" })
		install_shared(g.opts.map_desc)
	end
	shared.refs, shared.grids[g.id] = shared.refs + 1, g
end
local function release(g)
	if not shared.grids[g.id] then return end
	shared.grids[g.id], shared.refs = nil, shared.refs - 1
	if shared.refs > 0 then return end
	if shared.mouse ~= nil then vim.o.mouse = shared.mouse end
	if shared.mousemoveevent ~= nil then pcall(vim.api.nvim_set_option_value, "mousemoveevent", shared.mousemoveevent, { scope = "global" }) end
	shared.mouse, shared.mousemoveevent = nil, nil
	for _, mode in ipairs(MOUSE_MODES) do
		pcall(vim.keymap.del, mode, "<LeftMouse>"); pcall(vim.keymap.del, mode, "<LeftRelease>"); pcall(vim.keymap.del, mode, "<MouseMove>")
	end
end
function Grid:attach(buf, win)
	self.buf, self.win = buf, win
	if self.opts.global_mouse then acquire(self) end
	if self.opts.focus_guard or valid_buf(buf) then
		self.augroup = vim.api.nvim_create_augroup("YanaGrid" .. self.id, { clear = true })
	end
	if self.opts.focus_guard then
		vim.api.nvim_create_autocmd("WinEnter", { group = self.augroup, callback = function()
			if not self.closed and valid_win(self.win) and vim.api.nvim_get_current_win() ~= self.win and not transient_float(vim.api.nvim_get_current_win()) then self:close(true) end
		end })
	end
	if valid_buf(buf) then
		local map_desc = self.opts.map_desc or {}
		local map = function(lhs, key, desc) vim.keymap.set("n", lhs, function() self:key(key) end, { buffer = buf, nowait = true, silent = true, desc = map_desc[lhs] or desc }) end
		map("<Esc>", "<Esc>", "yana: grid cancel"); map("q", "q", "yana: grid cancel"); map("<CR>", "<CR>", "yana: grid apply"); map("<Space>", "<Space>", "yana: grid activate")
		map("<BS>", "<BS>", "yana: grid back")
		if self.opts.on_mark then map(self.opts.mark_key or "m", self.opts.mark_key or "m", "yana: grid mark") end
		if self.opts.on_delete then map("<Del>", "<Del>", "yana: grid delete") end
		for _, key in ipairs({ "h", "l", "<Left>", "<Right>", "<Up>", "<Down>", "<Tab>", "<S-Tab>", "j", "k" }) do map(key, key, "yana: grid navigation") end
		map("<LeftMouse>", "<LeftMouse>", "yana: grid press"); map("<LeftRelease>", "<LeftRelease>", "yana: grid release"); map("<MouseMove>", "<MouseMove>", "yana: grid hover")
		for _, key in ipairs({ "<2-LeftMouse>", "<3-LeftMouse>", "<LeftDrag>" }) do map(key, key, "yana: grid ignore mouse") end
		if self.opts.type_to_filter then
			local reserved = self.opts.reserved_keys or { h = true, j = true, k = true, l = true, q = true }
			for byte = 33, 126 do
				local ch = string.char(byte)
				if not reserved[ch] then map(ch, ch, "yana: grid filter") end
			end
		end
		vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, { group = self.augroup, buffer = buf, callback = function() self:sync_cursor() end })
	end
	self:render({ place_cursor = true })
	return self
end
function Grid:close(cancelled)
	if self.closed then return end
	self.closed = true
	if self.augroup then pcall(vim.api.nvim_del_augroup_by_id, self.augroup); self.augroup = nil end
	if self.opts.global_mouse then release(self) end
	if valid_win(self.win) and self.opts.close_window ~= false then pcall(vim.api.nvim_win_close, self.win, true) end
	if valid_buf(self.buf) and self.opts.delete_buffer ~= false then pcall(vim.api.nvim_buf_delete, self.buf, { force = true }) end
	if cancelled and self.opts.on_cancel then self.opts.on_cancel(self) end
end
function Grid:refresh(opts) return self:render(opts) end
function Grid:test_press(cell) self:press(cell and self:span_at(cell.line, cell.col_start) or nil) end
function Grid:test_release(cell) self:release(cell and self:span_at(cell.line, cell.col_start) or nil) end
function M.new(opts)
	next_id = next_id + 1
	return setmetatable({ opts = opts or {}, state = (opts and opts.state) or {}, id = next_id, data_start = 1, lines = {}, spans = {} }, Grid)
end
function M.open(opts)
	opts = opts or {}
	local g = M.new(opts)
	local width = tonumber(opts.width) or math.min(72, math.max(40, vim.o.columns - 4))
	local height = tonumber(opts.height) or math.min(24, math.max(8, math.floor(vim.o.lines * 2 / 3)))
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden, vim.bo[buf].modifiable = "wipe", false
	local win_opts = { relative = "editor", row = math.max(1, math.floor((vim.o.lines - height) / 3)), col = math.max(1, math.floor((vim.o.columns - width) / 2)), width = width, height = height, style = "minimal", border = "rounded", title = opts.window_title, title_pos = opts.title_pos }
	if opts.footer and opts.footer ~= "" then win_opts.footer, win_opts.footer_pos = opts.footer, opts.footer_pos or "right" end
	local win = vim.api.nvim_open_win(buf, true, win_opts)
	vim.wo[win].winhighlight, vim.wo[win].cursorline = "NormalFloat:Pmenu,FloatBorder:Pmenu", true
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
return M
