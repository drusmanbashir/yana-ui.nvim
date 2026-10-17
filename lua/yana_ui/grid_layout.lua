-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- yana-ui: reusable cell-grid layout support.
-- Callers provide state, cells(state), highlight groups, and semantic hooks.
-- This module knows no models, vendors, hunks, or reviews.
---@class YGridCell
---@field text? string [default: ""] Display text; column/flow layouts fall back to label, then value.
---@field label? string [default: nil] Column/flow text fallback.
---@field value? any [default: nil] Caller selection value; supply string-compatible text when used as a text fallback.
---@field col? string [default: nil] Column name for column layout.
---@field row_i? integer [default: 1] One-based logical row for column layout.
---@field key? string [default: nil] Caller key metadata.
---@field key_offset? integer [default: 0] Key-highlight offset from the cell start, in display cells.
---@field key_width? integer [default: 0] Key-highlight width in display cells.
---@field action? any [default: nil] Caller action identity.
---@field live? boolean [default: true] Cell eligibility metadata.
---@field dim? boolean [default: false] Dim highlight metadata.
---@field fixed? boolean [default: false] Fixed highlight metadata.
---@field current? boolean [default: false] Current highlight metadata.
---@field active? boolean [default: false] Selection highlight metadata.
---@field marked? boolean [default: false] Overlay highlight metadata.
---@field flash? boolean [default: false] Flash highlight metadata.
---@field clip? string [default: nil] Column truncation mode; leading places the ellipsis first.
---@field width? integer [default: measured text width] Band allocation width including prefix/suffix.
---@field prefix? string [default: ""] Band prefix; control whitespace becomes spaces.
---@field suffix? string [default: ""] Band suffix; control whitespace becomes spaces.
---@field shrink? number [default: 0] Band shrink priority; lower values shrink first, later equal priorities win.
---@field wrap? boolean [default: false] Band cell may create a second physical line.
---@field repeat_text? string [default: nil] Band text repeated width times before clipping.
---@class YGridSpan
---@field line integer One-based rendered line.
---@field col? string Cell column name.
---@field value? any Caller value.
---@field row_i integer Logical row metadata; flow uses its calculated fallback when omitted.
---@field col_start integer One-based display start.
---@field col_end integer Exclusive display end.
---@field key_col_start integer One-based key-highlight start.
---@field key_col_end integer Exclusive key-highlight end.
---@field key? string Caller key metadata.
---@field action? any Caller action identity.
---@field live boolean Eligibility metadata.
---@field dim boolean Dim metadata.
---@field fixed boolean Fixed metadata.
---@field current boolean Current metadata.
---@field active boolean Active metadata.
---@field marked boolean Marked metadata.
---@field flash boolean Flash metadata.
---@field text string Resolved text.
---@field armed? boolean Controller press state.
---@field hover? boolean Controller hover state.
---@field byte_start? integer Zero-based start byte, added when YGrid renders a live buffer.
---@field byte_end? integer Exclusive end byte, added by YGrid.
---@field key_byte_start? integer Zero-based key start byte, added by YGrid.
---@field key_byte_end? integer Exclusive key end byte, added by YGrid.
---@class YGridByteSpan
---@field line integer One-based physical band line.
---@field byte_col integer Zero-based start byte.
---@field end_byte_col integer Exclusive end byte.
---@field prefix_bytes integer Prefix byte length.
---@field suffix_bytes integer Suffix byte length.
---@field cell YGridCell Original band cell.
---@class YGridBand
---@field cells? YGridCell[] [default: row itself] Left-side cells, or supply an array directly.
---@field gap? integer [default: 1] Nonnegative cell gap.
---@field wrap? boolean [default: false] Wrap whole cells onto more physical lines.
---@field right? YGridCell[] [default: {}] Cells aligned against the right edge.
---@class YGridFitOptions
---@field scroll_data? boolean [default: false] Preserve header lines while trimming data.
---@field header_lines? integer [default: 2] Preserved header count.
---@field active_row? integer [default: 1] Data row to keep visible when reveal_row is absent.
---@field reveal_row? integer [default: nil] Data row to reveal at the top where possible.
---@class YGridLayoutOptions : YGridFitOptions
---@field layout? "columns"|"flow"|"bands" [default: nil] Nil/other values use column layout.
---@field width? integer [default: 40] Available cell width, clamped to at least one.
---@field max_height? integer [default: nil] Height cap; nil keeps all lines.
---@field columns? string[] [default: {}] Column names and ordering.
---@field column_widths? table|fun(width: integer, columns: string[]): table [default: nil] Fixed widths keyed by name or index.
---@field column_separator? string|table [default: nil] String vertical separator or table with vertical/junction fields (or indices 1/2).
---@class YSplitChild
---@field node YSplitNode Nested branch or leaf.
---@field size? integer [default: nil] Positive fixed size along the parent axis.
---@field min? integer [default: 1] Positive lower bound along the parent axis.
---@field weight? number [default: 1] Positive finite weight for unfixed sizes.
---@class YSplitNode
---@field id? string [default: nil] Nonempty unique leaf id; a leaf must not have children.
---@field min_width? integer [default: 1] Positive native leaf minimum width.
---@field min_height? integer [default: 1] Positive native leaf minimum height.
---@field axis? "row"|"column" [default: nil] Branch axis; row places children side by side, column stacks them.
---@field children? YSplitChild[] [default: nil] Nonempty ordered list required for branches.
---@class YSplitLayoutOptions
---@field width integer Positive finite whole-number width, including branch separators.
---@field height integer Positive finite whole-number height, including branch separators.
---@class YSplitRect
---@field row integer Zero-based top row.
---@field col integer Zero-based left column.
---@field width integer Width in cells.
---@field height integer Height in cells.
---@class YSplitPlan
---@field rects table<string,YSplitRect> Leaf ids mapped to rectangles.
---@field order string[] Leaf ids in traversal order.
---@class YGridLayout
---@field namespace integer Shared yana_ui.grid namespace.
---@field valid_win fun(win: any): boolean Whether a positive window handle is live.
---@field valid_buf fun(buf: any): boolean Whether a positive buffer handle is live.
---@field transient_float fun(win: any): boolean Whether a live window is floating.
---@field byte_at_display fun(text: string, cell: integer, column?: integer): integer Alias of YTextMetrics.byte_at_display().
---@doc brief Pure cell and split-tree calculations supporting YGrid and YPanelHost.
---@doc qt QGridLayout/text layout helpers. You receive text lines and spans or a zero-based split plan; these functions do not create native windows. This is the existing grid_layout module, not a separate YGridLayout constructor.
---@doc inherits none; YGrid.fit and YGrid.layout alias fit() and layout(). There are no properties or signals.
---@doc errors Text-layout malformed inputs and native string errors propagate. split_layout() returns nil plus one of invalid layout dimensions, invalid layout tree, invalid layout leaf, invalid layout branch, invalid layout size, invalid layout weight or layout does not fit. Its validation is pure and makes no native writes.
---@doc context lua/yana_ui/grid_layout.lua|YGridLayout
---@doc setup With your checkout on runtimepath, run this excerpt in Neovim. It computes a split plan only; it owns no windows.
---@doc example local layout = require("yana_ui.grid_layout")
---@doc example local tree = { axis = "row", children = {
---@doc example   { node = { id = "left" }, size = 4 },
---@doc example   { node = { id = "right" }, weight = 1 },
---@doc example } }
---@doc example local plan = assert(layout.split_layout(tree, { width = 10, height = 3 }))
---@doc example assert(plan.rects.left.width == 4 and plan.rects.right.col == 5)
---@doc see |YGrid|, |YPanelHost|, |YTextMetrics|.
local M = {}
local YTextMetrics = require("yana_ui.text_metrics")
local NS = vim.api.nvim_create_namespace("yana_ui.grid")
---Check for a positive live native window handle; zero is not resolved to current.
---@param win any Handle to inspect.
---@return boolean valid # True for a positive valid window handle.
local function valid_win(win)
	return type(win) == "number" and win > 0 and vim.api.nvim_win_is_valid(win)
end
---Check for a positive live native buffer handle; zero is not resolved to current.
---@param buf any Handle to inspect.
---@return boolean valid # True for a positive valid buffer handle.
local function valid_buf(buf)
	return type(buf) == "number" and buf > 0 and vim.api.nvim_buf_is_valid(buf)
end
local byte_at_display, pad, clip = YTextMetrics.byte_at_display, YTextMetrics.pad, YTextMetrics.clip
---Check whether a live window has a nonempty native relative configuration.
---@param win any Handle to inspect.
---@return boolean floating # True for a native floating window; false when absent.
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
	for _, cell in ipairs(flat) do cell_width = math.max(cell_width, YTextMetrics.width(cell_text(cell))) end
	cell_width = math.max(1, cell_width)
	local cols = math.max(1, math.floor((width + 1) / (cell_width + 1)))
	local lines, spans, current, col = {}, {}, "", 0
	for _, cell in ipairs(flat) do
		if col == cols then lines[#lines + 1], current, col = current, "", 0 end
		local sep = col == 0 and "" or " "
		local start = YTextMetrics.width(current .. sep) + 1
    current = current .. sep .. YTextMetrics.cell_clip(YTextMetrics.expand_tabs(cell_text(cell), start - 1), cell_width)
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
	for _, col in ipairs(columns or {}) do widths[col] = YTextMetrics.width(col) + 2 end
	local fixed = fixed_widths(opts, columns, width)
	if fixed then for col, value in pairs(fixed) do widths[col] = value end else
		for _, row in ipairs(rows or {}) do
			for _, cell in ipairs(row) do
				if cell.col then widths[cell.col] = math.max(widths[cell.col] or 1, YTextMetrics.width(cell_text(cell))) end
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
			local start = YTextMetrics.width(line .. sep) + 1
      line = line .. sep .. clip(YTextMetrics.expand_tabs(text, start - 1), widths[col] or 1, cell and cell.clip)
			if cell then spans[#spans + 1] = cell_span(cell, #lines + 1, start, widths[col] or 1, row_i) end
			col_start = col_start + (widths[col] or 1)
		end
		lines[#lines + 1] = line
	end
	return M.fit(lines, spans, max_height, opts)
end
---Trim supplied lines in place and adjust supplied span line numbers; return a new
---kept-span list. Without scroll_data, discard top lines. With scroll_data, retain
---headers and select a data slice. Empty output becomes one empty line.
---@param lines string[] Mutable text lines.
---@param spans? YGridSpan[]|YGridByteSpan[] [default: nil] Mutable positions; nil supplies no spans.
---@param cap? integer [default: nil] Height cap; nil keeps every line.
---@param opts? YGridFitOptions [default: nil] Header and reveal controls.
---@return string[] fitted # The supplied lines table after fitting.
---@return YGridSpan[]|YGridByteSpan[] kept # New list of retained, adjusted spans.
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

-- M3-SURFACES: cell bands share this module's allocation and byte coordinates.
local function clean_text(value)
	return tostring(value or ""):gsub("[\r\n\t]", " ")
end
local prefix_cells, cell_clip = YTextMetrics.prefix_cells, YTextMetrics.cell_clip
local function cell_width(cell)
	return math.max(0, math.floor(tonumber(cell.width) or YTextMetrics.width(
		clean_text(cell.prefix) .. clean_text(cell.text) .. clean_text(cell.suffix))))
end
local function allocate_cells(cells, width, gap)
	local widths = {}
	for i, cell in ipairs(cells) do widths[i] = cell_width(cell) end
	local function used()
		local total, visible = 0, 0
		for _, value in ipairs(widths) do
			if value > 0 then total, visible = total + value, visible + 1 end
		end
		return total + math.max(0, visible - 1) * gap
	end
	while used() > width do
		local shrink
		for i, cell in ipairs(cells) do
			if widths[i] > 0 and (not shrink or (cell.shrink or 0) <= (cells[shrink].shrink or 0)) then shrink = i end
		end
		if not shrink then break end
		widths[shrink] = widths[shrink] - math.min(widths[shrink], used() - width)
	end
	return widths
end
local function render_cell(cell, width, text)
	text = clean_text(text or cell.text)
	if cell.repeat_text then text = string.rep(cell.repeat_text, width) end
	local prefix, suffix = clean_text(cell.prefix), clean_text(cell.suffix)
	if width < YTextMetrics.width(prefix .. suffix) then prefix, suffix = "", "" end
	return prefix .. cell_clip(text, width - YTextMetrics.width(prefix .. suffix)) .. suffix, #prefix, #suffix
end
local function append_cell(line, spans, cell, width, line_i, text)
	local rendered, prefix, suffix = render_cell(cell, width, text)
	if #rendered > 0 then
		spans[#spans + 1] = { line = line_i, byte_col = #line, end_byte_col = #line + #rendered,
			prefix_bytes = prefix, suffix_bytes = suffix, cell = cell }
	end
	return line .. rendered
end
local function band_layout(rows, width, max_height)
	local lines, spans = {}, {}
	for _, row in ipairs(rows or {}) do
		local cells, gap = row.cells or row, math.max(0, math.floor(row.gap or 1))
		if row.wrap then
			local first, current, count = #lines + 1, "", 0
			for _, cell in ipairs(cells) do
				local size = math.max(1, math.min(width, cell_width(cell)))
				if count > 0 and YTextMetrics.width(current) + gap + size > width then
					lines[#lines + 1], current, count = pad(current, width), "", 0
				end
				if count > 0 then current = current .. string.rep(" ", gap) end
				current = append_cell(current, spans, cell, size, #lines + 1)
				count = count + 1
			end
			if current ~= "" or #lines < first then lines[#lines + 1] = current end
			if row.right and #row.right > 0 then
				local right_widths = allocate_cells(row.right, width, gap)
				local right, right_spans = "", {}
				for i, cell in ipairs(row.right) do
					if right_widths[i] > 0 then
						if right ~= "" then right = right .. string.rep(" ", gap) end
						right = append_cell(right, right_spans, cell, right_widths[i], first)
					end
				end
				local first_used, first_end, right_used = 0, 0, YTextMetrics.width(right)
				-- Padding is not content: measure the first band's last cell.
				for _, span in ipairs(spans) do
					if span.line == first then
						first_end = span.end_byte_col
						first_used = YTextMetrics.width(lines[first]:sub(1, first_end))
					end
				end
				local target = first
				if first_used > 0 and first_used + gap + right_used > width then
					target = #lines + 1
					lines[target] = ""
				end
				local left = target == first and lines[first]:sub(1, first_end) or ""
				local space = string.rep(" ", math.max(0, width - YTextMetrics.width(left) - right_used))
				lines[target] = left .. space .. right
				for _, span in ipairs(right_spans) do
					span.line, span.byte_col, span.end_byte_col = target, span.byte_col + #left + #space, span.end_byte_col + #left + #space
					spans[#spans + 1] = span
				end
			end
			for i = first, #lines do lines[i] = pad(lines[i], width) end
		else
			local all = {}
			for _, cell in ipairs(cells) do all[#all + 1] = cell end
			for _, cell in ipairs(row.right or {}) do all[#all + 1] = cell end
			local widths = allocate_cells(all, width, gap)
			local first_text, second_text, has_second = {}, {}, false
			for i, cell in ipairs(all) do
				if cell.wrap and widths[i] > 0 then
					local head, rest = prefix_cells(clean_text(cell.text), widths[i])
					first_text[i], second_text[i], has_second = head, rest, has_second or rest ~= ""
				end
			end
			local right_size, right_count = 0, 0
			for i = #cells + 1, #all do
				if widths[i] > 0 then right_size, right_count = right_size + widths[i], right_count + 1 end
			end
			right_size = right_size + math.max(0, right_count - 1) * gap
			for physical = 1, has_second and 2 or 1 do
				local line, visible, right_started = "", 0, false
				for i, cell in ipairs(all) do
					if widths[i] > 0 then
						if i > #cells and right_count > 0 then
							if not right_started then
								line = line .. string.rep(" ", math.max(0, width - YTextMetrics.width(line) - right_size))
								right_started = true
							elseif visible > 0 then line = line .. string.rep(" ", gap) end
						elseif visible > 0 then line = line .. string.rep(" ", gap) end
						local text = physical == 1 and first_text[i] or second_text[i]
						if physical == 2 then text = text or "" end
						line = append_cell(line, spans, cell, widths[i], #lines + 1, text)
						visible = visible + 1
					end
				end
				lines[#lines + 1] = pad(line, width)
			end
		end
	end
	return M.fit(lines, spans, max_height)
end
---Compute column, flow or band text and spans without writing a buffer.
---Columns group cells by row_i and col; flow flattens rows into equal-width cells.
---Bands return byte spans for surface consumers, rather than YGrid controller spans.
---@param rows? YGridCell[][]|YGridBand[] [default: nil] Cell rows or bands; nil supplies no rows.
---@param opts? YGridLayoutOptions [default: nil] Layout, width, cap and column controls.
---@return string[] lines # Fitted text lines.
---@return YGridSpan[]|YGridByteSpan[] spans # Display-column spans, or byte spans for bands.
function M.layout(rows, opts)
	opts = opts or {}
	local width = math.max(1, tonumber(opts.width) or 40)
	if opts.layout == "bands" then return band_layout(rows, math.floor(width), opts.max_height) end
	if opts.layout == "flow" then return flow_layout(rows, width, opts.max_height) end
	return column_layout(rows, opts.columns or {}, width, opts.max_height, opts)
end

local function parse_split(tree)
	local function integer(value) return type(value) == "number" and value >= 1 and value < math.huge and value == math.floor(value) end
	local seen, visiting = {}, {}
	local function parse(node)
		if type(node) ~= "table" or visiting[node] then return nil, "invalid layout tree" end
		visiting[node] = true
		if node.id ~= nil then
			if type(node.id) ~= "string" or node.id == "" or seen[node.id] or node.children then return nil, "invalid layout leaf" end
			if (node.min_width~=nil and not integer(node.min_width)) or (node.min_height~=nil and not integer(node.min_height)) then return nil,'invalid layout size'end
			seen[node.id], visiting[node] = true, nil
			return { id = node.id, min_width = node.min_width or 1, min_height = node.min_height or 1 }
		end
		if (node.axis ~= "row" and node.axis ~= "column") or type(node.children) ~= "table"
			or not vim.islist(node.children) or #node.children == 0 then return nil, "invalid layout branch" end
		local out = { axis = node.axis, children = {}, min_width = 1, min_height = 1 }
		local along, across = #node.children - 1, 1
		for _, child in ipairs(node.children) do
			if type(child) ~= "table" or (child.size ~= nil and not integer(child.size))
				or (child.min ~= nil and not integer(child.min)) then return nil, "invalid layout size" end
			local weight = child.weight or 1
			if child.size == nil and (type(weight) ~= "number" or weight <= 0 or weight >= math.huge) then return nil, "invalid layout weight" end
			local parsed, err = parse(child.node)
			if not parsed then return nil, err end
			local required = math.max(child.min or 1, node.axis == "row" and parsed.min_width or parsed.min_height)
			if child.size and child.size < required then return nil, "layout does not fit" end
			out.children[#out.children + 1] = { node = parsed, size = child.size, min = required, weight = weight }
			along = along + (child.size or required)
			across = math.max(across, node.axis == "row" and parsed.min_height or parsed.min_width)
		end
		out.min_width, out.min_height = node.axis == "row" and along or across, node.axis == "row" and across or along
		visiting[node] = nil
		return out
	end
	return parse(tree)
end

-- M3a/COLLAPSE: one pure split-tree validation and allocation authority.
---Validate an acyclic split tree with unique leaf ids and allocate all leaf rectangles.
---Reserve one separator cell between siblings; honor fixed/minimum sizes and divide
---remaining cells by positive weights, assigning rounding remainders in child order.
---@param tree YSplitNode Leaf or split branch.
---@param opts YSplitLayoutOptions Positive integer total width and height.
---@return YSplitPlan|nil plan # Leaf rectangles/order, or nil on validation/fit failure.
---@return string|nil reason # Shared split-layout validation/fit error, or nil.
function M.split_layout(tree, opts)
	local function integer(value) return type(value) == "number" and value >= 1 and value < math.huge and value == math.floor(value) end
	if type(opts) ~= "table" or not integer(opts.width) or not integer(opts.height) then return nil, "invalid layout dimensions" end
	local root, error_message = parse_split(tree)
	if not root then return nil, error_message end
	local result = { rects = {}, order = {} }
	local function place(node, rect)
		if rect.width < node.min_width or rect.height < node.min_height then return nil end
		if node.id then
			result.rects[node.id], result.order[#result.order + 1] = rect, node.id
			return true
		end
		local available = (node.axis == "row" and rect.width or rect.height) - #node.children + 1
		local sizes, active = {}, {}
		for i, child in ipairs(node.children) do
			if child.size then sizes[i], available = child.size, available - child.size else active[#active + 1] = i end
		end
		if #active == 0 and available ~= 0 then return nil end
		while #active > 0 do
			local weights, required = 0, 0
			for _, i in ipairs(active) do weights, required = weights + node.children[i].weight, required + node.children[i].min end
			if required > available then return nil end
			local kept, pinned = {}, false
			for _, i in ipairs(active) do
				local child = node.children[i]
				if available * child.weight / weights < child.min then
					sizes[i], pinned = child.min, true
				else kept[#kept + 1] = i end
			end
			if pinned then
				for _, i in ipairs(active) do if sizes[i] then available = available - sizes[i] end end
				active = kept
			else
				local remainder = available
				for _, i in ipairs(active) do sizes[i] = math.floor(available * node.children[i].weight / weights); remainder = remainder - sizes[i] end
				for _, i in ipairs(active) do if remainder > 0 then sizes[i], remainder = sizes[i] + 1, remainder - 1 end end
				active = {}
			end
		end
		local offset = 0
		for i, child in ipairs(node.children) do
			local next_rect = { row = rect.row, col = rect.col, width = rect.width, height = rect.height }
			if node.axis == "row" then next_rect.col, next_rect.width = rect.col + offset, sizes[i]
			else next_rect.row, next_rect.height = rect.row + offset, sizes[i] end
			if not place(child.node, next_rect) then return nil end
			offset = offset + sizes[i] + 1
		end
		return true
	end
	if not place(root, { row = 0, col = 0, width = opts.width, height = opts.height }) then return nil, "layout does not fit" end
	return result
end

-- DOCS: YGridLayout example start
-- local layout = require("yana_ui.grid_layout")
-- local tree = { axis = "row", children = {
--   { node = { id = "left" }, size = 4 },
--   { node = { id = "right" }, weight = 1 },
-- } }
-- local plan = assert(layout.split_layout(tree, { width = 10, height = 3 }))
-- assert(plan.rects.left.width == 4 and plan.rects.right.col == 5)
-- DOCS: YGridLayout example end
return {
  fit = M.fit,
  layout = M.layout,
  split_layout = M.split_layout,
  _parse_split = parse_split,
  namespace = NS,
  valid_win = valid_win,
  valid_buf = valid_buf,
  transient_float = transient_float,
  byte_at_display = byte_at_display,
}
