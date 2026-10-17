-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- the one YTableRow/YTreeRow shape
-- rule. Views copy and YSortFilterProxyModel borrows only rows it accepts, so a
-- model never publishes a batch its views would refuse.
local Object=require('yana_ui.object')
local ItemRow={}
local limit=2147483647
function ItemRow.text(value)
  assert(type(value)=='string' and not value:find('[\r\n%z]'),'table requires single-line text')
end
-- Raise on the first invalid field; tree adds the YTreeRow fields.
function ItemRow.check(v,tree)
  assert(type(v)=='table' and type(v.cells)=='table','invalid row');Object.identity(v.id)
  if v.current~=nil then Object.boolean(v.current)end
  if v.disabled~=nil then Object.boolean(v.disabled)end
  if v.dimmed~=nil then Object.boolean(v.dimmed)end
  for key,value in pairs(v.cells)do Object.identity(key);ItemRow.text(value)end
  if v.annotation~=nil then
    assert(type(v.annotation)=='table','invalid table annotation')
    ItemRow.text(v.annotation.text);ItemRow.text(v.annotation.hl_group);assert(v.annotation.hl_group~='','empty annotation group')
  end
  if not tree then return end
  local depth=v.depth
  assert(type(depth)=='number' and depth>=0 and depth<=limit and depth==math.floor(depth),'invalid tree integer')
  if v.parent_id~=nil then Object.identity(v.parent_id)end
  if v.expandable~=nil then Object.boolean(v.expandable)end
  if v.expanded~=nil then Object.boolean(v.expanded)end
end
return ItemRow
