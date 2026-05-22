local Popup = require("nui.popup")
local NuiText = require("nui.text")
local event = require("nui.utils.autocmd").event

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local M = {}

M.config = {
  summary_hint = 'week',
  tags_hint = 'all',
  edit_hint = 'week',
  status_refresh = 10,
  size = {
    width = "80%",
    height = 30,
  },
}

M.range_hints = {
  'all',
  'yesterday',
  'day',
  'today',
  'week',
  'fortnight',
  'month',
  'quarter',
  'year',
  'lastweek',
  'lastmonth',
  'lastquarter',
  'lastyear',
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
}

local function get_command_results(command)
  local result = vim.fn.systemlist(command)
  local lines = {}
  for _, line in ipairs(result) do
    if line ~= "" then
      table.insert(lines, line)
    end
  end
  return lines
end

-- Convert UTC time components to a Unix timestamp correctly regardless of local timezone.
-- os.time({...}) interprets its input as local time; this corrects for the offset.
local function utc_to_unix(y, mo, d, h, mi, s)
  local t = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
  local utc = os.date("!*t", t)
  return t - (os.time(utc) - t)
end

local function parse_timew_ts(s)
  if not s or #s < 15 then return nil end
  return utc_to_unix(
    tonumber(s:sub(1, 4)), tonumber(s:sub(5, 6)), tonumber(s:sub(7, 8)),
    tonumber(s:sub(10, 11)), tonumber(s:sub(12, 13)), tonumber(s:sub(14, 15))
  )
end

local function fmt_dur(secs)
  local h = math.floor(secs / 3600)
  local m = math.floor((secs % 3600) / 60)
  return h > 0 and string.format("%dh%02dm", h, m) or string.format("%dm", m)
end

-- Returns hint unchanged if it is in the allowed list, otherwise returns fallback.
-- Prevents shell injection when hint is interpolated into shell commands.
local function validate_hint(hint, allowed, fallback)
  allowed = allowed or M.range_hints
  fallback = fallback or "week"
  for _, h in ipairs(allowed) do
    if h == hint then return hint end
  end
  return fallback
end

local function half_width(w)
  if type(w) == "number" then
    return math.floor(w / 2)
  end
  local pct = w:match("^(%d+)%%$")
  if pct then
    return math.floor(tonumber(pct) / 2) .. "%"
  end
  return w
end

local _status_cache = { tracking_since = nil, tags = "", expires = 0 }

-- nui popups and the terminal chart window both need explicit close tracking
-- because BufLeave / WinLeave events are unreliable across popup mounts.
local _chart = { winid = nil, bufnr = nil }
local _popup_close = nil

local function close_popup()
  if _popup_close then
    local fn = _popup_close
    _popup_close = nil
    fn()
  end
end

local function close_chart()
  local w, b = _chart.winid, _chart.bufnr
  _chart.winid, _chart.bufnr = nil, nil
  if w and vim.api.nvim_win_is_valid(w) then
    pcall(vim.api.nvim_win_close, w, true)
  end
  if b and vim.api.nvim_buf_is_valid(b) then
    pcall(vim.api.nvim_buf_delete, b, { force = true })
  end
end

-- Shared popup factory with sensible defaults. cfg is merged on top of the defaults.
-- Pass close_q=true to also bind 'q' as a close key.
-- Closes any currently open popup before creating the new one.
-- Returns an unmounted popup; caller is responsible for popup:mount().
local function make_popup(cfg, close_q)
  close_popup()
  close_chart()
  vim.api.nvim_set_hl(0, 'border', { fg = "#dadada" })
  local popup = Popup(vim.tbl_deep_extend("force", {
    position = '50%',
    enter = true,
    focusable = true,
    zindex = 10,
    relative = 'editor',
    buf_options = { modifiable = true, readonly = false },
    win_options = {
      winblend = 10,
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
    border = {
      style = "rounded",
      padding = { top = 1, bottom = 1, left = 1, right = 1 },
    },
  }, cfg))
  popup.border:set_highlight('border')
  popup:map('n', '<Esc>', function() popup:unmount() end, { noremap = true })
  popup:map('n', '<CR>',  function() popup:unmount() end, { noremap = true })
  if close_q then
    popup:map('n', 'q', function() popup:unmount() end, { noremap = true })
  end
  popup:on(event.BufLeave, function()
    _popup_close = nil
    popup:unmount()
  end)
  _popup_close = function() popup:unmount() end
  return popup
end

local function get_tags_for_range(sorter)
  return get_command_results("timew tags " .. sorter .. " | awk 'NR > 3 && /.+/ { print $1 }'")
end

-- Returns a string describing the currently tracked interval, e.g. "work coding (1h23m)".
-- Returns "" when nothing is tracked.
-- Suitable for use in statusline plugins (lualine, heirline, etc.).
-- The timew query is cached for M.config.status_refresh seconds (default 10).
M.status = function()
  local now = os.time()

  if now >= _status_cache.expires then
    local result = vim.fn.system({ "timew", "export" })
    _status_cache.expires = now + M.config.status_refresh

    local ok, data = pcall(vim.fn.json_decode, result)
    if not ok or type(data) ~= "table" or #data == 0 then
      _status_cache.tracking_since = nil
      _status_cache.tags = ""
    else
      local last = data[#data]
      if last and not last["end"] then
        _status_cache.tracking_since = parse_timew_ts(last.start)
        _status_cache.tags = table.concat(last.tags or {}, " ")
      else
        _status_cache.tracking_since = nil
        _status_cache.tags = ""
      end
    end
  end

  if not _status_cache.tracking_since then
    return ""
  end

  local elapsed = math.max(0, now - _status_cache.tracking_since)
  return _status_cache.tags .. " (" .. fmt_dur(elapsed) .. ")"
end

M.summary = function(opts)
  close_chart()
  local sorter = ':' .. validate_hint(opts)
  local command = { 'timew', 'summary', ':ids', sorter }

  local popup = make_popup({
    size = { width = M.config.size.width, height = M.config.size.height },
    border = { text = {
      top = " Summary ",
      top_align = "center",
      bottom = NuiText("<Esc|q> exit", "Error"),
      bottom_align = "left",
    }},
    win_options = { wrap = false, linebreak = false },
  }, true)
  popup:mount()

  vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        local to_buf = vim.tbl_filter(function(v) return v ~= "" end, data)
        vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, to_buf)
        vim.bo[popup.bufnr].modifiable = false
      end
    end,
  })
end

M.tags = function(opts)
  close_chart()
  local sorter = ':' .. validate_hint(opts)
  local lines = get_tags_for_range(sorter)

  local popup = make_popup({
    size = { width = half_width(M.config.size.width), height = M.config.size.height },
    border = { text = {
      top = " Tags ",
      top_align = "center",
      bottom = NuiText("<Esc> exit", "Error"),
      bottom_align = "left",
    }},
  })
  popup:mount()

  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
  vim.bo[popup.bufnr].modifiable = false
end

M.track_tag = function(opts)
  close_chart()
  local sorter = ':' .. validate_hint(opts)
  local tags = get_tags_for_range(sorter)

  pickers.new({}, {
    prompt_title = "tags",
    finder = finders.new_table({ results = tags }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        if selection then
          local result = selection.value
          vim.fn.system({ "timew", "track", result })
          _status_cache.expires = 0
          vim.notify("Tracking: " .. result, vim.log.levels.INFO, { title = "Timewarrior" })
        end
        actions.close(prompt_bufnr)
      end)
      return true
    end,
  }):find()
end

M.track = function()
  close_popup()
  close_chart()
  local Input = require("nui.input")

  local input = Input({
    position = "50%",
    size = { width = "50%" },
    border = {
      padding = { top = 1, bottom = 1, left = 1, right = 1 },
      style = "rounded",
      text = {
        top = " Track ",
        top_align = "center",
        bottom = NuiText("<Esc> cancel | <CR> start", "Normal"),
        bottom_align = "left",
      },
    },
    win_options = {
      winblend = 10,
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
  }, {
    prompt = "> ",
    on_close = function() end,
    on_submit = function(value)
      if value and value ~= "" then
        local tags = vim.split(value, "%s+", { trimempty = true })
        local cmd = vim.list_extend({ "timew", "track" }, tags)
        vim.fn.system(cmd)
        _status_cache.expires = 0
        vim.notify("Tracking: " .. value, vim.log.levels.INFO, { title = "Timewarrior" })
      end
    end,
  })

  input:mount()
end

M.week = function(opts)
  close_chart()
  opts = opts or 'week'
  local sorter = ':' .. validate_hint(opts)
  local data_raw = vim.fn.system({ "timew", "export", sorter })
  local ok, data = pcall(vim.fn.json_decode, data_raw)
  if not ok or type(data) ~= "table" then
    vim.notify("timewarrior.nvim: could not parse timew export output", vim.log.levels.ERROR)
    return
  end

  local tag_totals = {}
  local day_totals = {}
  local total_secs = 0

  for _, entry in ipairs(data) do
    if entry["end"] then
      local s = parse_timew_ts(entry.start)
      local e = parse_timew_ts(entry["end"])
      if s and e then
        local dur = e - s
        total_secs = total_secs + dur
        local day_key = os.date("%Y-%m-%d %a", s)
        day_totals[day_key] = (day_totals[day_key] or 0) + dur
        for _, tag in ipairs(entry.tags or {}) do
          tag_totals[tag] = (tag_totals[tag] or 0) + dur
        end
      end
    end
  end

  if total_secs == 0 then
    vim.notify("timewarrior.nvim: no completed intervals in range", vim.log.levels.WARN)
    return
  end

  local sorted_tags = {}
  for tag, secs in pairs(tag_totals) do
    table.insert(sorted_tags, { tag = tag, secs = secs })
  end
  table.sort(sorted_tags, function(a, b) return a.secs > b.secs end)

  local max_tag_len = 3
  for _, item in ipairs(sorted_tags) do
    if #item.tag > max_tag_len then max_tag_len = #item.tag end
  end
  max_tag_len = math.min(max_tag_len, 40)

  -- Use as much width as the editor allows; leave a 4-col margin each side.
  -- Fixed columns: 2 (indent) + max_tag_len + 2 + 8 (time) + 2 + 7 (pct) + 2 = 23 + max_tag_len
  local popup_width = math.min(vim.o.columns - 4, 120)
  local BAR = math.max(20, popup_width - max_tag_len - 23)
  local col_fmt = "  %-" .. max_tag_len .. "s  %8s  %s"
  local sep = "  " .. string.rep("─", max_tag_len + BAR + 14)

  local lines = {}
  table.insert(lines, string.format(col_fmt, "Tag", "Time", ""))
  table.insert(lines, sep)
  for _, item in ipairs(sorted_tags) do
    local pct = item.secs / total_secs
    local filled = math.floor(pct * BAR)
    local bar = string.rep("█", filled) .. string.rep("░", BAR - filled)
    local pct_str = string.format("(%2.0f%%)", pct * 100)
    local tag = #item.tag > max_tag_len and (item.tag:sub(1, max_tag_len - 1) .. "…") or item.tag
    table.insert(lines, string.format(col_fmt, tag, fmt_dur(item.secs), bar .. " " .. pct_str))
  end
  table.insert(lines, sep)
  table.insert(lines, string.format(col_fmt, "Total", fmt_dur(total_secs), ""))

  local sorted_days = {}
  for day, secs in pairs(day_totals) do
    table.insert(sorted_days, { day = day, secs = secs })
  end
  table.sort(sorted_days, function(a, b) return a.day < b.day end)
  if #sorted_days > 0 then
    table.insert(lines, "")
    for _, item in ipairs(sorted_days) do
      table.insert(lines, string.format("  %-16s  %8s", item.day, fmt_dur(item.secs)))
    end
  end

  local popup = make_popup({
    size = { width = popup_width, height = #lines },
    border = { text = {
      top = " " .. opts .. " summary ",
      top_align = "center",
      bottom = NuiText("<Esc|q> exit", "Error"),
      bottom_align = "left",
    }},
    win_options = { wrap = false, linebreak = false },
  }, true)
  popup:mount()

  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
  vim.bo[popup.bufnr].modifiable = false
end

M.chart = function(opts)
  close_popup()
  close_chart()

  local chart_type = validate_hint(opts or "week", { "day", "week", "month" }, "week")

  local width = vim.o.columns - 4
  local height = math.min(vim.o.lines - 4, 24)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local bufnr = vim.api.nvim_create_buf(false, true)
  local winid = vim.api.nvim_open_win(bufnr, false, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. chart_type .. ' chart ',
    title_pos = 'center',
  })
  vim.wo[winid].winblend = 10

  _chart.winid = winid
  _chart.bufnr = bufnr

  -- TermClose fires after Neovim has appended the "[Process exited N]" marker,
  -- so this strip pass actually has something to remove.
  vim.api.nvim_create_autocmd('TermClose', {
    buffer = bufnr,
    once = true,
    callback = function()
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        vim.bo[bufnr].modifiable = true
        local n = vim.api.nvim_buf_line_count(bufnr)
        while n > 0 do
          local l = vim.api.nvim_buf_get_lines(bufnr, n - 1, n, false)[1] or ''
          if l == '' or l:find('%[Process exited') then
            vim.api.nvim_buf_set_lines(bufnr, n - 1, n, false, {})
            n = n - 1
          else
            break
          end
        end
        vim.bo[bufnr].modifiable = false
        if vim.api.nvim_win_is_valid(winid) then
          vim.api.nvim_win_set_cursor(winid, { 1, 0 })
        end
        vim.keymap.set('n', 'q',     close_chart, { buffer = bufnr, noremap = true })
        vim.keymap.set('n', '<Esc>', close_chart, { buffer = bufnr, noremap = true })
        vim.cmd('stopinsert')
      end)
    end,
  })

  vim.api.nvim_buf_call(bufnr, function()
    vim.fn.termopen({ "timew", chart_type })
  end)

  vim.api.nvim_set_current_win(winid)
end

M.stop = function()
  M.status()  -- ensure cache is fresh so we can read the current tags
  local tags = _status_cache.tags
  vim.fn.system({ "timew", "stop" })
  _status_cache.expires = 0
  if tags ~= "" then
    vim.notify("Stopped: " .. tags, vim.log.levels.INFO, { title = "Timewarrior" })
  end
end

M.continue = function()
  vim.fn.system({ "timew", "continue" })
  _status_cache.expires = 0
  M.status()
  if _status_cache.tags ~= "" then
    vim.notify("Tracking: " .. _status_cache.tags, vim.log.levels.INFO, { title = "Timewarrior" })
  end
end

local function on_save_edit_time_action(bufnr, index, modify)
  local timestamp = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[1]
  if not timestamp or timestamp == "" then
    vim.notify("No timestamp to save", vim.log.levels.ERROR, { title = "Timewarrior" })
    return
  end
  local output = vim.fn.system({ "timew", "modify", modify, index, timestamp, ":adjust" })
  _status_cache.expires = 0
  if vim.v.shell_error == 0 then
    vim.notify("Saved " .. index, vim.log.levels.INFO, { title = "Timewarrior" })
  else
    vim.notify("Error saving " .. index .. ": " .. vim.trim(output), vim.log.levels.ERROR, { title = "Timewarrior" })
  end
end

local function error_popup(content)
  local popup = make_popup({
    size = { width = "80%", height = 1 },
    border = { text = {
      top = "Error",
      top_align = "center",
      bottom = NuiText("<Esc|q> exit", "Normal"),
      bottom_align = "left",
    }},
  }, true)
  popup:mount()
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, vim.split(content, "\n"))
  vim.bo[popup.bufnr].modifiable = false
end

local function edit_time(content, modify)
  local index, timestamp_start, timestamp_end, tags = content:match("^(%S+)%s+(%S+)%s+-%s+(%S+)%s+(.+)$")
  if not index then
    error_popup("Could not parse entry")
    return
  end
  if modify == "end" and string.match(timestamp_end, "^%-") then
    error_popup("Can't edit the end time of an open entry, run :TimewStop before doing it")
    return
  end

  local popup = make_popup({
    size = { width = "50%", height = 1 },
    border = { text = {
      top = " Edit entry: " .. index .. " [" .. tags .. "]",
      top_align = "center",
      bottom = NuiText("<Esc> exit | <C-s> save", "Normal"),
      bottom_align = "left",
    }},
  })
  popup:map('n', '<C-s>', function()
    on_save_edit_time_action(popup.bufnr, index, modify)
    popup:unmount()
  end, { noremap = true })
  popup:mount()

  local timestamp = (modify == "start" and timestamp_start or timestamp_end)
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, vim.split(timestamp, "\n"))
end

local function select_start_end(content)
  local Menu = require("nui.menu")

  local t = vim.split(content, "%s+", { trimempty = true })
  local all_tags = table.concat(t, " ", 5)

  local menu = Menu({
    position = "50%",
    size = {
      width = 39,
      height = 2,
    },
    border = {
      style = "single",
      text = {
        top = "Modifying " .. all_tags,
        top_align = "center",
        bottom = (t[2] or "") .. " " .. (t[3] or "") .. " " .. (t[4] or ""),
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:Normal",
    },
  }, {
    lines = {
      Menu.item("start"),
      Menu.item("end"),
    },
    max_width = 20,
    keymap = {
      focus_next = { "j", "<Down>", "<Tab>" },
      focus_prev = { "k", "<Up>", "<S-Tab>" },
      close = { "<Esc>", "<C-c>" },
      submit = { "<CR>", "<Space>" },
    },
    on_close = function() end,
    on_submit = function(item)
      edit_time(content, item.text)
    end,
  })

  menu:mount()
end

M.edit = function(opts)
  close_chart()
  local sorter = ':' .. validate_hint(opts)

  local function is_gnu_date()
    local handle = io.popen("date --version 2>/dev/null")
    if not handle then
      return false
    end
    local result = handle:read("*a")
    handle:close()
    return result ~= nil and result:find("GNU coreutils") ~= nil
  end

  local gnu_date = is_gnu_date()

  local jq_cmd =
  [[ | jq -r '.[] | "@\(.id) \(.start[0:4] + "-" + .start[4:6] + "-" + .start[6:11] + ":" + .start[11:13] + ":" + .start[13:15]) \(.end[0:4] + "-" + .end[4:6] + "-" + .end[6:11] + ":" + .end[11:13] + ":" + .end[13:15]) \(.tags | join(" "))"']]

  local awk_script = [[awk '{
    cmd2 = "]] .. (gnu_date
    and [[date -d \"" $2 " UTC\" +\"%Y-%m-%dT%H:%M:%S\"]]
    or  [[date -j -f \"%Y-%m-%dT%H:%M:%S %z\" \"" $2 " +0000\" +\"%Y-%m-%dT%H:%M:%S\"]]) .. [[";
    cmd3 = "]] .. (gnu_date
    and [[date -d \"" $3 " UTC\" +\"%Y-%m-%dT%H:%M:%S\"]]
    or  [[date -j -f \"%Y-%m-%dT%H:%M:%S %z\" \"" $3 " +0000\" +\"%Y-%m-%dT%H:%M:%S\"]]) .. [[ || echo \"-\"";
    cmd2 | getline local2;
    close(cmd2);
    cmd3 | getline local3;
    close(cmd3);
    printf "%-5s %s - %-22s %s\n", $1, local2, local3, $4
   }']]

  local command = "timew export " .. sorter .. jq_cmd .. " | " .. awk_script .. " 2> /dev/null"

  local entries = get_command_results(command)
  table.sort(entries, function(a, b)
    local numA = tonumber(a:match("@(%d+)"))
    local numB = tonumber(b:match("@(%d+)"))

    if numA == nil then
      return false
    elseif numB == nil then
      return true
    else
      return numA < numB
    end
  end)

  pickers.new({}, {
    prompt_title = "entries",
    results_title = "<C-s> Edit start | <C-e> Edit end | <C-d> Delete",
    finder = finders.new_table({ results = entries }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        if selection then
          local content = selection.value
          actions.close(prompt_bufnr)
          select_start_end(content)
        end
      end)

      map("i", "<C-s>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          local content = selection.value
          actions.close(prompt_bufnr)
          edit_time(content, "start")
        end
      end)

      map("i", "<C-e>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          local content = selection.value
          actions.close(prompt_bufnr)
          edit_time(content, "end")
        end
      end)

      map("i", "<C-d>", function()
        local selection = action_state.get_selected_entry()
        if not selection then return end
        local index = selection.value:match("^(%S+)")
        if not index then return end
        actions.close(prompt_bufnr)
        local confirm = vim.fn.confirm("Delete entry " .. index .. "?", "&Yes\n&No", 2)
        if confirm == 1 then
          vim.fn.system({ "timew", "delete", index, ":yes" })
          vim.notify("Deleted " .. index, vim.log.levels.INFO, { title = "Timewarrior" })
        end
      end)

      return true
    end,
  }):find()
end

M.setup = function(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end
  vim.api.nvim_create_user_command("TimewSummary", function(o)
    M.summary(o.fargs[1] or M.config.summary_hint)
  end, {
    nargs = '?',
    complete = function(_, _, _)
      return M.range_hints
    end,
  })

  vim.api.nvim_create_user_command("TimewTags", function(o)
    M.tags(o.fargs[1] or M.config.tags_hint)
  end, {
    nargs = '?',
    complete = function(_, _, _)
      return M.range_hints
    end,
  })

  vim.api.nvim_create_user_command("TimewTrackTag", function(o)
    M.track_tag(o.fargs[1] or M.config.tags_hint)
  end, {
    nargs = '?',
    complete = function(_, _, _)
      return M.range_hints
    end,
  })

  vim.api.nvim_create_user_command("TimewTrack", function(_)
    M.track()
  end, {})

  vim.api.nvim_create_user_command("TimewStop", function(_)
    M.stop()
  end, {})

  vim.api.nvim_create_user_command("TimewContinue", function(_)
    M.continue()
  end, {})

  vim.api.nvim_create_user_command("TimewEdit", function(o)
    M.edit(o.fargs[1] or M.config.edit_hint)
  end, {
    nargs = '?',
    complete = function(_, _, _)
      return M.range_hints
    end,
  })

  vim.api.nvim_create_user_command("TimewChart", function(o)
    M.chart(o.fargs[1] or "week")
  end, {
    nargs = '?',
    complete = function() return { "day", "week", "month" } end,
  })

  vim.api.nvim_create_user_command("TimewWeek", function(o)
    M.week(o.fargs[1] or M.config.summary_hint)
  end, {
    nargs = '?',
    complete = function(_, _, _)
      return M.range_hints
    end,
  })
end

return M
