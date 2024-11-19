local has_telescope, telescope = pcall(require, "telescope")

if not has_telescope then
  error("timewarrior.nvim requires nvim-telescope/telescope.nvim")
end

local timewarrior = require("timewarrior")

return telescope.register_extension({
  setup = timewarrior.setup,
  exports = {
    timewarrior_track_tag = require("timewarrior").track_tag(),
  },
})
