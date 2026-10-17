-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-FileCopyrightText: 2016 The Qt Company Ltd
-- SPDX-License-Identifier: LGPL-3.0-only
-- Custom-order operand swap derived from Qt src/corelib/itemmodels/
-- qsortfilterproxymodel.cpp:34-76,681-698 (qtbase v6.8.4-lts-lgpl ed77a3ca).
-- ordering raw records without owning a model.
---@class YTableSort
---@doc brief Order borrowed records or visible tree siblings by explicit raw keys.
---@doc qt QSortFilterProxyModel sorting. These stateless helpers return arrays of the original records; |YSortFilterProxyModel| owns a batch, sort choice and projection. Custom less replaces a lessThan override.
---@doc inherits none; this module has no constructor options, properties or signals.
---@doc errors Rejects invalid configuration, sparse arrays, invalid text keys and ambiguous visible forests. Key, less and fixed-predicate errors propagate; less and fixed must return booleans. Invalid numeric or hex keys sort last in both directions; custom keys, nil included, go to less unchanged.
---@doc context lua/yana_ui/table_sort.lua|YTableSort
---@doc setup With your checkout on runtimepath, run this excerpt in Neovim. It owns no resources.
---@doc example local sort = require("yana_ui").YTableSort
---@doc example local rows = {{id = 1, name = "item10"}, {id = 2, name = "item2"}}
---@doc example local ordered = sort.sorted(rows, {key = function(row) return row.name end, method = "natural"})
---@doc example assert(ordered[1] == rows[2] and rows[1].id == 1)
---@doc see |YSortFilterProxyModel|, |YTableView|, |YTreeView|.
local YObject = require("yana_ui.object")
local YTableSort = {}

---@class YTableSortOptions
---@field key fun(record:any):any Extract one raw comparison key per record.
---@field method? "text"|"natural"|"numeric"|"hex"|"custom" [default: "text"] Comparison method.
---@field order? "ascending"|"descending" [default: "ascending"] Value order; ties retain input order.
---@field case_sensitive? boolean [default: false] Text/natural only; Neovim lowercase conversion.
---@field less? fun(a:any,b:any):boolean [default: nil] Custom only, required; strict weak order over raw keys.
---@field fixed? fun(row:table):boolean Tree only; anchors partition sortable sibling runs.

local function configuration(opts, tree)
  assert(type(opts) == "table", "sort options required")
  local allowed = {key=true, method=true, order=true, case_sensitive=true, less=true, fixed=tree}
  for k in pairs(opts) do assert(allowed[k], "unknown sort option: " .. tostring(k)) end
  assert(type(opts.key) == "function", "sort key must be a function")
  local method = opts.method == nil and "text" or opts.method
  local order = opts.order == nil and "ascending" or opts.order
  assert(method == "text" or method == "natural" or method == "numeric" or method == "hex" or method == "custom", "invalid sort method")
  assert(order == "ascending" or order == "descending", "invalid sort order")
  if opts.case_sensitive ~= nil then
    assert((method == "text" or method == "natural") and type(opts.case_sensitive) == "boolean", "invalid case_sensitive option")
  end
  if method == "custom" then assert(type(opts.less) == "function", "custom method requires a less function")
  else assert(opts.less == nil, "less requires the custom method") end
  assert(opts.fixed == nil or (tree and type(opts.fixed) == "function"), "invalid fixed predicate")
  return {key=opts.key, method=method, descending=order == "descending", case_sensitive=opts.case_sensitive == true, less=opts.less, fixed=opts.fixed}
end

local function dense(records)
  assert(type(records) == "table", "records must be a dense array")
  local count = 0
  for k in pairs(records) do
    assert(type(k) == "number" and k >= 1 and k % 1 == 0, "records must be a dense array")
    count = count + 1
  end
  for i = 1, count do assert(records[i] ~= nil, "records must be a dense array") end
  return count
end

local function trim(value) return value:match("^[ \t\r\n\f\v]*(.-)[ \t\r\n\f\v]*$") end
local function finite(value) return value == value and value ~= math.huge and value ~= -math.huge end
local function decimal(value)
  if type(value) == "number" then return finite(value) and value or nil end
  if type(value) ~= "string" then return nil end
  local text = trim(value)
  local mantissa, exponent = text:match("^(.-)[eE]([+-]?%d+)$")
  mantissa = mantissa or text
  if not (mantissa:match("^[+-]?%d+%.?%d*$") or mantissa:match("^[+-]?%.%d+$")) then return nil end
  if not exponent and text:find("[eE]") then return nil end
  local number = tonumber(text)
  return number and finite(number) and number or nil
end
local function magnitude(text)
  text = text:gsub("^0+", "")
  return text == "" and "0" or text
end
local function hexadecimal(value)
  if type(value) ~= "string" then return nil end
  local text = trim(value):gsub("^0[xX]", "")
  if not text:match("^[0-9a-fA-F]+$") then return nil end
  return magnitude(text:lower())
end
local function natural(text)
  local parts, pos = {}, 1
  while pos <= #text do
    local first, last = text:find("%d+", pos)
    if not first then parts[#parts+1] = {text=text:sub(pos)}; break end
    if first > pos then parts[#parts+1] = {text=text:sub(pos, first-1)} end
    parts[#parts+1] = {digits=magnitude(text:sub(first,last))}
    pos = last+1
  end
  return parts
end
local function normalize(value, opts)
  if opts.method == "custom" then return value end
  if opts.method == "numeric" then return decimal(value) end
  if opts.method == "hex" then return hexadecimal(value) end
  if value == nil then return nil end
  assert(type(value) == "string", "text and natural keys must be strings or nil")
  if not opts.case_sensitive then value = vim.fn.tolower(value) end
  return opts.method == "natural" and natural(value) or value
end
local function compare(a, b)
  if a == b then return 0 end
  return a < b and -1 or 1
end
local function compare_magnitude(a, b)
  if #a ~= #b then return compare(#a,#b) end
  return compare(a,b)
end
local function compare_natural(a,b)
  for i = 1, math.min(#a,#b) do
    local x,y = a[i],b[i]
    local result
    if x.digits and y.digits then result = compare_magnitude(x.digits,y.digits)
    else result = compare(x.text or x.digits,y.text or y.digits) end
    if result ~= 0 then return result end
  end
  return compare(#a,#b)
end
local function less(opts)
  return function(a,b)
    if a.value == nil or b.value == nil then
      if a.value == nil and b.value == nil then return a.index < b.index end
      return a.value ~= nil
    end
    local result
    if opts.method == "natural" then result = compare_natural(a.value,b.value)
    elseif opts.method == "hex" then result = compare_magnitude(a.value,b.value)
    else result = compare(a.value,b.value) end
    if result == 0 then return a.index < b.index end
    return opts.descending and result > 0 or (not opts.descending and result < 0)
  end
end
-- Qt GreaterThan calls lessThan with swapped operands; no missing bucket.
local function custom_less(opts)
  local function before(x, y)
    local result = opts.less(x, y)
    assert(type(result) == "boolean", "custom less must return boolean")
    return result
  end
  return function(a,b)
    local first, second = a, b
    if opts.descending then first, second = b, a end
    if before(first.value, second.value) then return true end
    if before(second.value, first.value) then return false end
    return a.index < b.index
  end
end
local function comparator(opts) return opts.method == "custom" and custom_less(opts) or less(opts) end

---Return a new array with stable ties; built-in methods put missing keys last
---in either order. Invalid input raises before any key callback.
---@param records any[] Dense array of borrowed records.
---@param opts YTableSortOptions Explicit raw-key callback and comparison policy.
---@return any[] ordered # Original record references in requested order.
function YTableSort.sorted(records, opts)
  opts = configuration(opts, false)
  local count, decorated = dense(records), {}
  for i = 1,count do decorated[i] = {row=records[i], index=i, value=normalize(opts.key(records[i]),opts)} end
  table.sort(decorated,comparator(opts))
  local result = {}
  for i,node in ipairs(decorated) do result[i] = node.row end
  return result
end

local Forest = {}
-- A detached, validated visible preorder forest; tree() never mutates it.
local function forest(rows)
  local count = dense(rows)
  local copy,roots,children,stack,seen = {},{},{},{},{}
  for i = 1,count do
    local row = rows[i]
    assert(type(row) == "table", "tree row must be a table")
    YObject.identity(row.id)
    assert(not seen[row.id], "duplicate tree row id")
    local depth = row.depth
    assert(type(depth) == "number" and depth >= 0 and depth % 1 == 0, "invalid tree depth")
    assert((i == 1 and depth == 0) or (i > 1 and depth <= copy[i-1].depth+1), "tree depth gap")
    local parent = depth > 0 and stack[depth] or nil
    assert(depth == 0 or parent, "tree parent is not visible")
    assert(row.parent_id == nil or (parent and row.parent_id == copy[parent].id), "tree parent must be the open ancestor")
    local siblings = parent and children[parent] or roots
    siblings[#siblings+1] = i
    copy[i],children[i],seen[row.id],stack[depth+1] = row,{},true,i
    for j = depth+2,#stack do stack[j] = nil end
  end
  return setmetatable({rows=copy,roots=roots,children=children},Forest)
end
local function sort_runs(siblings,compare)
  local first = 1
  for i = 1,#siblings+1 do
    if i > #siblings or siblings[i].fixed then
      if i-first > 1 then
        local run = {}
        for j = first,i-1 do run[#run+1] = siblings[j] end
        table.sort(run,compare)
        for j,node in ipairs(run) do siblings[first+j-1] = node end
      end
      first = i+1
    end
  end
end

---Validate a visible preorder forest once, for repeated tree() calls. The
---result borrows the rows but not the array; invalid input raises.
---@param rows table[] Dense visible rows with unique id, depth and optional parent_id.
---@return table forest # Opaque detached forest accepted by tree().
function YTableSort.forest(rows) return forest(rows) end

---Sort only sibling runs in a validated visible preorder forest.
---@param rows table[]|table Dense visible rows with unique id, depth and optional parent_id, or a forest() result.
---@param opts YTableSortOptions Raw-key policy; fixed rows anchor sibling runs.
---@return table[] ordered # Original row references with descendant relationships retained.
function YTableSort.tree(rows,opts)
  opts = configuration(opts,true)
  local prepared = getmetatable(rows) == Forest and rows or forest(rows)
  local nodes = {}
  for i,row in ipairs(prepared.rows) do
    local node = {row=row,index=i,value=normalize(opts.key(row),opts),fixed=false}
    if opts.fixed then
      -- Keep nil distinct from false at this strict callback boundary.
      local fixed = opts.fixed(row)
      assert(type(fixed) == "boolean", "fixed predicate must return boolean")
      node.fixed = fixed
    end
    nodes[i] = node
  end
  local compare = comparator(opts)
  local function ordered(indices)
    local siblings = {}
    for j,index in ipairs(indices) do siblings[j] = nodes[index] end
    sort_runs(siblings,compare)
    return siblings
  end
  local result,stack,roots = {},{},ordered(prepared.roots)
  for i = #roots,1,-1 do stack[#stack+1] = roots[i] end
  while #stack > 0 do
    local node = table.remove(stack)
    result[#result+1] = node.row
    local children = ordered(prepared.children[node.index])
    for i = #children,1,-1 do stack[#stack+1] = children[i] end
  end
  return result
end

return YTableSort
-- DOCS: YTableSort example start
-- local sort = require("yana_ui").YTableSort
-- local rows = {{id = 1, name = "item10"}, {id = 2, name = "item2"}}
-- local ordered = sort.sorted(rows, {key = function(row) return row.name end, method = "natural"})
-- assert(ordered[1] == rows[2] and rows[1].id == 1)
-- DOCS: YTableSort example end
