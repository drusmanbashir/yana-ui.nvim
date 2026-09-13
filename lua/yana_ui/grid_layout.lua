-- yana-ui: reusable cell-grid layout support.
-- Callers provide state, cells(state), highlight groups, and semantic hooks.
-- This module knows no models, vendors, hunks, or reviews.
local M = {}
local NS = vim.api.nvim_create_namespace("yana_ui.grid")
local MOUSE_MODES = { "n", "i" }
local shared = { refs = 0, mouse = nil, mousemoveevent = nil, grids = {} }
local next_id = 0
local function valid_win(win)
	return type(win) == "number" and win > 0 and vim.api.nvim_win_is_valid(win)
end
local function valid_buf(buf)
	return type(buf) == "number" and buf > 0 and vim.api.nvim_buf_is_valid(buf)
end
local function byte_at_display(line, display_col)
	if display_col <= 1 then return 0 end
	local display, byte = 0, 0
	while byte < #line do
		local char = vim.fn.strcharpart(line, vim.fn.charidx(line, byte), 1)
		local width = vim.fn.strdisplaywidth(char)
		if display + 1 >= display_col then return byte end
		display, byte = display + width, byte + #char
	end
	return #line
end
local function pad(text, width)
	return text .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(text)))
end
local function clip(text, width, mode)
	if vim.fn.strdisplaywidth(text) <= width then return pad(text, width) end
	if width <= 1 then return string.rep(" ", width) end
	if mode == "leading" then
		local tail, used = "…", vim.fn.strdisplaywidth("…")
		for i = #text, 1, -1 do
			local char, next_width = text:sub(i, i), vim.fn.strdisplaywidth(text:sub(i, i))
			if used + next_width > width then break end
			tail, used = tail .. char, used + next_width
		end
		return pad(tail, width)
	end
	local tail, used = "…", vim.fn.strdisplaywidth("…")
	for i = #text, 1, -1 do
		local char, next_width = text:sub(i, i), vim.fn.strdisplaywidth(text:sub(i, i))
		if used + next_width > width then break end
		tail, used = char .. tail, used + next_width
	end
	return pad(tail, width)
end
local function transient_float(win)
	if not valid_win(win) then return false end
	local cfg = vim.api.nvim_win_get_config(win)
	return type(cfg.relative) == "string" and cfg.relative ~= ""
end
local function cell_text(cell)
	return cell.text or cell.label or cell.value or ""
end
local function cell_span(cell, line, start, width, row_i)
	local text = cell_text(cell)
	local key_offset = tonumber(cell.key_offset)
	local key_width = tonumber(cell.key_width)
	return {
		line = line,
		col = cell.col,
		value = cell.value,
		row_i = cell.row_i or row_i,
		col_start = start,
		col_end = start + width,
		key_col_start = start + (key_offset or 0),
		key_col_end = start + (key_offset or 0) + (key_width or 0),
		key = cell.key,
		action = cell.action,
		live = cell.live ~= false,
		dim = cell.dim == true,
		fixed = cell.fixed == true,
		current = cell.current == true,
		active = cell.active == true,
		marked = cell.marked == true,
		flash = cell.flash == true,
		text = text,
	}
end
local function flow_layout(rows, width, max_height)
	local flat = {}
	for _, row in ipairs(rows or {}) do
		for _, cell in ipairs(type(row) == "table" and row or {}) do flat[#flat + 1] = cell end
	end
	local cell_width = 0
	for _, cell in ipairs(flat) do cell_width = math.max(cell_width, vim.fn.strdisplaywidth(cell_text(cell))) end
	cell_width = math.max(1, cell_width)
	local cols = math.max(1, math.floor((width + 1) / (cell_width + 1)))
	local lines, spans, current, col = {}, {}, "", 0
	for _, cell in ipairs(flat) do
		if col == cols then lines[#lines + 1], current, col = current, "", 0 end
		local sep = col == 0 and "" or " "
		local start = vim.fn.strdisplaywidth(current .. sep) + 1
		current = current .. sep .. pad(cell_text(cell), cell_width)
		col = col + 1
		spans[#spans + 1] = cell_span(cell, #lines + 1, start, cell_width, math.ceil(#flat / cols))
	end
	if current ~= "" then lines[#lines + 1] = current end
	return M.fit(lines, spans, max_height)
end
local function separator_chars(opts)
	local sep = opts and opts.column_separator
	if type(sep) == "table" then return sep.vertical or sep[1] or "│", sep.junction or sep[2] or "┼" end
	if type(sep) == "string" then return sep, "┼" end
	return " ", " "
end
local function fixed_widths(opts, columns, width)
	local wanted = opts and opts.column_widths
	if type(wanted) == "function" then wanted = wanted(width, columns) end
	if type(wanted) ~= "table" then return nil end
	local result = {}
	for i, col in ipairs(columns) do local value = wanted[col] or wanted[i]; if value then result[col] = math.max(1, math.floor(tonumber(value) or 1)) end end
	return result
end
local function column_layout(rows, columns, width, max_height, opts)
	local widths = {}
	for _, col in ipairs(columns or {}) do widths[col] = vim.fn.strdisplaywidth(col) + 2 end
	local fixed = fixed_widths(opts, columns, width)
	if fixed then for col, value in pairs(fixed) do widths[col] = value end else
		for _, row in ipairs(rows or {}) do
			for _, cell in ipairs(row) do
				if cell.col then widths[cell.col] = math.max(widths[cell.col] or 1, vim.fn.strdisplaywidth(cell_text(cell))) end
			end
		end
	end
	local vertical, junction = separator_chars(opts)
	local lines, spans = {}, {}
	local header = ""
	for i, col in ipairs(columns or {}) do
		local sep = i == 1 and "" or vertical
		header = header .. sep .. clip(" " .. col .. " ", widths[col] or 1)
	end
	if #columns > 0 then lines[#lines + 1] = header end
	if opts and opts.column_separator and #columns > 1 then
		local split = (widths[columns[1]] or 1) + 1
		local rule = string.rep("─", math.max(0, split - 1)) .. junction .. string.rep("─", math.max(0, width - split))
		lines[#lines + 1] = rule
	end
	local by_row = {}
	for _, row in ipairs(rows or {}) do
		for _, cell in ipairs(row) do by_row[cell.row_i or 1] = by_row[cell.row_i or 1] or {}; by_row[cell.row_i or 1][cell.col] = cell end
	end
	local max_row = 0
	for row_i in pairs(by_row) do max_row = math.max(max_row, row_i) end
	for row_i = 1, max_row do
		local line, col_start = "", 0
		for i, col in ipairs(columns or {}) do
			local sep = i == 1 and "" or vertical
			local cell = by_row[row_i] and by_row[row_i][col]
			local text = cell and cell_text(cell) or ""
			local start = vim.fn.strdisplaywidth(line .. sep) + 1
			line = line .. sep .. clip(text, widths[col] or 1, cell and cell.clip)
			if cell then spans[#spans + 1] = cell_span(cell, #lines + 1, start, widths[col] or 1, row_i) end
			col_start = col_start + (widths[col] or 1)
		end
		lines[#lines + 1] = line
	end
	return M.fit(lines, spans, max_height, opts)
end
function M.fit(lines, spans, cap, opts)
	local drop = math.max(0, #lines - (tonumber(cap) or #lines))
	if opts and opts.scroll_data and drop > 0 then
		local header = math.min(tonumber(opts.header_lines) or 2, #lines)
		local active = math.max(1, tonumber(opts.active_row) or 1)
		local data_total = math.max(0, #lines - header)
		local data_cap = math.max(1, (tonumber(cap) or #lines) - header)
		local reveal = tonumber(opts.reveal_row)
		local data_drop
		if reveal then
			reveal = math.max(1, math.min(reveal, data_total))
			data_drop = math.min(math.max(0, reveal - 1), math.max(0, data_total - data_cap))
		else
			data_drop = math.min(math.max(0, active - data_cap), math.max(0, data_total - data_cap))
		end
		for _ = 1, data_drop do table.remove(lines, header + 1) end
		for _ = 1, math.max(0, data_total - data_cap - data_drop) do table.remove(lines, header + data_cap + 1) end
		drop = data_drop
	else
		for _ = 1, drop do table.remove(lines, 1) end
	end
	local kept = {}
	for _, span in ipairs(spans or {}) do
		if (not opts or not opts.scroll_data) or span.line > (tonumber(opts.header_lines) or 2) then span.line = span.line - drop end
		if span.line >= 1 and span.line <= #lines then kept[#kept + 1] = span end
	end
	if #lines == 0 then lines[1] = "" end
	return lines, kept
end
function M.layout(rows, opts)
	opts = opts or {}
	local width = math.max(1, tonumber(opts.width) or 40)
	if opts.layout == "flow" then return flow_layout(rows, width, opts.max_height) end
	return column_layout(rows, opts.columns or {}, width, opts.max_height, opts)
end

return {
  fit = M.fit,
  layout = M.layout,
  namespace = NS,
  mouse_modes = MOUSE_MODES,
  shared = shared,
  valid_win = valid_win,
  valid_buf = valid_buf,
  transient_float = transient_float,
  byte_at_display = byte_at_display,
}
