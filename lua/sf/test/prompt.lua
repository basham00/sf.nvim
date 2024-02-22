-- local pickers = require 'telescope.pickers'
-- local finders = require 'telescope.finders'
-- local conf = require('telescope.config').values
local actions = require 'telescope.actions'
local action_state = require 'telescope.actions.state'

local S = require('sf')
local U = require('sf.util')
local T = require('sf.term')
local TS = require('sf.ts')
local H = {}
local api = vim.api
local buftype = 'nowrite'
local filetype = 'sf_test_prompt'

local P = {}

P.buf = nil
P.win = nil
P.class = nil
P.tests = nil
P.test_num = nil
P.selected_tests = {}

P.open = function()
  local class = TS.get_test_class_name()
  if class == nil then
    return vim.notify('not in Apex test file', vim.log.levels.ERROR)
  end

  local test_names = TS.get_test_method_names_in_curr_file()
  if next(test_names) == nil then
    return vim.notify('no Apex test found', vim.log.levels.ERROR)
  end

  local tests = {}
  local test_num = 0
  for _, name in ipairs(test_names) do
    table.insert(tests, name)
    test_num = test_num + 1
  end

  P.class = class
  P.tests = tests
  P.test_num = test_num

  local buf = P.use_existing_or_create_buf()
  local win = P.use_existing_or_create_win()
  P.buf = buf
  P.win = win

  api.nvim_win_set_buf(win, buf)

  P.set_keys()

  vim.bo[buf].modifiable = true
  P.display()
  vim.bo[buf].modifiable = false
end

P.set_keys = function()
  vim.keymap.set('n', 'x', function()
    P.toggle()
  end, { buffer = true, noremap = true })

  vim.keymap.set('n', 'tt', function()
    P.open_tests_in_selected()
  end, { buffer = true, noremap = true })

  vim.keymap.set('n', 'cc', function()
    local cmd = P.build_tests_cmd(U.cmd_params) .. ' -o ' .. S.get()
    P.close()
    T.run(cmd)
    S.last_tests = cmd
    P.selected_tests = {}
  end, { buffer = true, noremap = true })

  vim.keymap.set('n', 'cC', function()
    local cmd = P.build_tests_cmd(U.cmd_coverage_params) .. ' -o ' .. S.get()
    P.close()
    T.run(cmd)
    S.last_tests = cmd
    P.selected_tests = {}
  end, { buffer = true, noremap = true })
end

P.display = function()
  api.nvim_set_current_win(P.win)
  local names = {}
  table.insert(names,
    '** "x": toggle tests; "tt": change a test file; "cc": run tests; "cC": run tests with code coverage.')

  for _, test in ipairs(P.tests) do
    local class_test = string.format('%s.%s', P.class, test)
    if vim.tbl_contains(P.selected_tests, class_test) then
      table.insert(names, '[x] ' .. test)
    else
      table.insert(names, '[ ] ' .. test)
    end
  end
  api.nvim_buf_set_lines(P.buf, 0, 100, false, names)
end

P.use_existing_or_create_buf = function()
  if P.buf and api.nvim_buf_is_loaded(P.buf) then
    return P.buf
  end

  local buf = api.nvim_create_buf(false, false)
  vim.bo[buf].buftype = buftype
  vim.bo[buf].filetype = filetype

  return buf
end

P.use_existing_or_create_win = function()
  if P.win and api.nvim_win_is_valid(P.win) then
    api.nvim_set_current_win(P.win)
    return P.win
  end

  local split_win_rows = P.test_num + 2
  api.nvim_command(split_win_rows .. 'split')

  return api.nvim_get_current_win()
end

P.toggle = function()
  if vim.bo[0].filetype ~= filetype then
    return vim.notify('file-type must be: ' .. filetype, vim.log.levels.ERROR)
  end

  vim.bo[0].modifiable = true

  local r, _ = unpack(vim.api.nvim_win_get_cursor(0))
  if r == 1 then -- 1st row is title
    return
  end

  local row_index = r - 1

  local curr_value = api.nvim_buf_get_text(0, row_index, 1, row_index, 2, {})

  local name = P.tests[row_index]
  local class_test = string.format('%s.%s', P.class, name)
  local index = U.list_find(P.selected_tests, class_test)

  if curr_value[1] == 'x' then
    if index ~= nil then
      table.remove(P.selected_tests, index)
    end
    api.nvim_buf_set_text(0, row_index, 1, row_index, 2, { ' ' })
  elseif curr_value[1] == ' ' then
    if index == nil then
      table.insert(P.selected_tests, class_test)
    end
    api.nvim_buf_set_text(0, row_index, 1, row_index, 2, { 'x' })
  end

  print(vim.inspect(P.selected_tests))

  vim.bo[0].modifiable = false
end

P.build_tests_cmd = function(param_str)
  if next(P.selected_tests) == nil then
    return vim.notify('no selected test.', vim.log.levels.ERROR)
  end

  local t = ''
  for _, test in ipairs(P.selected_tests) do
    t = string.format('%s -t %s', t, test)
  end

  local cmd = string.format('sf apex run test%s %s', t, param_str)
  return cmd
end

P.close = function()
  if P.win and api.nvim_win_is_valid(P.win) then
    api.nvim_win_close(P.win, false)
  end
end

P.open_tests_in_selected = function()
  local opts = {
    attach_mappings = P.tele_pick_test_file,
    prompt_title = 'Select Test File',
    search_file = '*.cls', -- TODO: how to get rid of xml in the list?
  }
  require('telescope.builtin').find_files(opts)
end

P.tele_pick_test_file = function(prompt_bufnr, map)
  actions.select_default:replace(function()
    actions.close(prompt_bufnr)
    local path = action_state.get_selected_entry().path
    P.open_selected(path)
  end)
  return true
end

P.open_selected = function(abs_file_name)
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd('edit ' .. abs_file_name)
    P.open()
  end)
end

return P
