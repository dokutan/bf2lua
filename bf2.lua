#!/usr/bin/env lua

--- Brainfuck to Lua transpiler

local help_message = [[
bf2.lua - convert Brainfuck to Lua

Convert:
bf2.lua -i input.bf -o output.lua

Convert and run:
bf2.lua -i input.bf

Options:
-h --help         print this message
-i --input FILE   input file, - for stdin
-o --output FILE  output file, - for stdout
-f --functions    create a function for each loop
                  this improves compatibility with luajit and lua<5.4
]]

local output_header = [[
#!/usr/bin/env lua
data = {}
ptr = 1
max = 256

setmetatable(data, {__index = function() return 0 end})

]]

local function is_in(key, set)
    for _, v in ipairs(set) do
        if key == v then
            return true
        end
    end
    return false
end

--- Read brainfuck code from file.
--- @tparam file file
--- @treturn string
local read_brainfuck = function(file)
    local program = {}

    repeat
        local command = file:read(1)

        if command ~= nil and string.match(command, "[<>%+%-%.,%[%]]") ~= nil then
            program[#program + 1] = command
        end
    until command == nil -- EOF

    return table.concat(program, "")
end

--- Removes useless sequences of commands from a brainfuck program.
--- Adds the '0' command to set a cell to zero.
--- @tparam string program
--- @treturn string
local function optimize_brainfuck(program)
    -- remove all characters that are not brainfuck commands
    program = string.gsub(program, "[^><%+%-.,%]%[]", "")

    local substitutions = {
        -- these pairs of commands have no effect
        ["<>"] = "",
        ["><"] = "",
        ["%+%-"] = "",
        ["%-%+"] = "",

        -- these loops set the current cell to zero
        ["%[%-%]"] = "0",
        ["%[%+%]"] = "0",
        ["00"] = "0",

        -- the current cell is guaranteed to be zero after a loop
        ["%]0"] = "]"
    }
    local sum = 0

    repeat
        sum = 0
        for i, v in pairs(substitutions) do
            program, s = string.gsub(program, i, v)
            sum = sum + s
        end
    until sum == 0

    return program
end

--- Counts the number of unmatched loop commands, should return 0 for a valid program.
--- @tparam string program
--- @treturn int
local function count_brainfuck_loops(program)
    local loops = 0

    for i = 1, #program do
        if string.sub(program, i, i) == "[" then
            loops = loops + 1
        elseif string.sub(program, i, i) == "]" then
            loops = loops - 1
        end
    end

    return loops
end

--- Converts Brainfuck code to an intermediate representation.
--- @tparam string program
--- @treturn table
--- ---
--- @todo describe ir format
local convert_brainfuck = function(program)
    local loops = 0
    local counter = 1          -- used to count and join repeating commands
    local skipped_zero = false -- indicates if zeroing a cell has been omitted from the output
    local ir = {}

    for i = 1, #program do
        if string.sub(program, i, i) == "[" then
            -- output_write("while (data[ptr] or 0) ~= 0 do\n")
            ir[#ir + 1] = { "[", loops }
            loops = loops + 1
        elseif string.sub(program, i, i) == "]" then
            loops = loops - 1
            ir[#ir + 1] = { "]", loops }
        elseif string.sub(program, i, i) == "," then
            ir[#ir + 1] = { ",", loops, nil, 0 }
        elseif string.sub(program, i, i) == "." then
            ir[#ir + 1] = { ".", loops, nil, 0 }
        elseif string.sub(program, i, i) == "+" then
            if string.sub(program, i + 1, i + 1) == "+" then
                counter = counter + 1
            elseif skipped_zero then
                ir[#ir + 1] = { "=", loops, counter, 0 }
                counter = 1
                skipped_zero = false
            else
                ir[#ir + 1] = { "+", loops, counter, 0 }
                counter = 1
            end
        elseif string.sub(program, i, i) == "-" then
            if string.sub(program, i + 1, i + 1) == "-" then
                counter = counter + 1
            elseif skipped_zero then
                ir[#ir + 1] = { "=", loops, -counter, 0 }
                counter = 1
                skipped_zero = false
            else
                ir[#ir + 1] = { "-", loops, counter, 0 }
                counter = 1
            end
        elseif string.sub(program, i, i) == "<" then
            if string.sub(program, i + 1, i + 1) == "<" then
                counter = counter + 1
            else
                ir[#ir + 1] = { "<", loops, counter }
                counter = 1
            end
        elseif string.sub(program, i, i) == ">" then
            if string.sub(program, i + 1, i + 1) == ">" then
                counter = counter + 1
            else
                ir[#ir + 1] = { ">", loops, counter }
                counter = 1
            end
        elseif string.sub(program, i, i) == "0" then
            if string.sub(program, i + 1, i + 1) == "+" or
                string.sub(program, i + 1, i + 1) == "-" then
                -- setting this cell to zero can be skipped, because the value will be set with the next instruction
                skipped_zero = true
            else
                ir[#ir + 1] = { "=", loops, 0, 0 }
            end
        end

        if loops < 0 then break end
    end

    return ir
end

--- Optimize the intermediate representation.
--- @tparam table ir
--- @treturn table
local optimize_ir = function(ir)
    local optimized_ir = {}

    local i = 1
    while i <= #ir - 2 do
        if -- >?< → ?< or ?>
            ir[i][1] == ">" and
            is_in(ir[i + 1][1], { "+", "-", "=", ".", "," }) and
            ir[i + 2][1] == "<"
        then
            if ir[i][3] == ir[i + 2][3] then
                optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] + ir[i][3] }
            elseif ir[i][3] > ir[i + 2][3] then
                optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] + ir[i][3] }
                optimized_ir[#optimized_ir + 1] = { ">", ir[i][2], ir[i][3] - ir[i + 2][3] }
            elseif ir[i][3] < ir[i + 2][3] then
                optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] + ir[i][3] }
                optimized_ir[#optimized_ir + 1] = { "<", ir[i][2], ir[i + 2][3] - ir[i][3] }
            end
            i = i + 3
        elseif -- <?> → ?< or ?>
            ir[i][1] == "<" and
            is_in(ir[i + 1][1], { "+", "-", "=", ".", "," }) and
            ir[i + 2][1] == ">"
        then
            if ir[i][3] == ir[i + 2][3] then
                optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] - ir[i][3] }
            elseif ir[i][3] > ir[i + 2][3] then
                optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] - ir[i][3] }
                optimized_ir[#optimized_ir + 1] = { "<", ir[i][2], ir[i][3] - ir[i + 2][3] }
            elseif ir[i][3] < ir[i + 2][3] then
                optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] - ir[i][3] }
                optimized_ir[#optimized_ir + 1] = { ">", ir[i][2], ir[i + 2][3] - ir[i][3] }
            end
            i = i + 3
        elseif -- <?< → ?<
            ir[i][1] == "<" and
            is_in(ir[i + 1][1], { "+", "-", "=", ".", "," }) and
            ir[i + 2][1] == "<"
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] - ir[i][3] }
            optimized_ir[#optimized_ir + 1] = { "<", ir[i][2], ir[i][3] + ir[i + 2][3] }
            i = i + 3
        elseif -- >?> → ?>
            ir[i][1] == ">" and
            is_in(ir[i + 1][1], { "+", "-", "=", ".", "," }) and
            ir[i + 2][1] == ">"
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] + ir[i][3] }
            optimized_ir[#optimized_ir + 1] = { ">", ir[i][2], ir[i][3] + ir[i + 2][3] }
            i = i + 3
        elseif -- swap > with "+", "-", "=", ".", ","
            ir[i][1] == ">" and
            is_in(ir[i + 1][1], { "+", "-", "=", ".", "," })
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] + ir[i][3] }
            optimized_ir[#optimized_ir + 1] = { ">", ir[i][2], ir[i][3] }
            i = i + 2
        elseif -- swap < with "+", "-", "=", ".", ","
            ir[i][1] == "<" and
            is_in(ir[i + 1][1], { "+", "-", "=", ".", "," })
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] - ir[i][3] }
            optimized_ir[#optimized_ir + 1] = { "<", ir[i][2], ir[i][3] }
            i = i + 2
        elseif -- swap > with add-to
            ir[i][1] == ">" and
            ir[i + 1][1] == "add-to"
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] + ir[i][3],
                ir[i + 1][5] + ir[i][3] }
            optimized_ir[#optimized_ir + 1] = { ">", ir[i][2], ir[i][3] }
            i = i + 2
        elseif -- swap < with add-to
            ir[i][1] == "<" and
            ir[i + 1][1] == "add-to"
        then
            optimized_ir[#optimized_ir + 1] = { "add-to", ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] - ir[i][3],
                ir[i + 1][5] - ir[i][3] }
            optimized_ir[#optimized_ir + 1] = { "<", ir[i][2], ir[i][3] }
            i = i + 2
        elseif -- addition → "add-to"
            ir[i][1] == "[" and
            ir[i + 1][1] == "+" and
            ir[i + 2][1] == "-" and
            ir[i + 3][1] == "]" and
            ir[i + 1][3] == 1 and -- increment by one
            ir[i + 2][3] == 1 and -- decrement by one
            ir[i + 2][4] == 0     -- current cell is decremented
        then
            optimized_ir[#optimized_ir + 1] = { "add-to", ir[i][2], "+", ir[i + 1][4], 0 }
            optimized_ir[#optimized_ir + 1] = { "=", ir[i][2], 0, 0 }
            i = i + 4
        elseif -- addition to two cells → "add-to"
            ir[i][1] == "[" and
            ir[i + 1][1] == "+" and
            ir[i + 2][1] == "+" and
            ir[i + 3][1] == "-" and
            ir[i + 4][1] == "]" and
            ir[i + 1][3] == 1 and -- increment by one
            ir[i + 2][3] == 1 and -- increment by one
            ir[i + 3][3] == 1 and -- decrement by one
            ir[i + 3][4] == 0     -- current cell is decremented
        then
            optimized_ir[#optimized_ir + 1] = { "add-to", ir[i][2], "+", ir[i + 1][4], 0 }
            optimized_ir[#optimized_ir + 1] = { "add-to", ir[i][2], "+", ir[i + 2][4], 0 }
            optimized_ir[#optimized_ir + 1] = { "=", ir[i][2], 0, 0 }
            i = i + 5
        elseif -- subtraction → "add-to"
            ir[i][1] == "[" and
            ir[i + 1][1] == "-" and
            ir[i + 2][1] == "-" and
            ir[i + 3][1] == "]" and
            ir[i + 1][3] == 1 and -- decrement by one
            ir[i + 2][3] == 1 and -- decrement by one
            ir[i + 2][4] == 0     -- current cell is decremented
        then
            optimized_ir[#optimized_ir + 1] = { "add-to", ir[i][2], "-", ir[i + 1][4], 0 }
            optimized_ir[#optimized_ir + 1] = { "=", ir[i][2], 0, 0 }
            i = i + 4
        elseif -- = and add-to → move-to
            ir[i][1] == "=" and
            ir[i + 1][1] == "add-to" and
            ir[i][4] == ir[i + 1][4] -- both commands act on the same cell
        then
            optimized_ir[#optimized_ir + 1] = { "move-to", ir[i][2], ir[i][3], ir[i + 1][4], ir[i + 1][5] }
            i = i + 2
        elseif -- = and move-to → = and =
            ir[i][1] == "=" and
            ir[i + 1][1] == "move-to" and
            ir[i][4] == ir[i + 1][5] -- both commands act on the same cell
        then
            optimized_ir[#optimized_ir + 1] = { "=", ir[i][2], ir[i][3] + ir[i + 1][3], ir[i + 1][4] }
            optimized_ir[#optimized_ir + 1] = { "=", ir[i][2], 0, ir[i][4] }
            i = i + 2
        elseif -- + is useless after =
            ir[i][1] == "=" and
            ir[i + 1][1] == "+" and
            ir[i][4] == ir[i + 1][4] -- both commands act on the same cell
        then
            optimized_ir[#optimized_ir + 1] = { "=", ir[i + 1][2], ir[i][3] + ir[i + 1][3], ir[i + 1][4] }
            i = i + 2
        elseif -- - is useless after =
            ir[i][1] == "=" and
            ir[i + 1][1] == "-" and
            ir[i][4] == ir[i + 1][4] -- both commands act on the same cell
        then
            optimized_ir[#optimized_ir + 1] = { "=", ir[i + 1][2], ir[i][3] - ir[i + 1][3], ir[i + 1][4] }
            i = i + 2
        elseif -- = is useless before =
            ir[i][1] == "=" and
            ir[i + 1][1] == "=" and
            ir[i][4] == ir[i + 1][4]
        then
            optimized_ir[#optimized_ir + 1] = { "=", ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] }
            i = i + 2
        elseif -- sort +, -, =
            is_in(ir[i][1], { "+", "-", "=" }) and
            is_in(ir[i + 1][1], { "+", "-", "=" }) and
            ir[i][4] > ir[i + 1][4]
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] }
            optimized_ir[#optimized_ir + 1] = { ir[i][1], ir[i][2], ir[i][3], ir[i][4] }
            i = i + 2
        elseif -- +, -, = are useless before ,
            is_in(ir[i][1], { "+", "-", "=" }) and
            ir[i + 1][1] == "," and
            ir[i][4] == ir[i + 1][4]
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], (ir[i + 1][3] or 0) + ir[i][3], ir[i + 1][4] }
            i = i + 2
        elseif -- combine - and -
            ir[i][1] == "-" and
            ir[i + 1][1] == "-" and
            ir[i][4] == ir[i + 1][4]
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3] + ir[i][3], ir[i + 1][4] }
            i = i + 2
        elseif -- combine + and +
            ir[i][1] == "+" and
            ir[i + 1][1] == "+"
            and ir[i][4] == ir[i + 1][4]
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3] + ir[i][3], ir[i + 1][4] }
            i = i + 2
        elseif -- combine + and -
            ir[i][1] == "+" and
            ir[i + 1][1] == "-" and
            ir[i][4] == ir[i + 1][4]
        then
            if ir[i][3] > ir[i + 1][3] then
                optimized_ir[#optimized_ir + 1] = { "+", ir[i][2], ir[i][3] - ir[i + 1][3], ir[i][4] }
            elseif ir[i][3] < ir[i + 1][3] then
                optimized_ir[#optimized_ir + 1] = { "-", ir[i][2], ir[i + 1][3] - ir[i][3], ir[i][4] }
            end
            i = i + 2
        elseif -- combine - and +
            ir[i][1] == "-" and
            ir[i + 1][1] == "+" and
            ir[i][4] == ir[i + 1][4]
        then
            if ir[i][3] > ir[i + 1][3] then
                optimized_ir[#optimized_ir + 1] = { "-", ir[i][2], ir[i][3] - ir[i + 1][3], ir[i][4] }
            elseif ir[i][3] < ir[i + 1][3] then
                optimized_ir[#optimized_ir + 1] = { "+", ir[i][2], ir[i + 1][3] - ir[i][3], ir[i][4] }
            end
            i = i + 2
        elseif -- combine < and <
            ir[i][1] == "<" and
            ir[i + 1][1] == "<" and
            ir[i][4] == ir[i + 1][4]
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3] + ir[i][3], ir[i + 1][4] }
            i = i + 2
        elseif -- combine > and >
            ir[i][1] == ">" and
            ir[i + 1][1] == ">" and
            ir[i][4] == ir[i + 1][4]
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3] + ir[i][3], ir[i + 1][4] }
            i = i + 2
        elseif -- combine > and <
            ir[i][1] == ">" and
            ir[i + 1][1] == "<" and
            ir[i][4] == ir[i + 1][4]
        then
            if ir[i][3] > ir[i + 1][3] then
                optimized_ir[#optimized_ir + 1] = { ">", ir[i][2], ir[i][3] - ir[i + 1][3], ir[i][4] }
            elseif ir[i][3] < ir[i + 1][3] then
                optimized_ir[#optimized_ir + 1] = { "<", ir[i][2], ir[i + 1][3] - ir[i][3], ir[i][4] }
            end
            i = i + 2
        elseif -- combine < and >
            ir[i][1] == "<" and
            ir[i + 1][1] == ">" and
            ir[i][4] == ir[i + 1][4]
        then
            if ir[i][3] > ir[i + 1][3] then
                optimized_ir[#optimized_ir + 1] = { "<", ir[i][2], ir[i][3] - ir[i + 1][3], ir[i][4] }
            elseif ir[i][3] < ir[i + 1][3] then
                optimized_ir[#optimized_ir + 1] = { ">", ir[i][2], ir[i + 1][3] - ir[i][3], ir[i][4] }
            end
            i = i + 2
        elseif -- + or - is useless before =
            (ir[i][1] == "+" or ir[i][1] == "-") and
            ir[i + 1][1] == "="
            and ir[i][4] == ir[i + 1][4]
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] }
            i = i + 2
        elseif -- make joining writes easier ? @todo
            ir[i][1] == "+" and
            ir[i + 1][1] == "." and
            ir[i][4] ~= ir[i + 1][4]
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] }
            optimized_ir[#optimized_ir + 1] = { ir[i][1], ir[i][2], ir[i][3], ir[i][4] }
            i = i + 2
        elseif -- make joining writes easier ? @todo
            ir[i][1] == "-" and
            ir[i + 1][1] == "." and
            ir[i][4] ~= ir[i + 1][4]
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] }
            optimized_ir[#optimized_ir + 1] = { ir[i][1], ir[i][2], ir[i][3], ir[i][4] }
            i = i + 2
        else -- no optimisation applicable
            optimized_ir[#optimized_ir + 1] = ir[i]
            i = i + 1
        end
    end

    while i <= #ir do
        optimized_ir[#optimized_ir + 1] = ir[i]
        i = i + 1
    end

    return optimized_ir
end

--- Converts the intermediate representation to Lua code.
--- @tparam table ir
--- @tparam file output
--- @tparam boolean functions
local convert_ir = function(ir, output, functions)
    local ptr_offset = function(offset)
        if offset == 0 then
            return ""
        elseif offset > 0 then
            return " + " .. offset
        else
            return " - " .. -offset
        end
    end
    local function_counter = 1
    local function_names = {}

    output:write(output_header)

    for i = 1, #ir do
        local command = ir[i][1]
        local loops = ir[i][2]

        local output_write = function(str)
            output:write(string.rep("\t", loops) .. str)
        end

        if command == "[" then
            output_write("while data[ptr] ~= 0 do\n")
            if functions then
                output_write("function loop" .. function_counter .. "()\n")
                function_names[loops] = function_counter
                function_counter = function_counter + 1
            end
        elseif command == "]" then
            output_write("end\n")
            if functions then
                output_write("loop" .. function_names[loops] .. "()\n")
                output_write("end\n")
            end
        elseif command == "," then
            output_write("data[ptr" .. ptr_offset(ir[i][4]) .. "] = string.byte(io.read(1))\n")
        elseif command == "." then
            output_write(
                "io.write(string.char((data[ptr" .. ptr_offset(ir[i][4]) .. "]" ..
                ptr_offset(ir[i][3] or 0) .. ") % max))\n"
            )
        elseif command == "+" then
            output_write(
                "data[ptr" .. ptr_offset(ir[i][4]) ..
                "] = (data[ptr" .. ptr_offset(ir[i][4]) .. "] + " .. ir[i][3] .. ") % max\n"
            )
        elseif command == "-" then
            output_write(
                "data[ptr" .. ptr_offset(ir[i][4]) ..
                "] = (data[ptr" .. ptr_offset(ir[i][4]) .. "] - " .. ir[i][3] .. ") % max\n"
            )
        elseif command == "<" then
            output_write("ptr = ptr - " .. ir[i][3] .. "\n")
        elseif command == ">" then
            output_write("ptr = ptr + " .. ir[i][3] .. "\n")
        elseif command == "=" then
            output_write("data[ptr" .. ptr_offset(ir[i][4]) .. "] = " .. ir[i][3] .. " % max\n")
        elseif command == "add-to" then
            output_write(
                "data[ptr" .. ptr_offset(ir[i][4]) .. "] = (data[ptr" .. ptr_offset(ir[i][4]) .. "] " ..
                ir[i][3] .. " data[ptr" .. ptr_offset(ir[i][5]) .. "]) % max\n"
            )
        elseif command == "move-to" then
            output_write(
                "data[ptr" .. ptr_offset(ir[i][4]) .. "] = (" .. ir[i][3] ..
                " + data[ptr" .. ptr_offset(ir[i][5]) .. "]) % max\n"
            )
        end

        if loops < 0 then break end
    end
end

--- Main function.
local main = function()
    local infile = nil      -- input filename
    local outfile = nil     -- output filename
    local bfcode = ""       -- Brainfuck code
    local ir = {}           -- intermediate representation
    local output            -- output file
    local run = false       -- run the output ?
    local functions = false -- use functions in the output ?

    -- parse commandline args
    for i = 1, #arg do
        if arg[i] == "-h" or arg[i] == "--help" then
            io.write(help_message)
            os.exit(0)
        elseif arg[i] == "-i" or arg[i] == "--input" then
            if arg[i + 1] == nil then
                print("Option " .. arg[i] .. " requires an argument")
                os.exit(1)
            else
                infile = tostring(arg[i + 1])
            end
        elseif arg[i] == "-o" or arg[i] == "--output" then
            if arg[i + 1] == nil then
                print("Option " .. arg[i] .. " requires an argument")
                os.exit(1)
            else
                outfile = tostring(arg[i + 1])
            end
        elseif arg[i] == "-f" or arg[i] == "--functions" then
            functions = true
        end
    end

    -- read input
    if infile == nil then
        print("Missing argument -i, run " .. arg[0] .. " -h for help")
        os.exit(1)
    elseif infile == "-" then
        bfcode = read_brainfuck(io.input())
    else
        local input = io.open(infile)
        if input == nil then
            print("Couldn't open " .. infile)
            os.exit(1)
        end
        bfcode = read_brainfuck(input)
        input:close()
    end

    -- check for unmatched loops
    local loops = count_brainfuck_loops(bfcode)
    if loops > 0 then
        print("Error: missing " .. loops .. " ]")
        os.exit(1)
    elseif loops < 0 then
        print("Error: missing " .. -loops .. " [")
        os.exit(1)
    end

    -- optimize brainfuck code
    bfcode = optimize_brainfuck(bfcode)
    ir = convert_brainfuck(bfcode)
    local ir_length = #ir + 1
    while #ir ~= ir_length do
        ir_length = #ir
        ir = optimize_ir(ir)
        ir = optimize_ir(ir)
    end

    -- open output
    if outfile == nil then
        outfile = os.tmpname()
        output = io.open(outfile, "w")
        if output == nil then
            print("Couldn't open a temporary file")
            os.exit(1)
        end
        run = true
    elseif outfile == "-" then
        output = io.output()
    else
        output = io.open(outfile, "w")
        if output == nil then
            print("Couldn't open " .. outfile)
            os.exit(1)
        end
    end

    -- convert intermediate representation to lua and write to output
    convert_ir(ir, output, functions)
    if output ~= nil then
        output:close()
    end

    -- run output
    if run then
        dofile(outfile)
        os.remove(outfile)
    end
end

main()
