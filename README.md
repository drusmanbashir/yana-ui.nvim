# yana-ui.nvim

The goal of yana-ui is to support plugin developers in creating slick UI
elements, strongly influenced by Qt for C++.

Use shared actions, buttons, toolbars and menus in Lua. Use native buffers,
windows, keymaps, scrolling and Neovim’s main loop wherever they provide a
close counterpart.

Requires Neovim 0.11.2 or newer; no external runtime dependencies.
The API is alpha (`0.1.0-alpha.1`) and may change before 1.0.

## Install

Declare yana-ui as a plugin dependency with lazy.nvim:

```lua
return {
  "your-account/your-plugin.nvim",
  dependencies = { "drusmanbashir/yana-ui.nvim" },
}
```

Or install it directly:

```lua
return { "drusmanbashir/yana-ui.nvim", lazy = true }
```

With Neovim's native packages, put the repository at
`stdpath("data") .. "/site/pack/plugins/start/yana-ui.nvim"`. Generate help
tags with `:helptags /path/to/yana-ui.nvim/doc` when your package manager does
not generate them. Then open `:help yana-ui`.

## Quick start

Run `nvim --clean -u examples/00_quick_start.lua` from your checkout to open
a command picker. The file loads that checkout; set `YANA_UI_REPO` to choose
another. In an installed plugin, start at `local ui = require("yana_ui")`.

```lua
local source = debug.getinfo(1, "S").source:sub(2)
vim.opt.rtp:prepend(vim.env.YANA_UI_REPO or vim.fn.fnamemodify(source, ":p:h:h"))
local ui = require("yana_ui")
local items = { "Build", "Test", "Release" }
vim.schedule(function()
  ui.YGrid.open({
    window_title = " Plugin commands ", layout = "columns", columns = { "Command" },
    width = 44, height = 6, fixed_size = true, state = { active_row = 1 },
    legend = "j/k: move   Enter: choose   Esc: close", hl_groups = { live = "Pmenu", hover = "PmenuSel", flash = "IncSearch" },
    row_count = function() return #items end,
    cells = function(state)
      local rows = {}
      for i, name in ipairs(items) do
        rows[i] = { { col = "Command", value = name, text = " " .. name .. " ",
          row_i = i, active = state.active_row == i } }
      end
      return rows
    end,
    on_enter = function(g) local name = items[g.state.active_row]; g:close(); vim.notify(name) end,
  }) end)
```

![Command picker navigation](doc/media/00-quick-start.gif)

Supply your command items and callbacks. Call `g:close()` to release the grid’s
buffer, window and mappings. Build buttons on a shared buffer with the
[toolbar tutorial](doc/tutorials/01-toolbar.md).

## Class map

> Native Neovim windows and tabpages provide the application frame.

| Class or native concept | Qt counterpart | What it is for in Neovim | Example |
|---|---|---|---|
| Neovim itself | `QMainWindow` | Main window | Native window API |
| Window area | Central widget | A tabpage is one arrangement of the window area | Native window API |
| `YObject` | `QObject` | Parent/child lifetime and direct Lua signals | [Example](examples/reference/YObject.lua) |
| `YAction` | `QAction` | One shared command, enabled and checked state | [Example](examples/reference/YAction.lua) |
| `YTimer` | `QTimer` | Parent-owned native timers with scheduled delivery | [Example](examples/reference/YTimer.lua) |
| `YWidget` | `QWidget` | Virtual controls on an existing buffer canvas | [Example](examples/reference/YWidget.lua) |
| `YLayout` | `QLayout` | Virtual item membership and rectangle activation | [Example](examples/reference/YLayout.lua) |
| `YBoxLayout` | `QBoxLayout` | Horizontal or vertical cell layout | [Example](examples/reference/YBoxLayout.lua) |
| `YSizePolicy` | `QSizePolicy` | Immutable size policies and stretch weights | [Example](examples/reference/YSizePolicy.lua) |
| `YPushButton` | `QPushButton` | Standalone or action-backed push buttons | [Example](examples/reference/YPushButton.lua) |
| `YToolButton` | `QToolButton` | Icon-first buttons with optional flat idle style | [Example](examples/reference/YToolButton.lua) |
| `YToolBar` | `QToolBar` | Shared actions, buttons and an overflow menu | [Example](examples/reference/YToolBar.lua) |
| `YMenu` | `QMenu` | Flat action popup with native scrolling | [Example](examples/reference/YMenu.lua) |
| `YAbstractItemView` | `QAbstractItemView` | Shared table/tree base: columns, header, rows, input and optional row model | [Example](examples/reference/YAbstractItemView.lua) |
| `YTableView` | `QTableView` / `QHeaderView` | Borrowed native table with resizable columns and checked record requests | [Example](examples/reference/YTableView.lua) |
| `YTreeView` | `QTreeView` | Visible hierarchy rows with shared columns and expansion requests | [Example](examples/reference/YTreeView.lua) |
| `YSortFilterProxyModel` | `QSortFilterProxyModel` | One unsorted record batch, filtered and sorted for a bound view | [Example](examples/reference/YSortFilterProxyModel.lua) |
| `YPalette` | `QPalette` | Theme roles from highlights or explicit RGB values | [Example](examples/reference/YPalette.lua) |
| `YStyle` | `QStyle` | Highlight appearance derived from live control state | [Example](examples/reference/YStyle.lua) |
| `YFocus` | `QApplication` focus | Virtual focus within registered native windows | [Example](examples/reference/YFocus.lua) |
| `YPaintWriter` | `QPainter` / `QBackingStore` | Buffer drawing and highlight marks | [Example](examples/reference/YPaintWriter.lua) |
| `YEventDispatcher` | `QApplication` event delivery | Native input routed through virtual controls | [Example](examples/reference/YEventDispatcher.lua) |
| `YGrid` | `QAbstractItemView` / `QTableView` | Caller-owned cell data in a native grid float | [Example](examples/reference/YGrid.lua) |
| `YPanelHost` | Nested `QSplitter` host | Borrows a root window as its first leaf; opens other panes as native splits | [Example](examples/reference/YPanelHost.lua) |
| `YTextMetrics` | `QFontMetrics` | Native display-cell width and byte conversion | [Example](examples/reference/YTextMetrics.lua) |
| `YTestInput` | `QTest` | Direct dispatcher input for state tests | [Example](examples/reference/YTestInput.lua) |

`paint` inspects native highlight extmarks and `geometry` reads native window
positions. Lowercase modules such as `yana_ui.surface` and
`yana_ui.grid_layout` remain available by direct `require`; the table above
lists the public Y exports of `require("yana_ui")` alongside native concepts.

Use native editing, windows, tabpages, keymaps and `vim.ui` for text input,
splits, tabs, shortcuts and simple selection. The toolkit supports kitty and
standard terminals through Neovim’s native input and rendering APIs.

## Documentation

### Themes

`YPalette.new({ theme = "native" })` follows the editor colourscheme and is
the default. Use `theme = "dark"` or `theme = "light"` for a fixed palette,
then pass it to `YStyle.new({ focus = focus, palette = palette })`.
`palette:theme_name()` identifies its source. Explicit `colors` creates a
sparse `custom` palette; use `set_color()` to override an existing preset.
These choices do not change the editor colourscheme or caller-supplied grid
highlights.

Yana's open-review button pane supplies its own grid highlights and currently
uses the **native editor theme**: live buttons link to `Pmenu`, disabled to
`Comment`, hover to `PmenuSel`, pressed to `IncSearch`, and keys to `Special`.

Open `:help yana-ui` or [the help index](doc/yana-ui.txt).

- [Reference](doc/yana-ui-reference.txt): all 22 public exports and the split-layout helper.
- Tutorials: [Toolbar](doc/tutorials/01-toolbar.md), [View menu](doc/tutorials/02-view-menu.md), [Confirmation dialog](doc/tutorials/03-confirm-dialog.md), [Picker table](doc/tutorials/04-picker-table.md), [Two-pane panel](doc/tutorials/05-two-pane-panel.md). Run each page's linked example from your checkout; open `:help yana-ui-tutorials` for the same steps.
- How-tos: [Disable a button](doc/how-to/disable-button.md), [Synchronize options](doc/how-to/sync-option-menu.md), [Confirm discard](doc/how-to/confirm-discard.md), [Choose a buffer](doc/how-to/choose-buffer.md), [Refresh a panel](doc/how-to/refresh-panel.md).

![Toolbar input and overflow](doc/media/01-toolbar.gif)
![View menu option ticks](doc/media/02-view-menu.gif)
![Save, Discard and Cancel focus](doc/media/03-confirm-dialog.gif)
![Picker keyboard and mouse selection](doc/media/04-picker-table.gif)
![Panel dividers and refresh](doc/media/05-two-pane-panel.gif)

Read [the explanation](doc/yana-ui.txt) for how Qt concepts map to Neovim;
open `:help yana-ui-explanation`.

## Licence

Use yana-ui under LGPL-3.0-only. Distribute [LICENSE](LICENSE), its incorporated
GPLv3 terms in [COPYING](COPYING), and [NOTICE](NOTICE). Preserve source credits
for Usman Bashir, The Qt Company Ltd and other upstream rights holders.

Keep your plugin’s licence when your distribution satisfies LGPLv3. Keep
yana-ui separately replaceable and permit users to modify it and debug those
changes, including reverse engineering for that purpose. When vendoring,
provide complete corresponding library source and your modifications under
the applicable LGPL terms; readable Lua source can satisfy this requirement.
Apply these obligations when using `require()`. Follow
[LGPLv3 sections 0 and 4](https://www.gnu.org/licenses/lgpl-3.0.html) and the
[GNU FAQ](https://www.gnu.org/licenses/gpl-faq.html#LGPLStaticVsDynamic).
