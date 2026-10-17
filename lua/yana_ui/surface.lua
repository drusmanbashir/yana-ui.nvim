-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- Render application-independent cell surfaces.
local grid = require("yana_ui.grid_layout")
local M = {}

local function width(opts)
  assert(type(opts.width) == "number" and opts.width >= 1 and opts.width < math.huge,
    "surface.width must be a positive number")
  return math.floor(opts.width)
end
local function mark(result, line, col, finish, group, priority, eol)
  if type(group) == "string" and finish > col then
    result.marks[#result.marks + 1] = { line = line, col = col, end_col = finish,
      hl_group = group, priority = priority or 100, hl_eol = eol == true }
  end
end
local function render(opts, rows)
  local lines, spans = grid.layout(rows, { layout = "bands", width = width(opts) })
  local result, groups = { lines = lines, marks = {}, actions = {} }, opts.groups or {}
  for i, line in ipairs(lines) do mark(result, i, 0, #line, groups.normal, 10, true) end
  for _, span in ipairs(spans) do
    local cell = span.cell
    mark(result, span.line, span.byte_col, span.end_byte_col, cell.group, 100)
    if cell.edge_group then
      mark(result, span.line, span.byte_col, span.byte_col + span.prefix_bytes, cell.edge_group, 110)
      mark(result, span.line, span.end_byte_col - span.suffix_bytes, span.end_byte_col, cell.edge_group, 110)
    end
    if cell.action then
      result.actions[#result.actions + 1] = { line = span.line, col = span.byte_col,
        end_col = span.end_byte_col, id = cell.action.id, enabled = cell.action.enabled ~= false }
    end
  end
  return result, spans
end
local function button_cells(buttons, groups, pill)
  local cells = {}
  for _, button in ipairs(buttons or {}) do
    cells[#cells + 1] = { text = " " .. tostring(button.label or "") .. " ",
      prefix = pill and "" or "", suffix = pill and "" or "", shrink = 10,
      group = button.enabled == false and groups.disabled or groups.button,
      edge_group = pill and (button.enabled == false and (groups.disabled_edge or groups.disabled) or groups.edge), action = button }
  end
  return cells
end

-- M3-LOOK rows 4–5: one header band; clip caption before the right tiles.
function M.header(opts)
  local groups = opts.groups or {}
  return (render(opts, { { cells = {
    { text = opts.title, group = groups.title, shrink = 1 },
    { text = opts.subtitle, group = groups.subtitle, shrink = 0 },
  }, right = button_cells(opts.buttons, groups, false) } }))
end

-- M3-LOOK rows 1–2: wrapping preserves every action, including disabled ones.
function M.buttons(opts)
  local groups = opts.groups or {}
  local status = opts.status and opts.status ~= "" and { { text = opts.status, group = groups.status } } or nil
  return (render(opts, { { cells = button_cells(opts.buttons, groups, true), wrap = true, right = status } }))
end

-- M3-LOOK rows 7–8 and 10: byte ranges retain column foreground over a band.
function M.table_rows(opts)
  local groups, rows = opts.groups or {}, {}
  local columns = opts.columns or {}
  local function cells(values, heading)
    local out = {}
    for i, column in ipairs(columns) do
      out[i] = { text = heading and column.title or values[i], width = column.width,
        group = heading and groups.subtitle or column.hl_group,
        wrap = not heading and opts.wrap == true }
    end
    return out
  end
  if opts.header then rows[#rows + 1] = { cells = cells({}, true), heading = true } end
  if opts.rule then rows[#rows + 1] = { cells = { { text = "", width = width(opts), repeat_text = "─", group = groups.rule } }, heading = true } end
  local data_start = #rows + 1
  for _, values in ipairs(opts.rows or {}) do rows[#rows + 1] = { cells = cells(values, false) } end
  local result, spans = render(opts, rows)
  local lines = {}
  -- Use cell identity rather than a fixed row pitch: rows can have one or two lines.
  local owners = {}
  for i = data_start, #rows do
    for _, cell in ipairs(rows[i].cells) do owners[cell] = i - data_start + 1 end
  end
  for _, span in ipairs(spans) do if owners[span.cell] then lines[span.line] = owners[span.cell] end end
  for line_i, line in ipairs(result.lines) do
    local data_row = lines[line_i]
    if data_row then
      result.actions[#result.actions + 1] = { line = line_i, col = 0, end_col = #line, id = data_row, enabled = true }
      if data_row == opts.selected then mark(result, line_i, 0, #line, groups.selected, 20, true) end
    end
  end
  return result
end

-- M3-LOOK row 9: caller-owned cached detail occupies two lines.
function M.detail(opts)
  local groups = opts.groups or {}
  return (render(opts, {
    { gap = 0, cells = {
      { text = opts.name, group = groups.name or groups.title, shrink = 2 },
      { text = " · ", group = groups.subtitle, shrink = 1 },
      { text = opts.type, group = groups.type or groups.subtitle, shrink = 0 },
    } },
    { cells = { { text = opts.summary, width = width(opts), group = groups.value or groups.normal } } },
  }))
end

function M.separator(opts)
  local groups = opts.groups or {}
  return (render(opts, { { cells = { { text = "", repeat_text = "─", width = width(opts), group = groups.rule } } } }))
end

return M
