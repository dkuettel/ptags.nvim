local M = {}

-- NOTE align with strings of length 5
local kinds = {
    ["function"] = " func",
    ["variable"] = "  var",
    ["class"] = "class",
    ["type alias"] = " type",
}

local function entry_maker(raw_line)
    local name, line_str, kind, file = string.match(raw_line, "^(.*)%z(.*)%z(.*)%z(.*)$")
    local line = tonumber(line_str)
    kind = kinds[kind]
    if not kind then
        kind = "  ???"
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
---@param opts? table Additional options for telescope.
---@param ptags? string The ptags executable to use, defaults to "ptags" anywhere in your $PATH.
function M.telescope(sources, opts, ptags)
    if sources == nil or #sources == 0 then
        error("Sources needs to have at least one element.")
    end

    opts = opts or {}
    ptags = ptags or "ptags"
    local cmd = { ptags, "--format=telescope", unpack(sources) }

    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values

    local picker = pickers.new(opts, {
        prompt_title = "ptags",
        finder = finders.new_oneshot_job(cmd, {
            entry_maker = entry_maker,
        }),
        sorter = conf.generic_sorter(opts),
        previewer = conf.grep_previewer(opts),
    })
    picker:find()
end

---run ptags on sources and show in picker (from snacks)
---@param title string
---@param sources string[] Cannot be empty or nil.
function M.picker(title, sources)
    if sources == nil or #sources == 0 then
        error("Sources needs to have at least one element.")
    end

    local function picker_finder(_opts, ctx)
        return require("snacks.picker.source.proc").proc(
            ctx:opts {
                cmd = "ptags",
                args = { "--format=picker", unpack(sources) },
                transform = function(item)
                    local j = vim.json.decode(item.text)
                    return {
                        text = j["name"],
                        kind = j["kind"],
                        file = j["file"],
                        pos = { j["line"], 0 },
                    }
                end,
            },
            ctx
        )
    end

    Snacks.picker {
        title = title,
        finder = picker_finder,
        preview = "file",
        format = function(item, _picker)
            return {
                { kinds[item.kind], "Comment", virtual = true },
                { ":  ", "Comment", virtual = true },
                { item.text },
            }
        end,
    }
end

return M
