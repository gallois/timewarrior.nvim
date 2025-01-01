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
        bottom = NuiText("<Esc> exit", "Error"),
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
        vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, to_buf)
        vim.api.nvim_buf_set_option(popup.bufnr, 'modifiable', false)
      end
    end,
  })
end

M.tags = function(opts, width, height)
  local sorter = ':' .. opts
  local command = "timew tags " .. sorter .. " | awk 'NR > 3 && /.+/ { print $1 }'"

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
        vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, to_buf)
      end
    end,
  })
end

local function get_command_results(command)
  local result = vim.fn.systemlist(command)

  local tags = {}
  for _, line in ipairs(result) do
    if line ~= "" then
      table.insert(tags, line)
    end
  end

  return tags
end

M.track_tag = function(opts)
  local sorter = ':' .. opts
  local command = "timew tags " .. sorter .. " | awk 'NR > 3 && /.+/ { print $1 }'"
  local tags = get_command_results(command)

  pickers.new({}, {
    prompt_title = "tags",
    finder = finders.new_table({ results = tags }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        if selection then
          local result = selection.value
          vim.fn.system("timew track " .. vim.fn.shellescape(result))
          print("Tracking: " .. result)
        end
        actions.close(prompt_bufnr)
      end)
      return true
    end,
  }):find()
end

M.stop = function()
  vim.fn.system("timew stop")
end

M.continue = function()
  vim.fn.system("timew continue")
end

local function on_save_edit_time_action(bufnr, index, modify)
  vim.fn.system("timew modify " ..
    modify .. " " .. index .. " " .. vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[1] .. " :adjust")
  print("timew modify " ..
    modify .. " " .. index .. " " .. vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[1] .. " :adjust")
end

local function edit_time(content, modify)
  local index, timestamp_start, timestamp_end, tags = content:match("^(%S+)%s+(%S+)%s+-%s+(%S+)%s+(.+)$")
  -- local timestamps = timestamp_start .. " - " .. timestamp_end

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

M.edit = function(opts)
  local sorter = ':' .. opts
  local command = "timew export " ..
      sorter ..
      " | jq -r '.[] | \"@\\(.id) \\(.start[0:4] + \"-\" + .start[4:6] + \"-\" + .start[6:11] + \":\" + .start[11:13] + \":\" + .start[13:15]) \\(.end[0:4] + \"-\" + .end[4:6] + \"-\" + .end[6:11] + \":\" + .end[11:13] + \":\" + .end[13:15]) \\(.tags | join(\" \"))\"' | awk '{printf \"%-5s %s - %-22s %s\\n\", $1, $2, $3, $4}'"

  local entries = get_command_results(command)
  table.sort(entries, function(a, b)
    local numA = tonumber(a:match("@(%d+)"))
    local numB = tonumber(b:match("@(%d+)"))
    return numA < numB
  end)

  pickers.new({}, {
    prompt_title = "entries",
    results_title = "<C-s> Edit start time | <C-e> Edit end time",
    finder = finders.new_table({ results = entries }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        if selection then
          local result = selection.value
          -- FIXME do something
          -- vim.fn.system("timew track " .. vim.fn.shellescape(result))
          -- print("Tracking: " .. result)
        end
        actions.close(prompt_bufnr)
      end)

      map("i", "<C-s>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          local content = selection.value
          print(content)
          actions.close(prompt_bufnr)
          edit_time(content, "start")
        end
      end)

      map("i", "<C-e>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          local content = selection.value
          print(content)
          actions.close(prompt_bufnr)
          edit_time(content, "end")
        end
      end)


      return true
    end,
  }):find()
end

M.setup = function(config)
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
    M.tags(hint, M.config.size.width / 2, M.config.size.height)
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

  vim.api.nvim_create_user_command("TimewStop", function(_)
    M.stop()
  end, {})

  vim.api.nvim_create_user_command("TimewContinue", function(_)
    M.continue()
  end, {})

  vim.api.nvim_create_user_command("TimewEdit", function(opts)
    local hint = opts.fargs[1] and opts.fargs[1] or M.config.tags_hint
    M.edit(hint)
  end, {})
end

return M
