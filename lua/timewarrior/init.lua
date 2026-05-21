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

local _status_cache = { tracking_since = nil, tags = "", expires = 0 }

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
  local h = math.floor(elapsed / 3600)
  local m = math.floor((elapsed % 3600) / 60)
  local duration = h > 0 and string.format("%dh%02dm", h, m) or string.format("%dm", m)
  return _status_cache.tags .. " (" .. duration .. ")"
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

M.summary = function(opts, width, height)
  local sorter = ':' .. opts
  local command = { 'timew', 'summary', ':ids', sorter }

  vim.api.nvim_set_hl(0, 'border', { fg = "#dadada" })
  local popup = Popup({
    position = '50%',
    size = {
      width = width,
      height = height,
    },
    enter = true,
    focusable = true,
    zindex = 10,
    relative = 'editor',
    border = {
      padding = {
        top = 1,
        bottom = 1,
        left = 1,
        right = 1,
      },
      style = "rounded",
      text = {
        top = " Summary ",
        top_align = "center",
        bottom_align = "left",
        bottom = NuiText("<Esc|q> exit", "Error"),
      },
    },
    buf_options = {
      modifiable = true,
      readonly = false,
    },
    win_options = {
      winblend = 10,
      wrap = false,
      linebreak = false,
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
  })

  popup.border:set_highlight('border')

  popup:map('n', '<Esc>', function()
    popup:unmount()
  end, { noremap = true })

  popup:map('n', 'q', function()
    popup:unmount()
  end, { noremap = true })

  popup:mount()

  popup:on(event.BufLeave, function()
    popup:unmount()
  end)

  vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local to_buf = {}
      if data then
        for _, v in ipairs(data) do
          if v ~= "" then
            table.insert(to_buf, v)
          end
        end
        vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, to_buf)
        vim.api.nvim_buf_set_option(popup.bufnr, 'modifiable', false)
      end
    end,
  })
end

M.tags = function(opts, width, height)
  local sorter = ':' .. opts
  local command = "timew tags " .. sorter .. " | awk 'NR > 3 && /.+/ { print $1 }'"
  local lines = get_command_results(command)

  vim.api.nvim_set_hl(0, 'border', { fg = "#dadada" })
  local popup = Popup({
    position = '50%',
    size = {
      width = width,
      height = height,
    },
    enter = true,
    focusable = true,
    zindex = 10,
    relative = 'editor',
    border = {
      padding = {
        top = 1,
        bottom = 1,
        left = 1,
        right = 1,
      },
      style = "rounded",
      text = {
        top = " Tags ",
        top_align = "center",
        bottom_align = "left",
        bottom = NuiText("<Esc> exit", "Error"),
      },
    },
    buf_options = {
      modifiable = true,
      readonly = false,
    },
    win_options = {
      winblend = 10,
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
  })

  popup.border:set_highlight('border')

  popup:map('n', '<Esc>', function()
    popup:unmount()
  end, { noremap = true })

  popup:mount()

  popup:on(event.BufLeave, function()
    popup:unmount()
  end)

  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(popup.bufnr, 'modifiable', false)
end

M.track_tag = function(opts)
  local sorter = ':' .. opts
  local command = "timew tags " .. sorter .. " | awk 'NR > 3 && /.+/ { print $1 }'"
  local tags = get_command_results(command)

  pickers.new({}, {
    prompt_title = "tags",
    finder = finders.new_table({ results = tags }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        if selection then
          local result = selection.value
          vim.fn.system("timew track " .. vim.fn.shellescape(result))
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
  local sorter = ':' .. (opts or 'week')
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

  local function fmt_dur(secs)
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    return h > 0 and string.format("%dh%02dm", h, m) or string.format("%dm", m)
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

  local popup_height = #lines

  vim.api.nvim_set_hl(0, 'border', { fg = "#dadada" })
  local popup = Popup({
    position = '50%',
    size = { width = popup_width, height = popup_height },
    enter = true,
    focusable = true,
    zindex = 10,
    relative = 'editor',
    border = {
      padding = { top = 1, bottom = 1, left = 1, right = 1 },
      style = "rounded",
      text = {
        top = " " .. opts .. " summary ",
        top_align = "center",
        bottom = NuiText("<Esc|q> exit", "Error"),
        bottom_align = "left",
      },
    },
    buf_options = { modifiable = true, readonly = false },
    win_options = {
      winblend = 10,
      wrap = false,
      linebreak = false,
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
  })

  popup.border:set_highlight('border')
  popup:map('n', '<Esc>', function() popup:unmount() end, { noremap = true })
  popup:map('n', 'q', function() popup:unmount() end, { noremap = true })
  popup:mount()
  popup:on(event.BufLeave, function() popup:unmount() end)

  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(popup.bufnr, 'modifiable', false)
end

M.chart = function(opts)
  local chart_type = opts or "week"
  local cmd = "timew " .. chart_type

  local width = vim.o.columns - 4
  local height = math.min(vim.o.lines - 4, 24)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local bufnr = vim.api.nvim_create_buf(false, true)
  local winid = vim.api.nvim_open_win(bufnr, true, {
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

  local function close()
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end

  vim.fn.termopen(cmd, {
    on_exit = function()
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end

        -- Neovim appends "[Process exited N]" to the terminal buffer.
        -- Switch the buffer out of terminal mode so we can edit it, then
        -- strip that trailing noise before the user sees it.
        pcall(function()
          vim.bo[bufnr].buftype = ''
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
        end)

        if vim.api.nvim_win_is_valid(winid) then
          vim.api.nvim_win_set_cursor(winid, { 1, 0 })
        end
        vim.keymap.set('n', 'q',     close, { buffer = bufnr, noremap = true })
        vim.keymap.set('n', '<Esc>', close, { buffer = bufnr, noremap = true })
        vim.cmd('stopinsert')
      end)
    end,
  })

  vim.api.nvim_create_autocmd('WinLeave', {
    buffer = bufnr,
    once = true,
    callback = close,
  })
end

M.stop = function()
  M.status()  -- ensure cache is fresh so we can read the current tags
  local tags = _status_cache.tags
  vim.fn.system("timew stop")
  _status_cache.expires = 0
  if tags ~= "" then
    vim.notify("Stopped: " .. tags, vim.log.levels.INFO, { title = "Timewarrior" })
  end
end

M.continue = function()
  vim.fn.system("timew continue")
  _status_cache.expires = 0
  M.status()
  if _status_cache.tags ~= "" then
    vim.notify("Tracking: " .. _status_cache.tags, vim.log.levels.INFO, { title = "Timewarrior" })
  end
end

local function on_save_edit_time_action(bufnr, index, modify)
  local timestamp = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[1]
  vim.fn.system({ "timew", "modify", modify, index, timestamp, ":adjust" })
end

local function error_popup(content)
  vim.api.nvim_set_hl(0, 'border', { fg = "#dadada" })
  local popup = Popup({
    position = '50%',
    size = {
      width = "80%",
      height = 1,
    },
    enter = true,
    focusable = true,
    zindex = 10,
    relative = 'editor',
    border = {
      padding = {
        top = 1,
        bottom = 1,
        left = 1,
        right = 1,
      },
      style = "rounded",
      text = {
        top = "Error",
        top_align = "center",
        bottom_align = "left",
        bottom = NuiText("<Esc|q> exit", "Normal"),
      },
    },
    buf_options = {
      modifiable = true,
      readonly = false,
    },
    win_options = {
      winblend = 10,
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
  })

  popup.border:set_highlight('border')

  popup:map('n', '<Esc>', function()
    popup:unmount()
  end, { noremap = true })

  popup:map('n', 'q', function()
    popup:unmount()
  end, { noremap = true })

  popup:mount()

  popup:on(event.BufLeave, function()
    popup:unmount()
  end)

  vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, vim.split(content, "\n"))
  vim.api.nvim_buf_set_option(popup.bufnr, 'modifiable', false)
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

  vim.api.nvim_set_hl(0, 'border', { fg = "#dadada" })
  local popup = Popup({
    position = '50%',
    size = {
      width = "50%",
      height = 1,
    },
    enter = true,
    focusable = true,
    zindex = 10,
    relative = 'editor',
    border = {
      padding = {
        top = 1,
        bottom = 1,
        left = 1,
        right = 1,
      },
      style = "rounded",
      text = {
        top = " Edit entry: " .. index .. " [" .. tags .. "]",
        top_align = "center",
        bottom_align = "left",
        bottom = NuiText("<Esc> exit | <C-s> save", "Normal"),
      },
    },
    buf_options = {
      modifiable = true,
      readonly = false,
    },
    win_options = {
      winblend = 10,
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
  })

  popup.border:set_highlight('border')

  popup:map('n', '<Esc>', function()
    popup:unmount()
  end, { noremap = true })

  popup:map('n', '<C-s>', function()
    on_save_edit_time_action(popup.bufnr, index, modify)
    popup:unmount()
  end, { noremap = true })

  popup:mount()
  local timestamp = (modify == "start" and timestamp_start or timestamp_end)
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, vim.split(timestamp, "\n"))

  popup:on(event.BufLeave, function()
    popup:unmount()
  end)
end

local function split_str(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
    table.insert(t, str)
  end
  return t
end

local function select_start_end(content)
  local Menu = require("nui.menu")

  local t = split_str(content)
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
        bottom = t[2] .. " " .. t[3] .. " " .. t[4],
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
    on_close = function()
      -- close
    end,
    on_submit = function(item)
      edit_time(content, item.text)
    end,
  })

  menu:mount()
end

M.edit = function(opts)
  local sorter = ':' .. opts

  local function is_gnu_date()
    local handle = io.popen("date --version 2>/dev/null")
    if not handle then
      return false
    end
    local result = handle:read("*a")
    handle:close()
    return result ~= nil and result:find("GNU coreutils") ~= nil
  end

  local jq_cmd =
  [[ | jq -r '.[] | "@\(.id) \(.start[0:4] + "-" + .start[4:6] + "-" + .start[6:11] + ":" + .start[11:13] + ":" + .start[13:15]) \(.end[0:4] + "-" + .end[4:6] + "-" + .end[6:11] + ":" + .end[11:13] + ":" + .end[13:15]) \(.tags | join(" "))"']]

  local awk_script = [[awk '{
    cmd2 = "]] .. (is_gnu_date()
    and [[date -d \"" $2 " UTC\" +\"%Y-%m-%dT%H:%M:%S\"]]
    or [[date -j -f \"%Y-%m-%dT%H:%M:%S %z\" \"" $2 " +0000\" +\"%Y-%m-%dT%H:%M:%S\"]]) .. [[";
    cmd3 = "]] .. (is_gnu_date()
    and [[date -d \"" $3 " UTC\" +\"%Y-%m-%dT%H:%M:%S\"]]
    or [[date -j -f \"%Y-%m-%dT%H:%M:%S %z\" \"" $3 " +0000\" +\"%Y-%m-%dT%H:%M:%S\"]]) .. [[ || echo \"-\"";
    cmd2 | getline local2;
    close(cmd2);
    cmd3 | getline local3;
    close(cmd3);
    printf "%-5s %s - %-22s %s\n", $1, local2, local3, $4
   }']]

  local full_cmd = jq_cmd .. " | " .. awk_script
  local command = "timew export " .. sorter .. full_cmd .. " 2> /dev/null"

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
          print("Deleted " .. index)
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
  vim.api.nvim_create_user_command("TimewSummary", function(opts)
    local hint = opts.fargs[1] and opts.fargs[1] or M.config.summary_hint
    M.summary(hint, M.config.size.width, M.config.size.height)
  end, {
    nargs = '?',
    complete = function(_, _, _)
      return M.range_hints
    end,
  })

  vim.api.nvim_create_user_command("TimewTags", function(opts)
    local hint = opts.fargs[1] and opts.fargs[1] or M.config.tags_hint
    M.tags(hint, half_width(M.config.size.width), M.config.size.height)
  end, {
    nargs = '?',
    complete = function(_, _, _)
      return M.range_hints
    end,
  })

  vim.api.nvim_create_user_command("TimewTrackTag", function(opts)
    local hint = opts.fargs[1] and opts.fargs[1] or M.config.tags_hint
    M.track_tag(hint)
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

  vim.api.nvim_create_user_command("TimewEdit", function(opts)
    local hint = opts.fargs[1] and opts.fargs[1] or M.config.edit_hint
    M.edit(hint)
  end, {
    nargs = '?',
    complete = function(_, _, _)
      return M.range_hints
    end,
  })

  vim.api.nvim_create_user_command("TimewChart", function(opts)
    local hint = opts.fargs[1] or "week"
    M.chart(hint)
  end, {
    nargs = '?',
    complete = function() return { "day", "week", "month" } end,
  })

  vim.api.nvim_create_user_command("TimewWeek", function(opts)
    local hint = opts.fargs[1] and opts.fargs[1] or M.config.summary_hint
    M.week(hint)
  end, {
    nargs = '?',
    complete = function(_, _, _)
      return M.range_hints
    end,
  })
end

return M
