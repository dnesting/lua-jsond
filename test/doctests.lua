-- This tests the code snippets in a file.
-- The file is expected to contain code snippets in the following format:
--
-- ```lua
-- buf = ByteArray.new('{"key": "value"}', true):tvb()()
-- obj = jsond.decode(buf)
-- print(obj.key)
-- print(obj.missing)
-- -- value
-- -- nil
-- ```
--
-- The package provides routines to read the file, extract code blocks, execute the
-- blocks, and compare the output to the expected output.

local diff = require("test/diff")

local docrunner = {}

local function get_blocks_from_lines(next_line, filename, start_line_num)
    local line = next_line()
    local num = 0
    local blocks = {}
    local output_lines = {}
    local code_lines = {}
    local block_start
    local last_heading
    if not filename then
        filename = "(string)"
    end
    if start_line_num then
        num = start_line_num - 1
    end
    while line do
        num = num + 1
        if block_start then
            if line:sub(1, 3) == "-- " then
                line = line:sub(4)
                table.insert(output_lines, line)
            elseif line:sub(1, 3) == "```" then
                -- block end
                if #output_lines > 0 then
                    local block = {
                        filename = filename,
                        heading = last_heading,
                        first_line = block_start + 1,
                        code_lines = code_lines,
                        expected_lines = output_lines
                    }
                    table.insert(blocks, block)
                end
                block_start = nil
                output_lines = {}
                code_lines = {}
            else
                -- we only want the comments at the end of the block
                output_lines = {}
                table.insert(code_lines, line)
            end
        elseif line:sub(1, 6) == "```lua" then
            block_start = num
        elseif line:sub(1, 1) == '#' then
            line = line:gsub("^#+%s*", "")
            line = line:gsub("^`", ""):gsub("`$", "")
            last_heading = line
        end
        line = next_line()
    end
    if block_start then
        error("Unmatched block start for block starting at " .. filename .. ":" .. block_start)
    end
    if #blocks == 0 then
        return nil
    end
    return blocks
end


local default_sandbox = {
    require = function(name)
        error("Module not found: " .. name)
    end
}

local function sandbox_or_default(sandbox)
    if not sandbox then
        sandbox = {}
        for k, v in pairs(default_sandbox) do
            sandbox[k] = v
        end
    end
    return sandbox
end

local function fixup_error(err, filename, first_line)
    err = tostring(err)
    local line = err:match("%(load%):(%d+)")
    if line then
        local line_num = tonumber(line)
        if line_num then
            local new_line = first_line + line_num - 1
            err = err:gsub("%(load%):%d+", filename .. ":" .. new_line)
        end
    end
    return err
end

local function iter_lines(lines)
    local i = 0
    return function()
        i = i + 1
        if lines[i] then
            return lines[i] .. "\n"
        end
        return nil
    end
end

local function run_code(block, sandbox)
    local output = {}
    sandbox = sandbox_or_default(sandbox)
    sandbox.print = function(...)
        local args = {}
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            args[i] = tostring(v)
        end
        table.insert(output, table.concat(args, " "))
    end
    local func, err = load(iter_lines(block.code_lines), nil, nil, sandbox)
    if func then
        local status
        status, err = pcall(func)
        if status then
            return output
        end
    end
    if err then
        err = fixup_error(err, block.filename, block.first_line)
        return nil, err
    end
    return output
end

local function run_and_verify(block, sandbox)
    local actual, err = run_code(block, sandbox)
    if not actual then
        return false, nil, err
    end
    local diff = diff(block.expected_lines, actual)
    if diff then
        return false, diff
    end
    return true
end

local function print_code(block, prefix)
    for i, line in ipairs(block.code_lines) do
        print(string.format("%s%d: %s", prefix, i + block.first_line - 1, line))
    end
end

local function run_blocks(blocks, sandbox, verbose)
    local all_passed = true
    for _, block in ipairs(blocks) do
        local context = block.filename .. ":" .. block.first_line
        if block.heading then
            context = context .. " (" .. block.heading .. ")"
        end
        io.write("Running example " .. context .. ": ")
        if verbose then
            print()
            print()
            print_code(block, "  | ")
            print()
            for _, line in ipairs(block.expected_lines) do
                print("  " .. line)
            end
            print()
        end
        local ok, diff, err = run_and_verify(block, sandbox)
        if ok then
            print("PASS")
        else
            print("FAIL")
            print()
            print("  " .. (err or "Output does not match:"))
            print()

            if not verbose then
                print_code(block, "  | ")
                print()
            end

            all_passed = false
            if diff then
                for _, line in ipairs(diff) do
                    print("  " .. line)
                end
                print()
            end
        end
        if verbose then
            print()
        end
    end
    if all_passed then
        print("PASS")
    else
        print("FAIL")
    end
    return all_passed
end

local function splitlines(str)
    -- returns an iterator over lines, including blank lines
    return function()
        if str == "" then
            return nil
        end
        local line
        line, str = str:match("([^\n]*)\n?(.*)")
        return line
    end
end

function docrunner.run_string(code, sandbox, filename, line_num)
    code = "```lua\n" .. code .. "\n```"
    local blocks = get_blocks_from_lines(splitlines(code), filename, line_num)
    if not blocks then
        error("No code blocks found in string")
    end
    return run_blocks(blocks, sandbox, docrunner.verbose)
end

function docrunner.run_from_file(filename, sandbox)
    local blocks = get_blocks_from_lines(io.lines(filename), filename)
    if not blocks then
        print("No code blocks found in " .. filename)
        return nil
    end
    return run_blocks(blocks, sandbox, docrunner.verbose)
end

docrunner.verbose = false

return docrunner
