local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values

local ptags_path = vim.fn.resolve(vim.fs.dirname(debug.getinfo(1).source:sub(2)) .. "/../bin/ptags")
local kinds = { ["function"] = " func", ["variable"] = "  var", ["class"] = "class" }

local function entry_maker(raw_line)
    local name, line, kind, file = string.match(raw_line, "^(.*)%z(.*)%z(.*)%z(.*)$")
    line = tonumber(line)
    kind = kinds[kind]
    if not kind then
        kind = "???"
    end
    local display = kind .. ": " .. name
    return {
        value = { name = name, line = line, kind = kind, file = file },
        display = display,
        ordinal = display,
        path = file,
        lnum = line,
        col = 0,
    }
end

---run ptags on sources and show in telescope
---@param sources string[] Cannot be empty or nil.
---@param opts table Additional options for telescope.
local function telescope(sources, opts)
    if sources == nil or #sources == 0 then
        error("Sources needs to have at least one element.")
    end
    opts = opts or {}
    local cmd = { ptags_path, "--format=telescope", unpack(sources) }
    pickers.new(opts, {
        prompt_title = "ptags",
        finder = finders.new_oneshot_job(cmd, {
            entry_maker = entry_maker,
        }),
        sorter = conf.generic_sorter(opts),
        previewer = conf.grep_previewer(opts),
    }):find()
end

return { telescope = telescope }
