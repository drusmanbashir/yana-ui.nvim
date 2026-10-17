-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- WIDGETS YTextMetrics: Neovim owns character boundaries and display widths.
---@class YTextMetrics
---@doc brief Measure text cells and translate between character, cell and byte positions.
---@doc qt QFontMetrics. Neovim supplies display widths and character boundaries; you measure terminal cells rather than font pixels. Tabs depend on the starting column and Neovim options.
---@doc inherits none; this module has no constructor options, properties or signals.
---@doc errors Native string and UTF-index errors propagate; this module does not validate widths or positions. Supply strings and nonnegative integer cell widths. Character indices and byte offsets are zero-based; display-cell positions are one-based.
---@doc context lua/yana_ui/text_metrics.lua|YTextMetrics
---@doc setup With your checkout on runtimepath, run this excerpt in Neovim. It owns no resources.
---@doc example local metrics = require("yana_ui").YTextMetrics
---@doc example local head, rest, used = metrics.prefix_cells("hello", 3)
---@doc example assert(head == "hel" and rest == "lo" and used == 3)
---@doc example assert(metrics.cell_clip("hello", 4) == "hel…")
---@doc example assert(metrics.byte_at_display("界x", 2) == 0)
---@doc see |YGrid|, |geometry|.
local YTextMetrics = {}

---Read Neovim display width from the supplied starting column.
---@param text string Text to measure.
---@param column? integer [default: 0] Zero-based starting display column.
---@return integer width # Display-cell width.
function YTextMetrics.width(text, column)
  return vim.fn.strdisplaywidth(text, column or 0)
end

---Expand tabs at their native display positions without changing other text.
---@param text string Source text.
---@param column? integer [default: 0] Zero-based starting display column.
---@return string expanded # Text with tabs replaced by their native cell-width spaces.
function YTextMetrics.expand_tabs(text, column)
  local head = ""
  for i = 0, vim.fn.strchars(text, true) - 1 do
    local char = YTextMetrics.character(text, i)
    if char == "\t" then
      local start = (column or 0) + YTextMetrics.width(head, column)
      char = string.rep(" ", YTextMetrics.width(char, start))
    end
    head = head .. char
  end
  return head
end

---Read one character with composing characters included, using strcharpart().
---@param text string Source text.
---@param index integer Zero-based character index, using Neovim composing-character semantics.
---@return string character # Character slice; empty outside the text.
function YTextMetrics.character(text, index)
  return vim.fn.strcharpart(text, index, 1, true)
end

---Take the longest prefix that fits without splitting a character.
---@param text string Source text.
---@param width integer Maximum display-cell width.
---@param column? integer [default: 0] Zero-based starting display column.
---@return string head # Prefix that fits.
---@return string rest # Remaining characters.
---@return integer used # Display cells used by the prefix.
function YTextMetrics.prefix_cells(text, width, column)
  local head, used, next_char = "", 0, 0
  for i = 0, vim.fn.strchars(text, true) - 1 do
    local char = YTextMetrics.character(text, i)
    local size = YTextMetrics.width(head .. char, column)
    if size > width then break end
    head, used, next_char = head .. char, size, i + 1
  end
  return head, vim.fn.strcharpart(text, next_char, vim.fn.strchars(text, true) - next_char, true), used
end

---Append spaces to reach a minimum width; wider input is kept intact.
---@param text string Source text.
---@param width integer Minimum display-cell width.
---@return string padded # Text with any required trailing spaces.
function YTextMetrics.pad(text, width)
  return text .. string.rep(" ", math.max(0, width - YTextMetrics.width(text)))
end

---Keep a fitting string or shorten its prefix with a trailing ellipsis.
---Nonpositive widths return an empty string.
---@param text string Source text.
---@param width integer Maximum display-cell width.
---@return string elided # Text fitting the width.
function YTextMetrics.elide(text, width)
  if width <= 0 then return "" end
  if YTextMetrics.width(text) <= width then return text end
  local marker = "…"
  if YTextMetrics.width(marker) > width then return "" end
  return YTextMetrics.prefix_cells(text, width - YTextMetrics.width(marker)) .. marker
end

local function suffix_cells(text,width,column)
  local tail = ""
  for i=vim.fn.strchars(text,true)-1,0,-1 do
    local char = YTextMetrics.character(text,i)
    if YTextMetrics.width(char..tail,column)>width then break end
    tail=char..tail
  end
  return tail
end

---Keep both ends around a middle ellipsis, without splitting native characters.
---The prefix receives half the available content cells, rounded down.
---@param text string Source text.
---@param width integer Maximum display-cell width.
---@return string elided # Fitting text, or empty for nonpositive widths.
function YTextMetrics.elide_middle(text,width)
  if width<=0 then return "" end
  if YTextMetrics.width(text)<=width then return text end
  local marker="…"
  local remaining=width-YTextMetrics.width(marker)
  if remaining<0 then return "" end
  local head_width=math.floor(remaining/2)
  local head=YTextMetrics.prefix_cells(text,head_width)
  local tail=suffix_cells(text,remaining-head_width,YTextMetrics.width(head..marker))
  return head..marker..tail
end

---Elide the prefix if needed, then pad to the requested width.
---@param text string Source text.
---@param width integer Target display-cell width.
---@return string clipped # Elided and padded text; empty for nonpositive widths.
function YTextMetrics.cell_clip(text, width)
  return YTextMetrics.pad(YTextMetrics.elide(text, width), math.max(0, width))
end

-- Legacy column grids retain the suffix, with the ellipsis on the requested side.
---Keep the suffix when truncating; leading puts the ellipsis before that suffix,
---other modes put it after. Oversized input at width 0 or 1 becomes spaces.
---@param text string Source text.
---@param width integer Target display-cell width.
---@param mode? string [default: nil] Use "leading" for a leading ellipsis.
---@return string clipped # Suffix-preserving clipped and padded text.
function YTextMetrics.clip(text, width, mode)
  if YTextMetrics.width(text) <= width then return YTextMetrics.pad(text, width) end
  if width <= 1 then return string.rep(" ", math.max(0, width)) end
  local marker = "…"
  local tail = suffix_cells(text,width-YTextMetrics.width(marker))
  return YTextMetrics.pad(mode == "leading" and marker .. tail or tail .. marker, width)
end

-- A cell inside a wide character maps to that character's first byte.
---Map a display cell to a zero-based byte offset. A cell inside a wide character
---maps to its first byte; a cell beyond the string maps to its byte length.
---@param text string Source text.
---@param cell integer One-based display cell.
---@param column? integer [default: 0] Zero-based starting display column.
---@return integer byte # Zero-based byte offset.
function YTextMetrics.byte_at_display(text, cell, column)
  local head, byte = "", 0
  for i = 0, vim.fn.strchars(text, true) - 1 do
    local char = YTextMetrics.character(text, i)
    if cell <= YTextMetrics.width(head .. char, column) then return byte end
    head, byte = head .. char, byte + #char
  end
  return #text
end

---Map a byte offset to its character start cell; the byte length maps to the cell
---after the string. Native UTF-index validation runs first.
---@param text string Source text.
---@param byte integer Zero-based byte offset.
---@param column? integer [default: 0] Zero-based starting display column.
---@return integer cell # One-based cell relative to the string start.
function YTextMetrics.cell_at_byte(text, byte, column)
  vim.str_utfindex(text, "utf-32", byte, true)
  local head, offset = "", 0
  for i = 0, vim.fn.strchars(text, true) - 1 do
    local char = YTextMetrics.character(text, i)
    if byte < offset + #char then return YTextMetrics.width(head, column) + 1 end
    head, offset = head .. char, offset + #char
  end
  return YTextMetrics.width(text, column) + 1
end

-- DOCS: YTextMetrics example start
-- local metrics = require("yana_ui").YTextMetrics
-- local head, rest, used = metrics.prefix_cells("hello", 3)
-- assert(head == "hel" and rest == "lo" and used == 3)
-- assert(metrics.cell_clip("hello", 4) == "hel…")
-- assert(metrics.byte_at_display("界x", 2) == 0)
-- DOCS: YTextMetrics example end
return YTextMetrics
