-- Verify dependencies are installed
local has_telescope, telescope = pcall(require, 'telescope')

if not has_telescope then
  error(
    'cder requires telescope.nvim: https://github.com/nvim-telescope/telescope.nvim'
  )
end

local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local previewers = require('telescope.previewers')
local sorters = require('telescope.sorters')

local opts = {
  -- The title of the prompt.
  prompt_title = function()
    return 'cwd: ' .. vim.fn.getcwd()
  end,

  -- The command used to generate a list of directories.
  -- Defaults to fd on the home directory.
  -- Example for showing hidden directories:
  --   dir_command = { 'fd', '--hidden', '--type=d', '.', os.getenv('HOME') },
  -- Example for excluding certain directories:
  --   dir_command = { 'fd', '--exclude=Library', '--exclude=Pictures', '--type=d', '.', os.getenv('HOME') },
  dir_command = { 'fd', '--type=d', '.', os.getenv('HOME') },

  -- The binary used to execute previewer_command | pager_command.
  -- This is needed because termopen in Neovim does not support piping
  -- multiple commands, so we get around this by just using bash -c.
  command_executer = { 'bash', '-c' },

  -- The command used to preview directories. Defaults to ls.
  -- Example:
  --   previewer_command = 'exa -a --icons'
  previewer_command = 'ls -a',

  -- A function to return an entry given an entry produced
  -- by dir_command. Returns the entry directly by default.
  entry_value_fn = function(entry_value)
    if vim.loop.os_uname().sysname == 'Windows_NT' then
      return '"' .. entry_value:gsub("\\$", "") .. '"'
    else
      return '"' .. entry_value .. '"'
    end
  end,

  -- The command used to page directory previews. Defaults to bat.
  -- Receives the output of the previewer_command as input.
  -- Example without bat:
  --   pager_command = 'less -RS'
  pager_command = 'bat --plain --paging=always --pager="less -RS"',

  -- Function to create an entry in the picker given
  -- a line outputted from the dir_command.
  --   value is used as the directory in the :cd command
  --   display is what is actually displayed, so this can
  --     be a function that trims a path prefix for example.
  entry_maker = function(line)
    local folder_icon = ' '
    return {
      value = line,
      display = function(entry)
        if vim.loop.os_uname().sysname == 'Windows_NT' then
          return folder_icon .. line:gsub(os.getenv('USERPROFILE') .. "\\", ''),
            { { { 1, 3 }, 'Directory' } }
        else
          return folder_icon .. line:gsub(os.getenv('HOME') .. '/', ''),
            { { { 1, 3 }, 'Directory' } }
        end
      end,
      ordinal = line,
    }
  end,

  -- A mapping should be a function that takes as parameter the selected
  -- directory as a string.
  mappings = {
    default = function(directory)
      vim.cmd.cd(directory)
    end,
    ['<C-t>'] = function(directory)
      vim.cmd.tcd(directory)
    end,
  },
}

-- TODO: call after setup if OS is Windows series
local function config_for_windows(o)
  dir_command = { 'dir', '/B', '.', }
  command_executer = { 'cmd.exe', '/c' }
  previewer_command = 'dir /B'
end

local function setup(o)
  o = o or {}
  opts = vim.tbl_deep_extend('force', opts, o)
end

local function mapping(prompt_bufnr, command)
  return function()
    -- Close Telescope window
    actions.close(prompt_bufnr)

    local directory = action_state.get_selected_entry().value
    if directory ~= nil then
      command(directory)
    end
  end
end

local function resolve_given_param(param)
  local param_type = type(param)
  if param_type == 'function' then
    return param()
  else
    return param
  end
end

local function run(o)
  o = o and vim.tbl_deep_extend('force', opts, o) or opts
  o.prompt_title = resolve_given_param(o.prompt_title)
  pickers
    .new(o, {
      prompt_title = o.prompt_title,
      finder = finders.new_oneshot_job(o.dir_command, o),
      previewer = previewers.new_termopen_previewer({

        get_command = function(entry)
          return vim.tbl_flatten({
            o.command_executer,
            o.previewer_command
              .. ' '
              .. o.entry_value_fn(entry.value)
              .. ' | '
              .. o.pager_command,
          })
        end,
      }),
      sorter = sorters.get_fuzzy_file(),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(
          mapping(prompt_bufnr, opts.mappings.default)
        )

        -- Other mappings
        for key, command in pairs(opts.mappings) do
          if key ~= 'default' then
            map('i', key, mapping(prompt_bufnr, command))
            map('n', key, mapping(prompt_bufnr, command))
          end
        end

        return true
      end,
    })
    :find()
end

return telescope.register_extension({
  setup = setup,
  exports = {
    cder = run,
  },
})
