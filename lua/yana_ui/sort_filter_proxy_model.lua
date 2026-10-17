-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-FileCopyrightText: 2016 The Qt Company Ltd
-- SPDX-License-Identifier: LGPL-3.0-only
-- Derived from Qt (qtbase v6.8.4-lts-lgpl ed77a3ca) src/corelib/itemmodels/
-- qsortfilterproxymodel.cpp: sort 2516-2526, Private::sort 608-622,
-- sort_source_rows 681-698, LessThan/GreaterThan 34-76, lessThan 3190-3196,
-- _q_sourceReset 1587-1595 (a reset rebuilds through create_mapping, which
-- always sorts: set_rows is a reset), Mapping 120-127, create_mapping 474-518,
-- build_source_to_proxy_mapping 1210-1217, mapToSource/mapFromSource
-- 3259-3276, invalidate 3083-3089, setSortRole 2932-2940, filterAcceptsRow
-- 3212-3235; qabstractproxymodel.cpp sort 428-432. Delta from
-- qabstractitemmodel.cpp isVariantLessThan 758-794: missing keys stay last.
-- one owner for the batch, sort choice, filter and projection.
local YObject = require("yana_ui.object")
local Sort = require("yana_ui.table_sort")
local ItemRow = require("yana_ui.item_row")
---@class YSortFilterProxySorter
---@field key fun(row:table):any Extract one raw comparison key per record.
---@field method? "text"|"natural"|"numeric"|"hex"|"custom" [default: "text"] |YTableSort| comparison method.
---@field case_sensitive? boolean [default: false] Text/natural only.
---@field less? fun(a:any,b:any):boolean [default: nil] Custom only, required; strict weak order over raw keys.
---@class YSortFilterProxyModelOptions : YObjectOptions
---@field tree? boolean [default: false] Validate a visible YTreeRow forest and sort siblings only.
---@field sorters? table<string|integer,YSortFilterProxySorter> [default: nil] Initial sorters by column ID.
---@field fixed? fun(row:table):boolean [default: nil] Tree only; anchors keep their sibling position.
---@class YSortFilterProxyModel : YObject
---@doc brief Own one unsorted record batch and publish its filtered, sorted display order.
---@doc qt QSortFilterProxyModel. Consumers push whole batches with set_rows instead of a source model; key callbacks replace sort roles and a predicate replaces filterAcceptsRow. Missing keys stay last in both directions; Qt puts invalid data first when descending. Each batch is a source reset, projected under the current filter and sort before layout_changed, so a bound view's indicator never claims an unapplied order; there is no dynamic-sort switch, since a whole-batch model has no incremental path for it to govern.
---@doc inherits |YObject|; parent, lifetime and destroyed retain |YObject| semantics.
---@doc property sort_column|sort_column()|sort(column_id, order), set_sorters(sorters)|layout_changed|nil
---@doc property sort_order|sort_order()|sort(column_id, order), set_sorters(sorters)|layout_changed|nil
---@doc property sortable|is_sortable(column_id)|set_sorters(sorters)|layout_changed|false
---@doc property filter|filter()|set_filter(predicate)|layout_changed|nil
---@doc property rows|rows()|set_rows(rows, generation)|layout_changed|{}
---@doc property generation|generation()|set_rows(rows, generation)|layout_changed|0
---@signal layout_changed(generation: string|integer) | Emitted once after set_rows and after each changed sort, sorter set or filter, with the current batch generation. Unchanged requests, refusals and callback errors emit nothing.
---@doc errors Rows are dense arrays of |YTableRow| values (|YTreeRow| when tree) with distinct nonempty string or finite integer IDs, validated by the same rule as the views, so a bound view never refuses a published batch; a tree batch must also satisfy |YTableSort.forest()|. Generations and column IDs follow the same identity rule. Sorters follow |YTableSort| configuration without order. Validation raises before the destroyed check and before any state change. Key, less, fixed and filter callback errors propagate and keep the previous projection; filter and fixed must return booleans. Getters remain readable after destruction.
---@doc destroyed set_rows,set_sorters,sort,set_filter
---@doc context lua/yana_ui/sort_filter_proxy_model.lua|YSortFilterProxyModel
---@doc setup Run this excerpt in Neovim with yana-ui on runtimepath. The owner owns the model and its connection; destroying it releases both.
---@doc example local ui = require("yana_ui")
---@doc example local owner = ui.YObject.new()
---@doc example local model = ui.YSortFilterProxyModel.new({ parent = owner, sorters = {
---@doc example   name = { key = function(row) return row.cells.name end, method = "natural" } } })
---@doc example local generation
---@doc example model:connect("layout_changed", owner, function(_, value) generation = value end)
---@doc example model:set_rows({ { id = 1, cells = { name = "item10" } }, { id = 2, cells = { name = "item2" } } }, 7)
---@doc example model:sort("name", "ascending")
---@doc example assert(model:rows()[1].id == 2 and model:map_to_source(1) == 2 and generation == 7)
---@doc example owner:destroy()
---@doc see |YTableSort|, |YTableView|, |YTreeView|, |YObject|.
local YSortFilterProxyModel = setmetatable({}, { __index = YObject })
YSortFilterProxyModel.__index = YSortFilterProxyModel
local OPTIONS = { parent = true, tree = true, sorters = true, fixed = true }
local SORTER = { "key", "method", "case_sensitive", "less" }
local ORDERS = { ascending = true, descending = true }
-- Every projection field, written together by store().
local STATE = { "_source", "_index", "_prepared", "_generation", "_sorters", "_column", "_order",
  "_filter", "_view", "_display", "_to_source", "_from_source" }

local identity = YObject.identity
local function integer(index)
  assert(type(index) == "number", "invalid index"); identity(index)
end

-- Validate a whole batch; returns a detached array, id index and tree forest.
-- F2: rows pass the views' own shape rule, so no bound view can refuse them.
local function batch(rows, tree)
  assert(type(rows) == "table" and vim.islist(rows), "rows must be a dense array")
  local source, index = {}, {}
  for i, row in ipairs(rows) do
    ItemRow.check(row, tree)
    assert(index[row.id] == nil, "duplicate row identity")
    source[i], index[row.id] = row, i
  end
  return source, index, tree and Sort.forest(rows) or nil
end

-- Validate through YTableSort's configuration path; returns a detached map.
local function sorters_copy(sorters)
  assert(type(sorters) == "table", "sorters must be a table")
  local copy = {}
  for column_id, sorter in pairs(sorters) do
    identity(column_id)
    assert(type(sorter) == "table" and sorter.order == nil, "sorter must be a table without order")
    Sort.sorted({}, sorter)
    copy[column_id] = {}
    for _, field in ipairs(SORTER) do copy[column_id][field] = sorter[field] end
  end
  return copy
end
local function same_sorters(a, b)
  for column_id, sorter in pairs(a) do
    if not b[column_id] then return false end
    for _, field in ipairs(SORTER) do
      if sorter[field] ~= b[column_id][field] then return false end
    end
  end
  for column_id in pairs(b) do if not a[column_id] then return false end end; return true
end

-- Qt filterAcceptsRow, non-recursive: a rejected tree row hides its subtree.
local function accepted(source, tree, predicate)
  if not predicate then return source end
  local rows, hidden = {}, nil
  for _, row in ipairs(source) do
    if not (hidden and row.depth > hidden) then
      hidden = nil
      local keep = predicate(row)
      assert(type(keep) == "boolean", "filter predicate must return boolean")
      if keep then rows[#rows + 1] = row elseif tree then hidden = row.depth end
    end
  end
  return rows
end

local function ordered(self, view, sorter, order)
  local opts = { order = order }; for _, field in ipairs(SORTER) do opts[field] = sorter[field] end
  if not self._tree then return Sort.sorted(view.rows, opts) end
  opts.fixed = self._fixed
  -- A filtered tree is a forest of whole subtrees; validate it once per view.
  view.forest = view.forest or Sort.forest(view.rows)
  return Sort.tree(view.forest, opts)
end

local function state(self)
  local s = {}; for _, field in ipairs(STATE) do s[field] = self[field] end; return s
end
local function store(self, s) for _, field in ipairs(STATE) do self[field] = s[field] end end

-- Qt create_mapping 474-518 filters then sorts, and build_source_to_proxy_mapping
-- 1210-1217 derives the reverse map. Everything is computed before store().
local function apply(self, s)
  local view = s._view
  if not view then
    local rows = accepted(s._source, self._tree, s._filter)
    view = { rows = rows, forest = rows == s._source and s._prepared or nil }
  end
  local display = view.rows
  if s._column ~= nil then display = ordered(self, view, s._sorters[s._column], s._order) end
  local to_source, from_source = {}, {}
  for i, row in ipairs(display) do
    local source = s._index[row.id]
    to_source[i], from_source[source] = source, i
  end
  s._view, s._display, s._to_source, s._from_source = view, display, to_source, from_source
  store(self, s)
  self:emit("layout_changed", self._generation)
  return true
end

---Create an empty model. Invalid options, sorters or parents raise before
---allocation; fixed requires tree.
---@param opts? YSortFilterProxyModelOptions [default: nil] Constructor options.
---@return YSortFilterProxyModel model # New model with generation 0 and no rows.
function YSortFilterProxyModel.new(opts)
  if opts == nil then opts = {} end
  assert(type(opts) == "table", "YSortFilterProxyModel options must be a table")
  for name in pairs(opts) do assert(OPTIONS[name], "unknown proxy option: " .. tostring(name)) end
  if opts.tree ~= nil then YObject.boolean(opts.tree) end
  local tree = opts.tree == true
  assert(opts.fixed == nil or (tree and type(opts.fixed) == "function"), "fixed requires tree and a function")
  local sorters = sorters_copy(opts.sorters == nil and {} or opts.sorters)
  local self = setmetatable(YObject.new({ parent = opts.parent }), YSortFilterProxyModel)
  self._tree, self._fixed = tree, opts.fixed
  store(self, { _source = {}, _index = {}, _prepared = tree and Sort.forest({}) or nil, _generation = 0,
    _sorters = sorters, _display = {}, _to_source = {}, _from_source = {} })
  return self
end

---Replace the authoritative unsorted batch, borrowing its records. Invalid
---batches or generations raise. The batch is projected under the current
---filter and sort before layout_changed (Qt source reset).
---@param rows YTableRow[] Dense records with distinct id; YTreeRow fields when tree.
---@param generation string|integer Stable nonempty string or finite integer.
---@return boolean changed # True after replacement; false when destroyed.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YSortFilterProxyModel:set_rows(rows, generation)
  local source, index, prepared = batch(rows, self._tree)
  identity(generation)
  if self:is_destroyed() then return false, "destroyed" end
  local s = state(self)
  s._source, s._index, s._prepared, s._generation, s._view = source, index, prepared, generation, nil
  return apply(self, s)
end

---Replace all sorters (Qt setSortRole/lessThan). Invalid sorters raise. A
---changed set re-sorts; a column losing its sorter clears an active sort on it.
---@param sorters table<string|integer,YSortFilterProxySorter> Sorters by column ID.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YSortFilterProxyModel:set_sorters(sorters)
  local copy = sorters_copy(sorters)
  if self:is_destroyed() then return false, "destroyed" end
  if same_sorters(copy, self._sorters) then return false end
  local s = state(self)
  s._sorters = copy
  if s._column ~= nil and not copy[s._column] then s._column, s._order = nil, nil end
  return apply(self, s)
end

---Sort by one column, or restore source order with nil. A column requires an
---explicit order; invalid IDs or orders raise. An unchanged column and order
---are ignored: every batch is already projected under them.
---@param column_id string|integer|nil Column with a sorter, or nil for source order.
---@param order "ascending"|"descending"|nil Required with a column; nil without one.
---@return boolean changed # True after sorting; false if unchanged, unsortable or destroyed.
---@return "destroyed"|"unsortable"|nil reason # Refusal, or nil.
function YSortFilterProxyModel:sort(column_id, order)
  if column_id == nil then assert(order == nil, "sort(nil) takes no order")
  else identity(column_id); assert(ORDERS[order], "sort order must be ascending or descending") end
  if self:is_destroyed() then return false, "destroyed" end
  if column_id ~= nil and not self._sorters[column_id] then return false, "unsortable" end
  if self._column == column_id and self._order == order then return false end
  local s = state(self)
  s._column, s._order = column_id, order
  return apply(self, s)
end

---Read the active sort column.
---@return string|integer|nil column_id # Active column, or nil for source order.
function YSortFilterProxyModel:sort_column() return self._column end
---Read the active sort order.
---@return "ascending"|"descending"|nil order # Active order, or nil for source order.
function YSortFilterProxyModel:sort_order() return self._order end
---Read whether a column has a sorter. Invalid IDs raise.
---@param column_id string|integer Column ID.
---@return boolean sortable # True when sort() accepts the column.
function YSortFilterProxyModel:is_sortable(column_id) identity(column_id); return self._sorters[column_id] ~= nil end
---Read the row predicate.
---@return fun(row:table):boolean|nil predicate # Current filter, or nil.
function YSortFilterProxyModel:filter() return self._filter end

---Replace the row predicate (Qt filterAcceptsRow); nil accepts every row.
---A non-function raises. A rejected tree row hides its subtree.
---@param predicate fun(row:table):boolean|nil Strict boolean predicate, or nil.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # Destruction refusal, or nil.
function YSortFilterProxyModel:set_filter(predicate)
  assert(predicate == nil or type(predicate) == "function", "filter must be a function or nil")
  if self:is_destroyed() then return false, "destroyed" end
  if self._filter == predicate then return false end
  local s = state(self)
  s._filter, s._view = predicate, nil
  return apply(self, s)
end

---Read the displayed records.
---@return table[] rows # Fresh array of borrowed records in display order.
function YSortFilterProxyModel:rows()
  local rows = {}; for i, row in ipairs(self._display) do rows[i] = row end; return rows
end
---Read the current batch generation.
---@return string|integer generation # Last set_rows generation, initially 0.
function YSortFilterProxyModel:generation() return self._generation end

---Find a displayed record by ID. Invalid IDs raise.
---@param id string|integer Row ID.
---@return table|nil row # Displayed record, or nil when absent or filtered.
---@return integer|nil index # Its one-based display index, or nil.
function YSortFilterProxyModel:row(id)
  identity(id)
  local source = self._index[id]
  local index = source and self._from_source[source]
  if not index then return nil end
  return self._display[index], index
end

---Map a display index to its batch index (Qt mapToSource). Non-integers raise.
---@param index integer One-based display index.
---@return integer|nil source # One-based batch index, or nil outside the display.
function YSortFilterProxyModel:map_to_source(index) integer(index); return self._to_source[index] end

---Map a batch index to its display index (Qt mapFromSource). Non-integers raise.
---@param index integer One-based batch index.
---@return integer|nil display # One-based display index, or nil when filtered or absent.
function YSortFilterProxyModel:map_from_source(index) integer(index); return self._from_source[index] end

return YSortFilterProxyModel
-- DOCS: YSortFilterProxyModel example start
-- local ui = require("yana_ui")
-- local owner = ui.YObject.new()
-- local model = ui.YSortFilterProxyModel.new({ parent = owner, sorters = {
--   name = { key = function(row) return row.cells.name end, method = "natural" } } })
-- local generation
-- model:connect("layout_changed", owner, function(_, value) generation = value end)
-- model:set_rows({ { id = 1, cells = { name = "item10" } }, { id = 2, cells = { name = "item2" } } }, 7)
-- model:sort("name", "ascending")
-- assert(model:rows()[1].id == 2 and model:map_to_source(1) == 2 and generation == 7)
-- owner:destroy()
-- DOCS: YSortFilterProxyModel example end
