# yana-ui.nvim

yana-ui is a small Lua library for Neovim that draws and drives cell-grid
menus and reads back what a plugin has painted on screen. It is the UI grid
and layout library that [yana.nvim](https://github.com/drusmanbashir/yana.nvim)
depends on. It has no dependencies of its own.

The Lua module is `yana_ui`.

Status: alpha (`0.1.0-alpha.1`). The API may change before 1.0.

## Requirements

- Neovim 0.11.2+

## Installation

### As a yana.nvim dependency (lazy.nvim)

Add yana-ui to the `dependencies` of your yana.nvim plugin entry. lazy.nvim
installs it and loads it before yana.nvim:

```lua
return {
  "drusmanbashir/yana.nvim",
  dependencies = { "drusmanbashir/yana-ui.nvim" },
  -- the rest of your yana.nvim configuration (cmd, build, opts, ...)
}
```

### On its own

```lua
return {
  "drusmanbashir/yana-ui.nvim",
  lazy = true, -- loaded on the first require("yana_ui")
}
```

## Modules

`require("yana_ui")` returns a table holding the four modules below. Each can
also be required directly, for example `require("yana_ui.grid")`.

### `yana_ui.grid`

A cell-grid controller. The caller owns the state and the meaning of every
cell; the grid lays the cells out, highlights them, and routes keys and mouse
events back to caller hooks.

- `grid.open(opts)` opens the grid in a centred floating window and returns it.
- `grid.new(opts)` creates a grid without a window; attach one with
  `g:attach(buf, win)`.
- `grid.layout(rows, opts)` is the pure layout step: it returns the rendered
  lines and one span per cell.

Common options:

| Option | Meaning |
|---|---|
| `cells(state)` | returns rows of cells; a cell is `{ col, value, text, row_i, ... }` |
| `columns` | column names, as a list or a function of the state |
| `layout` | `"columns"` for a table with a header row, `"flow"` to wrap cells |
| `state` | caller-owned table passed to the hooks |
| `row_count(state)` | number of data rows, used to bound keyboard movement |
| `hl_groups` | highlight groups: `live`, `hover`, `flash`, `dim`, `current`, `marked`, `key` |
| `on_enter`, `on_press`, `on_release`, `on_hover`, `on_cancel` | caller hooks |
| `title`, `legend`, `window_title`, `footer` | text around the grid |

Keys inside the grid: `h`, `l`, `<Tab>`, `<S-Tab>`, `<Left>` and `<Right>` move
between columns; `j`, `k`, `<Up>` and `<Down>` move between rows; `<CR>`
applies; `<Esc>` or `q` cancels. The mouse presses and releases cells, and
hover follows the pointer.

```lua
local items = { "alpha", "beta", "gamma" }
require("yana_ui.grid").open({
  window_title = " Pick one ",
  layout = "columns",
  columns = { "item" },
  state = { active_row = 1 },
  row_count = function() return #items end,
  cells = function(state)
    local rows = {}
    for i, name in ipairs(items) do
      rows[i] = { { col = "item", value = name, text = " " .. name .. " ",
        row_i = i, active = state.active_row == i } }
    end
    return rows
  end,
  hl_groups = { live = "Normal", hover = "PmenuSel", flash = "IncSearch" },
  on_enter = function(g)
    vim.notify("picked " .. items[g.state.active_row])
    g:close()
  end,
})
```

### `yana_ui.paint`

Reads highlight extmarks without decoding extmark tuples yourself.

- `paint.at(buf, ns, line, byte_col)`: the highest-priority highlight group
  covering a position.
- `paint.range(buf, ns, start_line, start_byte_col, end_line, end_byte_col, group)`:
  whether `group` covers every byte in the range.
- `paint.ranges(buf, ns, group)`: every extmark carrying `group`, sorted by
  position.

### `yana_ui.geometry`

- `geometry.list(tabpage)`: the geometry of every window in a tab page.
- `geometry.get(win)`: one window's geometry, or `nil` once it is gone.
- `geometry.cell(win, screen_row, screen_col)`: turns a screen cell into
  window-local coordinates.
- `geometry.screenpos(win, line, column)`: where a buffer position is drawn on
  screen.

### `yana_ui.input`

Resolves a screen coordinate through a resolver you supply, then dispatches
the gesture to a handler you supply.

- `input.resolve(win, screen_row, screen_col, resolver)`
- `input.hover(win, screen_row, screen_col, resolver, handler)`
- `input.press(win, screen_row, screen_col, resolver, handler)`

### Coordinates

`geometry.cell()` returns 1-based screen and window-local coordinates.
`paint.at()` takes a 1-based line and a 0-based byte column. `paint.range()`
uses a half-open byte range.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
