# timewarrior.nvim

Neovim UI for [Timewarrior](https://timewarrior.net/) — track time without leaving your editor.

## Requirements

- Neovim 0.9+
- [Timewarrior](https://timewarrior.net/) (`timew`) in your `$PATH`
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- `jq` and `awk` in your `$PATH` (used by `:TimewEdit`)

## Installation

### lazy.nvim

```lua
{
  "felipegallois/timewarrior.nvim",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "nvim-telescope/telescope.nvim",
  },
  config = function()
    require("timewarrior").setup()
  end,
}
```

### Configuration

All options and their defaults:

```lua
require("timewarrior").setup({
  summary_hint = "week",   -- default range for :TimewSummary
  tags_hint    = "all",    -- default range for :TimewTags / :TimewTrackTag
  edit_hint    = "week",   -- default range for :TimewEdit
  status_refresh = 10,     -- seconds between timew queries in M.status()
  size = {
    width  = "80%",
    height = 30,
  },
})
```

## Commands

| Command | Description |
|---|---|
| `:TimewSummary [range]` | Show a time summary popup |
| `:TimewTags [range]` | Show all tags used in a range |
| `:TimewTrack` | Start tracking — type any tag(s) in a popup |
| `:TimewTrackTag [range]` | Start tracking — pick an existing tag via Telescope |
| `:TimewStop` | Stop the current interval |
| `:TimewContinue` | Continue the most recent interval |
| `:TimewEdit [range]` | Browse and edit intervals via Telescope |

All commands that accept a `[range]` support tab-completion with Timewarrior's
built-in hints: `today`, `week`, `month`, `year`, `lastweek`, day names, etc.

### :TimewSummary

Opens a floating popup with the output of `timew summary :ids` for the given
range. Close with `<Esc>` or `q`.

### :TimewTags

Opens a floating popup listing all tags used in the given range.
Close with `<Esc>`.

### :TimewTrack

Opens an input popup. Type one or more space-separated tags and press `<CR>`
to start tracking. Press `<Esc>` to cancel.

```
> work coding feature-branch
```

### :TimewTrackTag

Opens a Telescope picker pre-populated with all tags used in the given range.
Select one and press `<CR>` to start tracking it.

### :TimewEdit

Opens a Telescope picker listing all intervals in the given range, sorted by
entry ID. Each line shows:

```
@N   YYYY-MM-DDTHH:MM:SS - YYYY-MM-DDTHH:MM:SS   tag1 tag2
```

Keybindings inside the picker:

| Key | Action |
|---|---|
| `<CR>` | Choose whether to edit the start or end time |
| `<C-s>` | Edit the start time directly |
| `<C-e>` | Edit the end time directly |
| `<C-d>` | Delete the entry (asks for confirmation) |

When editing a time, a popup pre-filled with the current timestamp opens.
Modify it and press `<C-s>` to save. The change is applied with `timew modify
... :adjust` so surrounding intervals are adjusted automatically.

> Note: you cannot edit the end time of an open (currently tracking) interval.
> Run `:TimewStop` first.

## Statusline integration

`require("timewarrior").status()` returns a string like `"work coding (23m)"`
when an interval is active, and `""` when idle. The underlying `timew export`
call is cached for `status_refresh` seconds; elapsed time is recomputed on
every call so the counter stays live between cache refreshes.

### lualine

```lua
require("lualine").setup({
  sections = {
    lualine_x = {
      { require("timewarrior").status },
    },
  },
})
```

### heirline

```lua
{
  provider = function()
    local s = require("timewarrior").status()
    return s ~= "" and ("  " .. s) or ""
  end,
}
```
