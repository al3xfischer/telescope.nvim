local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local action_set = require('telescope.actions.set')
local finders = require('telescope.finders')
local make_entry = require('telescope.make_entry')
local pickers = require('telescope.pickers')
local previewers = require('telescope.previewers')
local utils = require('telescope.utils')
local conf = require('telescope.config').values

local scan = require('plenary.scandir')
local Path = require('plenary.path')
local os_sep = Path.path.sep

local flatten = vim.tbl_flatten
local filter = vim.tbl_filter

local files = {}

local escape_chars = function(string)
  return string.gsub(string,  "[%(|%)|\\|%[|%]|%-|%{%}|%?|%+|%*]", {
    ["\\"] = "\\\\", ["-"] = "\\-",
    ["("] = "\\(", [")"] = "\\)",
    ["["] = "\\[", ["]"] = "\\]",
    ["{"] = "\\{", ["}"] = "\\}",
    ["?"] = "\\?", ["+"] = "\\+",
    ["*"] = "\\*",
  })
end

-- Special keys:
--  opts.search_dirs -- list of directory to search in
--  opts.grep_open_files -- boolean to restrict search to open files
files.live_grep = function(opts)
  local vimgrep_arguments = opts.vimgrep_arguments or conf.vimgrep_arguments
  local search_dirs = opts.search_dirs
  local grep_open_files = opts.grep_open_files
  opts.cwd = opts.cwd and vim.fn.expand(opts.cwd) or vim.loop.cwd()

  local filelist = {}

  if grep_open_files then
   local bufnrs = filter(function(b)
      if 1 ~= vim.fn.buflisted(b) then return false end
      return true
    end, vim.api.nvim_list_bufs())
    if not next(bufnrs) then return end

    local tele_path = require'telescope.path'
    for _, bufnr in ipairs(bufnrs) do
      local file = vim.api.nvim_buf_get_name(bufnr)
      table.insert(filelist, tele_path.make_relative(file, opts.cwd))
    end
  elseif search_dirs then
    for i, path in ipairs(search_dirs) do
      search_dirs[i] = vim.fn.expand(path)
    end
  end

  local live_grepper = finders.new_job(function(prompt)
      -- TODO: Probably could add some options for smart case and whatever else rg offers.

      if not prompt or prompt == "" then
        return nil
      end

      prompt = escape_chars(prompt)

      local search_list = {}

      if search_dirs then
        table.insert(search_list, search_dirs)
      elseif os_sep == '\\' then
        table.insert(search_list, '.')
      end

      if grep_open_files then
        search_list = filelist
      end

      return flatten { vimgrep_arguments, prompt, search_list }
    end,
    opts.entry_maker or make_entry.gen_from_vimgrep(opts),
    opts.max_results,
    opts.cwd
  )

  pickers.new(opts, {
    prompt_title = 'Live Grep',
    finder = live_grepper,
    previewer = conf.grep_previewer(opts),
    sorter = conf.generic_sorter(opts),
  }):find()
end


-- Special keys:
--  opts.search -- the string to search.
--  opts.search_dirs -- list of directory to search in
files.grep_string = function(opts)
  -- TODO: This should probably check your visual selection as well, if you've got one

  local vimgrep_arguments = opts.vimgrep_arguments or conf.vimgrep_arguments
  local search_dirs = opts.search_dirs
  local search = escape_chars(opts.search or vim.fn.expand("<cword>"))
  local word_match = opts.word_match
  opts.entry_maker = opts.entry_maker or make_entry.gen_from_vimgrep(opts)

  if search_dirs then
    for i, path in ipairs(search_dirs) do
      search_dirs[i] = vim.fn.expand(path)
    end
  end

  local args = flatten {
    vimgrep_arguments,
    word_match,
    search,
  }

  if search_dirs then
    table.insert(args, search_dirs)
  elseif os_sep == '\\' then
    table.insert(args, '.')
  end

  pickers.new(opts, {
    prompt_title = 'Find Word',
    finder = finders.new_oneshot_job(args, opts),
    previewer = conf.grep_previewer(opts),
    sorter = conf.generic_sorter(opts),
  }):find()
end

-- TODO: Maybe just change this to `find`.
--          Support `find` and maybe let people do other stuff with it as well.
files.find_files = function(opts)
  local find_command = opts.find_command
  local hidden = opts.hidden
  local follow = opts.follow
  local search_dirs = opts.search_dirs

  if search_dirs then
    for k,v in pairs(search_dirs) do
      search_dirs[k] = vim.fn.expand(v)
    end
  end

  if not find_command then
    if 1 == vim.fn.executable("fd") then
      find_command = { 'fd', '--type', 'f' }
      if hidden then table.insert(find_command, '--hidden') end
      if follow then table.insert(find_command, '-L') end
      if search_dirs then
        table.insert(find_command, '.')
        for _,v in pairs(search_dirs) do
          table.insert(find_command, v)
        end
      end
    elseif 1 == vim.fn.executable("fdfind") then
      find_command = { 'fdfind', '--type', 'f' }
      if hidden then table.insert(find_command, '--hidden') end
      if follow then table.insert(find_command, '-L') end
      if search_dirs then
        table.insert(find_command, '.')
        for _,v in pairs(search_dirs) do
          table.insert(find_command, v)
        end
      end
    elseif 1 == vim.fn.executable("rg") then
      find_command = { 'rg', '--files' }
      if hidden then table.insert(find_command, '--hidden') end
      if follow then table.insert(find_command, '-L') end
      if search_dirs then
        for _,v in pairs(search_dirs) do
          table.insert(find_command, v)
        end
      end
    elseif 1 == vim.fn.executable("find") then
      find_command = { 'find', '.', '-type', 'f' }
      if not hidden then
        table.insert(find_command, { '-not', '-path', "*/.*" })
        find_command = flatten(find_command)
      end
      if follow then table.insert(find_command, '-L') end
      if search_dirs then
        table.remove(find_command, 2)
        for _,v in pairs(search_dirs) do
          table.insert(find_command, 2, v)
        end
      end
    end
  end

  if not find_command then
    print("You need to install either find, fd, or rg. " ..
          "You can also submit a PR to add support for another file finder :)")
    return
  end

  if opts.cwd then
    opts.cwd = vim.fn.expand(opts.cwd)
  end

  opts.entry_maker = opts.entry_maker or make_entry.gen_from_file(opts)

  pickers.new(opts, {
    prompt_title = 'Find Files',
    finder = finders.new_oneshot_job(
      find_command,
      opts
    ),
    previewer = conf.file_previewer(opts),
    sorter = conf.file_sorter(opts),
  }):find()
end

local function prepare_match(entry, kind)
  local entries = {}

  if entry.node then
      entry["kind"] = kind
      table.insert(entries, entry)
  else
    for name, item in pairs(entry) do
        vim.list_extend(entries, prepare_match(item, name))
    end
  end

  return entries
end

files.file_browser = function(opts)
  opts = opts or {}

  opts.depth = opts.depth or 1
  opts.cwd = opts.cwd and vim.fn.expand(opts.cwd) or vim.loop.cwd()
  opts.new_finder = opts.new_finder or function(path)
    opts.cwd = path
    local data = {}

    scan.scan_dir(path, {
      hidden = opts.hidden or false,
      add_dirs = true,
      depth = opts.depth,
      on_insert = function(entry, typ)
        table.insert(data, typ == 'directory' and (entry .. os_sep) or entry)
      end
    })
    table.insert(data, 1, '..' .. os_sep)

    return finders.new_table {
      results = data,
      entry_maker = (function()
        local tele_path = require'telescope.path'
        local gen = make_entry.gen_from_file(opts)
        return function(entry)
          local tmp = gen(entry)
          tmp.ordinal = tele_path.make_relative(entry, opts.cwd)
          return tmp
        end
      end)()
    }
  end

  pickers.new(opts, {
    prompt_title = 'File Browser',
    finder = opts.new_finder(opts.cwd),
    previewer = conf.file_previewer(opts),
    sorter = conf.file_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      action_set.select:replace_if(function()
        return action_state.get_selected_entry().path:sub(-1) == os_sep
      end, function()
        local new_cwd = vim.fn.expand(action_state.get_selected_entry().path:sub(1, -2))
        local current_picker = action_state.get_current_picker(prompt_bufnr)
        current_picker.cwd = new_cwd
        current_picker:refresh(opts.new_finder(new_cwd), { reset_prompt = true })
      end)

      local create_new_file = function()
        local current_picker = action_state.get_current_picker(prompt_bufnr)
        local file = action_state.get_current_line()
        if file == "" then
          print('To create a new file or directory(add ' .. os_sep .. ' at the end of file) ' ..
                'write the desired new into the prompt and press <C-e>. ' ..
                'It works for not existing nested input as well.' ..
                'Example: this' .. os_sep .. 'is' .. os_sep .. 'a' .. os_sep .. 'new_file.lua')
          return
        end

        local fpath = current_picker.cwd .. os_sep .. file
        if string.sub(fpath, -1) ~= os_sep then
          actions.close(prompt_bufnr)
          Path:new(fpath):touch({ parents = true })
          vim.cmd(string.format(':e %s', fpath))
        else
          Path:new(fpath:sub(1, -2)):mkdir({ parents = true })
          local new_cwd = vim.fn.expand(fpath)
          current_picker.cwd = new_cwd
          current_picker:refresh(opts.new_finder(new_cwd), { reset_prompt = true })
        end
      end

      map('i', '<C-e>', create_new_file)
      map('n', '<C-e>', create_new_file)
      return true
    end,
  }):find()
end

files.treesitter = function(opts)
  opts.show_line = utils.get_default(opts.show_line, true)

  local has_nvim_treesitter, _ = pcall(require, 'nvim-treesitter')
  if not has_nvim_treesitter then
    print('You need to install nvim-treesitter')
    return
  end

  local parsers = require('nvim-treesitter.parsers')
  if not parsers.has_parser() then
    print('No parser for the current buffer')
    return
  end

  local ts_locals = require('nvim-treesitter.locals')
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

  local results = {}
  for _, definitions in ipairs(ts_locals.get_definitions(bufnr)) do
    local entries = prepare_match(definitions)
    for _, entry in ipairs(entries) do
      table.insert(results, entry)
    end
  end

  if vim.tbl_isempty(results) then
    return
  end

  pickers.new(opts, {
    prompt_title = 'Treesitter Symbols',
    finder    = finders.new_table {
      results = results,
      entry_maker = opts.entry_maker or make_entry.gen_from_treesitter(opts)
    },
    previewer = conf.grep_previewer(opts),
    sorter = conf.generic_sorter(opts),
  }):find()
end

files.current_buffer_fuzzy_find = function(opts)
  -- All actions are on the current buffer
  local bufnr = vim.api.nvim_get_current_buf()
  local filename = vim.fn.expand(vim.api.nvim_buf_get_name(bufnr))
  local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local lines_with_numbers = {}

  for lnum, line in ipairs(lines) do
    table.insert(lines_with_numbers, {
      lnum = lnum,
      bufnr = bufnr,
      filename = filename,
      text = line,
    })
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, filetype)
  if ok then
    local query = vim.treesitter.get_query(filetype, "highlights")

    local root = parser:parse()[1]:root()

    local highlighter = vim.treesitter.highlighter.new(parser)
    local highlighter_query = highlighter:get_query(filetype)

    local line_highlights = setmetatable({}, {
      __index = function(t, k)
        local obj = {}
        rawset(t, k, obj)
        return obj
      end,
    })
    for id, node in query:iter_captures(root, bufnr, 0, -1) do
      local hl = highlighter_query.hl_cache[id]
      if hl then
        local row1, col1, row2, col2 = node:range()

        if row1 == row2 then
          local row = row1 + 1

          for index = col1, col2 do
            line_highlights[row][index] = hl
          end
        else
          local row = row1 + 1
          for index = col1, #lines[row] do
              line_highlights[row][index] = hl
          end

          while row < row2 + 1 do
            row = row + 1

            for index = 0, #lines[row] do
              line_highlights[row][index] = hl
            end
          end
        end
      end
    end

    opts.line_highlights = line_highlights
  end

  pickers.new(opts, {
    prompt_title = 'Current Buffer Fuzzy',
    finder = finders.new_table {
      results = lines_with_numbers,
      entry_maker = opts.entry_maker or make_entry.gen_from_buffer_lines(opts),
    },
    sorter = conf.generic_sorter(opts),
    previewer = conf.grep_previewer(opts),
    attach_mappings = function()
      action_set.select:enhance {
        post = function()
          local selection = action_state.get_selected_entry()
          vim.api.nvim_win_set_cursor(0, { selection.lnum, 0 })
        end,
      }

      return true
    end
  }):find()
end

files.tags = function(opts)
  local ctags_file = opts.ctags_file or 'tags'

  if not vim.loop.fs_open(vim.fn.expand(ctags_file, true), "r", 438) then
    print('Tags file does not exists. Create one with ctags -R')
    return
  end

  local fd = assert(vim.loop.fs_open(vim.fn.expand(ctags_file, true), "r", 438))
  local stat = assert(vim.loop.fs_fstat(fd))
  local data = assert(vim.loop.fs_read(fd, stat.size, 0))
  assert(vim.loop.fs_close(fd))

  local results = vim.split(data, '\n')

  pickers.new(opts,{
    prompt = 'Tags',
    finder = finders.new_table {
      results = results,
      entry_maker = opts.entry_maker or make_entry.gen_from_ctags(opts),
    },
    previewer = previewers.ctags.new(opts),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function()
      action_set.select:enhance {
        post = function()
          local selection = action_state.get_selected_entry()

          if selection.scode then
            local scode = string.gsub(selection.scode, '[$]$', '')
            scode = string.gsub(scode, [[\\]], [[\]])
            scode = string.gsub(scode, [[\/]], [[/]])
            scode = string.gsub(scode, '[*]', [[\*]])

            vim.cmd('norm! gg')
            vim.fn.search(scode)
            vim.cmd('norm! zz')
          else
            vim.api.nvim_win_set_cursor(0, {selection.lnum, 0})
          end
        end,
      }
      return true
    end
  }):find()
end

files.current_buffer_tags = function(opts)
  return files.tags(vim.tbl_extend("force", {
    prompt_title = 'Current Buffer Tags',
    only_current_file = true,
    hide_filename = true,
  }, opts))
end

local function apply_checks(mod)
  for k, v in pairs(mod) do
    mod[k] = function(opts)
      opts = opts or {}

      v(opts)
    end
  end

  return mod
end

return apply_checks(files)
