-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-FileCopyrightText: 2016 The Qt Company Ltd
-- SPDX-License-Identifier: LGPL-3.0-only
-- Derived from Qt src/widgets/kernel/qlayoutengine.cpp:18-290 (qtbase v6.8.3).
-- Modified: Lua/Neovim adaptation by Usman Bashir; notice added 2026-10-08.
-- WIDGETS B: Qt6.8.3 qGeomCalc integer sharing, clamping and spare placement.
-- Chain fields: minimum, hint (smart), maximum, stretch, expansive, empty.
local M = {}
local function rounded(fixed) return math.floor((fixed + 128) / 256) end
function M.allocate(chain, position, space, spacing)
  local count = #chain
  if count == 0 then return end
  local hint, minimum, stretch, gaps, expansive, visible = 0, 0, 0, 0, 0, 0
  for _, item in ipairs(chain) do
    item.done = false
    hint, minimum, stretch = hint + item.hint, minimum + item.minimum, stretch + item.stretch
    if not item.empty then visible = visible + 1 end
    if item.expansive then expansive = expansive + 1 end
  end
  gaps = math.max(0, visible - 1)
  local gap_total, spare = spacing * gaps, 0
  if space < minimum + gap_total then
    spacing = minimum + gap_total > 0 and math.floor(spacing * space / (minimum + gap_total)) or 0
    gap_total = spacing * gaps
    local sorted = {}; for i, item in ipairs(chain) do sorted[i] = item.minimum end
    table.sort(sorted)
    local available, sum, used, current, index = space - gap_total, 0, 0, 0, 1
    while index <= count and used < available do
      current = sorted[index]; used = sum + current * (count - index + 1)
      sum = sum + current; index = index + 1
    end
    local items = count - math.max(1, index - 1) + 1
    local deficit = used - available
    local maxval = current - math.floor(deficit / items)
    local remainder, rest = deficit % items, 0
    for _, item in ipairs(chain) do
      rest = rest + remainder
      local cap = maxval
      if rest >= items then cap = cap - 1; rest = rest - items end
      item.size = math.max(0, math.min(item.minimum, cap))
    end
  elseif space < hint + gap_total then
    local n, overdraft = count, hint - (space - gap_total)
    for _, item in ipairs(chain) do
      if item.minimum >= item.hint then item.size, item.done = item.hint, true; n = n - 1 end
    end
    while n > 0 do
      local error_fixed, clamped = 0, false
      for _, item in ipairs(chain) do
        if not item.done then
          error_fixed = error_fixed + math.floor(overdraft * 256 / n)
          local removed = rounded(error_fixed)
          item.size = item.hint - removed; error_fixed = error_fixed - removed * 256
          if item.size < item.minimum then
            item.size, item.done = item.minimum, true
            overdraft, n, clamped = overdraft - (item.hint - item.minimum), n - 1, true
            break
          end
        end
      end
      if not clamped then break end
    end
  else
    local n, available = count, space - gap_total
    for _, item in ipairs(chain) do
      if item.maximum <= item.hint then
        item.size, item.done = item.hint, true
        available, stretch, n = available - item.size, stretch - item.stretch, n - 1
        if item.expansive then expansive = expansive - 1 end
      end
    end
    spare = available
    while n > 0 do
      local deficit, surplus, error_fixed = 0, 0, 0
      for _, item in ipairs(chain) do
        if not item.done then
          spare = 0
          local share
          if stretch > 0 then share = math.floor(available * 256 * item.stretch / stretch)
          elseif expansive > 0 then share = item.expansive and math.floor(available * 256 / expansive) or 0
          else share = math.floor(available * 256 / n) end
          error_fixed = error_fixed + share
          item.size = rounded(error_fixed); error_fixed = error_fixed - item.size * 256
          if item.size < item.hint then deficit = deficit + item.hint - item.size
          elseif item.size > item.maximum then surplus = surplus + item.size - item.maximum end
        end
      end
      local function finish(item, size)
        item.size, item.done = size, true
        available, stretch, n = available - size, stretch - item.stretch, n - 1
        if item.expansive then expansive = expansive - 1 end
      end
      if deficit > 0 and surplus <= deficit then
        for _, item in ipairs(chain) do if not item.done and item.size < item.hint then finish(item, item.hint) end end
      end
      if surplus > 0 and surplus >= deficit then
        for _, item in ipairs(chain) do if not item.done and item.size > item.maximum then finish(item, item.maximum) end end
      end
      if n == 0 then spare = available end
      if n == 0 or surplus == deficit then break end
    end
  end
  local extra = math.floor(spare / (gaps + 2))
  local cursor = position + extra
  for _, item in ipairs(chain) do
    item.position = cursor; cursor = cursor + item.size
    if not item.empty then cursor = cursor + spacing + extra end
  end
end
return M
