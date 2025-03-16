_G.Months = {}

--stylua: ignore start
Months.items = {
  { name = 'January',   kind = 1 },
  { name = 'February',  kind = 1 },
  { name = 'March',     kind = 2 },
  { name = 'April',     kind = 2 },
  { name = 'May',       kind = 2 },
  { name = 'June',      kind = 3 },
  { name = 'July',      kind = 3 },
  { name = 'August',    kind = 3 },
  { name = 'September', kind = 4 },
  { name = 'October',   kind = 4 },
  { name = 'November',  kind = 4 },
  { name = 'December',  kind = 1 },
}

local markdown_info = {
  -- Should remove all blank lines from the top
  '',
  '  ',
  '# Month #07',
  -- Should collapse multiple blank lines into one
  '',
  ' ',
  '\t',
  -- Should replace section separator with continuous one spanning window width
  '---',
  '',
  -- Should conceal special characters and highlight
  'This *is* __markdown__ text',
  '',
  ' ',
  -- Should conceal code block characters *and* remove all blank lines before
  -- and after code block (as those will be displayed as empty themselves)
  '```lua',
  'local a = 1',
  '```',
  -- Should remove all blank lines from the bottom
  ' ',
  '',
  '\t',
  ' ',
  '',
}

Months.data = {
  January   = { documentation = 'Month #01' },
  February  = { documentation = 'a\nb\nc\nd\ne\nf\ng\nh' },
  March     = { documentation = 'Month #03' },
  April     = { documentation = 'Month #04', detail = '\n  local a = "New info"  \n  \n' },
  May       = { documentation = nil },
  June      = { documentation = 'Month #06' },
  July      = { documentation = table.concat(markdown_info, '\n') },
  August    = { documentation = 'Month #08', detail = 'Month' },
  September = { documentation = nil,         detail = 'Sep' },
  October   = { documentation = 'Month #10' },
  November  = { documentation = 'Month #11' },
  December  = { documentation = string.rep('a ', 1000) },
}
--stylua: ignore end

Months.client = {
  name = 'months-lsp',
  offset_encoding = 'utf-16',
  server_capabilities = {
    completionProvider = { resolveProvider = true, triggerCharacters = { '.' } },
    signatureHelpProvider = { triggerCharacters = { '(', ',' } },
  },
}

local construct_additionTextEdits = function(id, name)
  return {
    {
      newText = ('from months.%s import %s\n'):format(id, name),
      range = {
        start = { line = 0, character = 0 },
        ['end'] = { line = 0, character = 0 },
      },
    },
  }
end

local construct_textEdit = function(name, kind)
  if _G.mock_textEdit == nil then return end
  local new_text, pos = _G.mock_textEdit.new_text, _G.mock_textEdit.pos
  local is_insertreplaceedit = kind == 'InsertReplaceEdit'
  local range = {
    start = { line = pos[1] - 1, character = pos[2] - 1 },
    ['end'] = { line = pos[1] - 1, character = pos[2] },
  }
  return {
    newText = new_text(name),
    [is_insertreplaceedit and 'insert' or 'range'] = range,
    replace = is_insertreplaceedit and range or nil,
  }
end

local construct_filterText = function(name)
  if _G.mock_filterText == nil then return end
  return _G.mock_filterText(name)
end

Months.requests = {
  ['textDocument/completion'] = function(params)
    -- Count actual requests for easier "force completion" tests
    _G.n_textdocument_completion = (_G.n_textdocument_completion or 0) + 1

    params = type(params) == 'function' and params(Months.client, vim.api.nvim_get_current_buf()) or params

    -- Imitate returning nothing in comments
    local line = vim.fn.getline(params.position.line + 1)
    if line:find('^%s*#') ~= nil then return { { result = { items = {} } } } end

    local items = {}
    for i, item in ipairs(Months.items) do
      local res = { label = item.name, kind = item.kind, sortText = ('%03d'):format(i) }
      -- Mock `additionalTextEdits` as in `pyright`
      if vim.tbl_contains({ 'September', 'November' }, item.name) then
        res.additionalTextEdits = construct_additionTextEdits('completion', item.name)
      end

      if item.name == 'April' then
        res.textEdit = construct_textEdit(item.name, 'InsertReplaceEdit')
        res.textEditText = _G.mock_itemdefaults ~= nil and 'New April' or nil
        res.filterText = construct_filterText(item.name)
      end
      if item.name == 'August' then
        res.textEdit = construct_textEdit(item.name, 'textEdit')
        res.textEditText = _G.mock_itemdefaults ~= nil and 'New August' or nil
        res.filterText = construct_filterText(item.name)
      end

      table.insert(items, res)
    end

    -- Mock incomplete computation
    if _G.mock_isincomplete then items = vim.list_slice(items, 1, 6) end

    return { { result = { items = items, isIncomplete = _G.mock_isincomplete, itemDefaults = _G.mock_itemdefaults } } }
  end,

  ['completionItem/resolve'] = function(params)
    local doc = Months.data[params.label].documentation
    if doc ~= nil then params.documentation = { kind = 'markdown', value = doc } end
    params.detail = Months.data[params.label].detail
    -- Mock additionalTextEdits as in `typescript-language-server`
    if vim.tbl_contains({ 'October', 'November' }, params.label) then
      params.additionalTextEdits = construct_additionTextEdits('resolve', params.label)
    end
    return { { result = params } }
  end,

  ['textDocument/signatureHelp'] = function(params)
    params = type(params) == 'function' and params(Months.client, vim.api.nvim_get_current_buf()) or params

    local n_line, n_col = params.position.line, params.position.character
    local line = vim.api.nvim_buf_get_lines(0, n_line, n_line + 1, false)[1]
    line = line:sub(1, n_col)

    local after_open_paren = line:match('%(.*$') or line
    local after_close_paren = line:match('%).*$') or line

    -- Stop showing signature help after closing bracket
    if after_close_paren:len() < after_open_paren:len() then return { {} } end

    -- Compute active parameter id by counting number of ',' from latest '('
    local _, active_param_id = after_open_paren:gsub('%,', '%,')

    -- Compute what is displayed in signature help: text and parameter info
    -- (for highlighting) based on latest function call
    local word = line:match('(%S+%()[^%(]*$')
    local label, parameters
    if word == 'long(' then
      label = string.rep('a ', 1000)
    elseif word == 'string.format(' then
      label = 'function string.format(s:string|number, ...any)'
    elseif word == 'multiline(' then
      label = 'multiline(\narg1,\narg2)'
    elseif word == 'scroll(' then
      label = 'aaa bbb ccc ddd eee fff ggg hhh'
    else
      label = 'abc(param1, param2)'
      parameters = { { label = { 4, 10 } }, { label = { 12, 18 } } }
    end

    -- Construct output
    local signature = {
      activeParameter = active_param_id,
      label = label,
      parameters = parameters,
    }
    return { { result = { signatures = { signature } } } }
  end,
}

-- Replace builtin functions with custom testable ones ========================
local make_request = function(bufnr, method, params, callback)
  local requests = Months.requests[method]
  if requests == nil then return end
  callback(requests(params))
end

vim.lsp.buf_request_all = function(bufnr, method, params, callback)
  if _G.mock_request_delay == nil then return make_request(bufnr, method, params, callback) end
  vim.defer_fn(function() make_request(bufnr, method, params, callback) end, _G.mock_request_delay)
end

local get_lsp_clients = function() return { Months.client } end

if vim.fn.has('nvim-0.10') == 0 then vim.lsp.buf_get_clients = get_lsp_clients end
if vim.fn.has('nvim-0.10') == 1 then vim.lsp.get_clients = get_lsp_clients end

vim.lsp.get_client_by_id = function(client_id) return get_lsp_clients()[client_id] end
