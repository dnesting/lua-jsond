-- Compute Longest Common Subsequence table
local function build_lcs(a, b)
    local n, m = #a, #b
    local dp = {}
    for i = 0, n do
        dp[i] = {}
        for j = 0, m do
            dp[i][j] = 0
        end
    end
    for i = 1, n do
        for j = 1, m do
            if a[i] == b[j] then
                dp[i][j] = dp[i - 1][j - 1] + 1
            else
                dp[i][j] = (dp[i - 1][j] >= dp[i][j - 1]) and dp[i - 1][j] or dp[i][j - 1]
            end
        end
    end
    return dp
end

-- Backtrack through the LCS table to get a sequence of ops
local function backtrack(dp, a, b)
    local ops = {}
    local i, j = #a, #b
    while i > 0 or j > 0 do
        if i > 0 and j > 0 and a[i] == b[j] then
            table.insert(ops, 1, { type = "=", a_line = i, b_line = j })
            i, j = i - 1, j - 1
        elseif j > 0 and (i == 0 or dp[i][j - 1] >= dp[i - 1][j]) then
            table.insert(ops, 1, { type = "+", a_line = nil, b_line = j })
            j = j - 1
        else
            table.insert(ops, 1, { type = "-", a_line = i, b_line = nil })
            i = i - 1
        end
    end
    return ops
end

-- Group the flat list of ops into “hunks” with the given context
local function collect_hunks(ops, context)
    local hunks = {}
    local n = #ops
    local i = 1
    while i <= n do
        if ops[i].type ~= "=" then
            local hstart = math.max(1, i - context)
            local last_change = i
            local j = i + 1
            while j <= n and j <= last_change + context do
                if ops[j].type ~= "=" then last_change = j end
                j = j + 1
            end
            local hend = math.min(n, last_change + context)
            table.insert(hunks, { start = hstart, stop = hend })
            i = hend + 1
        else
            i = i + 1
        end
    end
    return hunks
end

-- Format a single hunk into unified diff lines
local function format_hunk(ops, hunk, a, b)
    -- determine hunk header ranges
    local a_start, a_count = nil, 0
    local b_start, b_count = nil, 0
    for idx = hunk.start, hunk.stop do
        local op = ops[idx]
        if op.a_line then
            a_start = a_start or op.a_line
            a_count = a_count + 1
        end
        if op.b_line then
            b_start = b_start or op.b_line
            b_count = b_count + 1
        end
    end
    -- fall back if all insertions or deletions
    a_start = a_start or ((ops[hunk.start].a_line or (ops[hunk.start + 1] and ops[hunk.start + 1].a_line)) or 1)
    b_start = b_start or ((ops[hunk.start].b_line or (ops[hunk.start + 1] and ops[hunk.start + 1].b_line)) or 1)

    --local header = string.format("@@ -%d,%d +%d,%d @@", a_start, a_count, b_start, b_count)
    --local lines = { header }
    local lines = {}
    for idx = hunk.start, hunk.stop do
        local op = ops[idx]
        if op.type == "=" then
            table.insert(lines, " " .. a[op.a_line])
        elseif op.type == "-" then
            table.insert(lines, "-" .. a[op.a_line])
        elseif op.type == "+" then
            table.insert(lines, "+" .. b[op.b_line])
        end
    end
    return lines
end

-- Public diff function: returns a table of unified-diff lines
local function diff(a, b)
    local context = 1 -- one line of context
    local dp      = build_lcs(a, b)
    local ops     = backtrack(dp, a, b)
    local hunks   = collect_hunks(ops, context)

    local result  = {}
    for _, h in ipairs(hunks) do
        for _, line in ipairs(format_hunk(ops, h, a, b)) do
            table.insert(result, line)
        end
    end
    if #result == 0 then
        return nil
    end
    return result
end

return diff
