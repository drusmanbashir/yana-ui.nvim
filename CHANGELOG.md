# Changelog

All notable changes to yana-ui are documented here. Versions follow Semantic
Versioning.

## 0.1.0-alpha.1 - 2026-09-10

First public release. yana-ui is the UI grid and layout library that
yana.nvim depends on.

### Added

- `yana_ui.grid`: a cell-grid controller. It lays cells out as a column table
  or a flowing grid, highlights them, fits the result to a height cap, and
  routes keyboard navigation, mouse press, release and hover, and cancel and
  apply to caller-supplied hooks.
- `yana_ui.paint`: read highlight extmarks by position, by range, or by group.
- `yana_ui.geometry`: window geometry and screen-cell resolution.
- `yana_ui.input`: resolve a screen coordinate through a caller-supplied
  resolver and dispatch hover or press to a caller-supplied handler.
