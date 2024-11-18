local Popup = require("nui.popup")
local NuiText = require("nui.text")
local event = require("nui.utils.autocmd").event

local M = {}

M.config = {
  summary_hint = 'week',
  size = {
    width = '75%',
    height = '25%',
  },
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
        bottom = NuiText("q <quit>", "Error"),
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
        vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, to_buf)
      end
    end,
  })
end

M.setup = {
  vim.api.nvim_create_user_command("TimewSummary", function(opts)
    local hint = opts.fargs[1] and opts.fargs[1] or M.config.summary_hint
    M.summary(hint, M.config.size.width, M.config.size.height)
  end, {
    nargs = '?',
    complete = function(_, _, _)
      return {
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
    end,
  })
}

return M
