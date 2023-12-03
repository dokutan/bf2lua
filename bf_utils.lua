--- brainfuck utilities
-- @module bf_utils

local bf_utils = {}

local function is_in(key, set)
    for _, v in ipairs(set) do
        if key == v then
            return true
        end
    end
    return false
end


--- Read brainfuck code from `file`.
--- @tparam file file input file
--- @treturn string brainfuck program
bf_utils.read_brainfuck = function(file)
    local program = {}

    repeat
        local command = file:read(1)

        if command ~= nil and string.match(command, "[<>%+%-%.,%[%]#]") ~= nil then
            program[#program + 1] = command
        end
    until command == nil -- EOF

    return table.concat(program, "")
end


--- Removes useless sequences of commands from a brainfuck program.
--- Adds the '0' command to set a cell to zero.
--- @tparam string program brainfuck program
--- @tparam int optimization optimization level
--- @tparam bool debugging enable the debugging command: '#'
--- @treturn string optimized brainfuck program
bf_utils.optimize_brainfuck = function(program, optimization, debugging)
    -- remove all characters that are not brainfuck commands
    program = string.gsub(program, "[^><%+%-.,%]%[#]", "")
    if not debugging then
        program = string.gsub(program, "#", "")
    end

    if optimization < 1 then
        return program
    end

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
    local s = 0
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
--- @tparam string program brainfuck program
--- @treturn int the number of unmatched loop commands
bf_utils.count_brainfuck_loops = function(program)
    local _, count_open = string.gsub(program, "%[", "[")
    local _, count_close = string.gsub(program, "%]", "]")
    return count_open - count_close
end


--- Converts Brainfuck code to an intermediate representation.
---
--- The intermediate representation is a table containing the following commands
--- (some commands are only generated by optimize_ir()):
---
--- * {"[", indentation depth, nil, ptr offset}
--- * {"]", indentation depth}
--- * {"if", indentation depth}
--- * {",", indentation depth, nil, ptr offset}
--- * {".", indentation depth, value offset, ptr offset} (add value offset + value of cell at ptr + ptr offset)
--- * {"+", indentation depth, value, ptr offset} (add value to cell at ptr + ptr offset)
--- * {"-", indentation depth, value, ptr offset} (subtract value from cell at ptr + ptr offset)
--- * {"=", indentation depth, value, ptr offset} (assign value to cell at ptr + ptr offset)
--- * {"<", indentation depth, value} (move ptr by -value)
--- * {">", indentation depth, value} (move ptr by value)
--- * {"add-to2", indentation depth, value +, value *, ptr offset to, ptr offset from}
--- * {"move-to2", indentation depth, value =, value *, ptr offset to, ptr offset from}
--- * {"#", indentation depth} call bf_debug
--- @tparam string program brainfuck program
--- @treturn table intermediate representation
bf_utils.convert_brainfuck = function(program)
    local loops = 0
    local counter = 1          -- used to count and join repeating commands
    local skipped_zero = false -- indicates if zeroing a cell has been omitted from the output
    local ir = {}

    for i = 1, #program do
        if string.sub(program, i, i) == "[" then
            -- output_write("while (data[ptr] or 0) ~= 0 do\n")
            ir[#ir + 1] = { "[", loops, nil, 0 }
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
        elseif string.sub(program, i, i) == "#" then
            ir[#ir + 1] = { "#", loops }
        end
    end

    return ir
end


--- Optimize the intermediate representation.
--- @tparam table ir intermediate representation
--- @tparam int optimization optimization level
--- @treturn table optimized intermediate representation
bf_utils.optimize_ir = function(ir, optimization)
    if optimization < 2 then
        return ir
    end

    local optimized_ir = {}
    local i = 1
    while i <= #ir - 2 do
        if -- while → if
            ir[i][1] == "[" and ir[i][4] == 0
        then
            local correct_instructions = true
            local current_cell_zero = false
            for j = i+1, #ir do
                if ir[j][1] == "]" then
                    break
                elseif not is_in(ir[j][1], { "+", "-", "=", ".", "add-to2", "move-to2" }) then
                    correct_instructions = false
                    break
                elseif is_in(ir[j][1], { "+", "-", "=" }) and ir[j][3] ~= 0 and ir[j][4] == 0 then
                    correct_instructions = false
                    break
                elseif is_in(ir[j][1], { "add-to2", "move-to2" }) and ir[j][5] == 0 then
                    correct_instructions = false
                    break
                elseif ir[j][1] == "=" and ir[j][3] == 0 and ir[j][4] == 0 then
                    current_cell_zero = true
                end
            end


            if correct_instructions and current_cell_zero then
                optimized_ir[#optimized_ir + 1] = { "if", ir[i][2] }
                i = i + 1
            end
        end

        if -- loop → add-to2
            ir[i][1] == "[" and ir[i][4] == 0
        then
            local correct_instructions = true
            local cell_deltas = {}
            for j = i+1, #ir do
                if ir[j][1] == "]" then
                    break
                elseif not is_in(ir[j][1], { "+", "-" }) then
                    correct_instructions = false
                    break
                elseif ir[j][1] == "+" then
                    cell_deltas[ir[j][4]] = (cell_deltas[ir[j][4]] or 0) + ir[j][3]
                elseif ir[j][1] == "-" then
                    cell_deltas[ir[j][4]] = (cell_deltas[ir[j][4]] or 0) - ir[j][3]
                end
            end

            if correct_instructions and cell_deltas[0] == -1 then
                local depth = ir[i][2]
                i = i + 2
                for ptr_offset, multiplied_by in pairs(cell_deltas) do
                    if ptr_offset ~= 0 then
                        optimized_ir[#optimized_ir + 1] = { "add-to2", depth, 0, multiplied_by, ptr_offset, 0 }
                    end
                    i = i + 1
                end
                optimized_ir[#optimized_ir + 1] = { "=", depth, 0, 0 }
            end
        end

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
        elseif -- swap > with add-to2
            ir[i][1] == ">" and
            ir[i + 1][1] == "add-to2"
        then
            optimized_ir[#optimized_ir + 1] = { "add-to2", ir[i + 1][2], ir[i + 1][3], ir[i + 1][4], ir[i + 1][5] + ir[i][3], ir[i + 1][6] + ir[i][3] }
            optimized_ir[#optimized_ir + 1] = { ">", ir[i][2], ir[i][3] }
            i = i + 2
        elseif -- swap < with add-to2
            ir[i][1] == "<" and
            ir[i + 1][1] == "add-to2"
        then
            optimized_ir[#optimized_ir + 1] = { "add-to2", ir[i + 1][2], ir[i + 1][3], ir[i + 1][4], ir[i + 1][5] - ir[i][3], ir[i + 1][6] - ir[i][3] }
            optimized_ir[#optimized_ir + 1] = { "<", ir[i][2], ir[i][3] }
            i = i + 2
        elseif -- swap > with move-to2
            ir[i][1] == ">" and
            ir[i + 1][1] == "move-to2"
        then
            optimized_ir[#optimized_ir + 1] = { "move-to2", ir[i + 1][2], ir[i + 1][3], ir[i + 1][4], ir[i + 1][5] + ir[i][3], ir[i + 1][6] + ir[i][3] }
            optimized_ir[#optimized_ir + 1] = { ">", ir[i][2], ir[i][3] }
            i = i + 2
        elseif -- swap < with move-to2
            ir[i][1] == "<" and
            ir[i + 1][1] == "move-to2"
        then
            optimized_ir[#optimized_ir + 1] = { "move-to2", ir[i + 1][2], ir[i + 1][3], ir[i + 1][4], ir[i + 1][5] - ir[i][3], ir[i + 1][6] - ir[i][3] }
            optimized_ir[#optimized_ir + 1] = { "<", ir[i][2], ir[i][3] }
            i = i + 2
        elseif -- combine + with add-to2
            ir[i][1] == "+" and
            ir[i + 1][1] == "add-to2" and
            ir[i][4] == ir[i + 1][5]
        then
            optimized_ir[#optimized_ir + 1] = { "add-to2", ir[i + 1][2], ir[i + 1][3] + ir[i][3], ir[i + 1][4], ir[i + 1][5], ir[i + 1][6] }
            i = i + 2
        elseif -- combine - with add-to2
            ir[i][1] == "-" and
            ir[i + 1][1] == "add-to2" and
            ir[i][4] == ir[i + 1][5]
        then
            optimized_ir[#optimized_ir + 1] = { "add-to2", ir[i + 1][2], ir[i + 1][3] - ir[i][3], ir[i + 1][4], ir[i + 1][5], ir[i + 1][6] }
            i = i + 2
        elseif -- = and add-to2 → move-to2
            ir[i][1] == "=" and
            ir[i + 1][1] == "add-to2" and
            ir[i][4] == ir[i + 1][5] -- both commands act on the same cell
        then
            optimized_ir[#optimized_ir + 1] = { "move-to2", ir[i + 1][2], ir[i][3], ir[i + 1][4], ir[i + 1][5], ir[i + 1][6] }
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
        elseif -- sort +, -, = and add-to2
            is_in(ir[i][1], { "+", "-", "=" }) and
            ir[i + 1][1] == "add-to2" and
            ir[i][4] > ir[i + 1][5] and
            ir[i][4] ~= ir[i + 1][6]
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4], ir[i + 1][5], ir[i + 1][6] }
            optimized_ir[#optimized_ir + 1] = { ir[i][1], ir[i][2], ir[i][3], ir[i][4] }
            i = i + 2
        elseif -- sort add-to2 and +, -, =
            ir[i][1] == "add-to2" and
            is_in(ir[i + 1][1], { "+", "-", "=" }) and
            ir[i][5] > ir[i + 1][4] and
            ir[i][6] ~= ir[i + 1][4]
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] }
            optimized_ir[#optimized_ir + 1] = { ir[i][1], ir[i][2], ir[i][3], ir[i][4], ir[i][5], ir[i][6] }
            i = i + 2
        elseif -- sort add-to2
            ir[i][1] == "add-to2" and
            ir[i + 1][1] == "add-to2" and
            ir[i][5] > ir[i + 1][5] and
            ir[i][6] ~= ir[i + 1][5] and
            ir[i][5] ~= ir[i + 1][6]
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4], ir[i + 1][5], ir[i + 1][6] }
            optimized_ir[#optimized_ir + 1] = { ir[i][1], ir[i][2], ir[i][3], ir[i][4], ir[i][5], ir[i][6] }
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
        elseif -- >[≶] → [≶]>
            ir[i][1] == ">" and
            ir[i + 1][1] == "[" and
            is_in(ir[i + 2][1], { ">", "<" }) and
            ir[i + 3][1] == "]"
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] + ir[i][3] }
            optimized_ir[#optimized_ir + 1] = { ir[i + 2][1], ir[i + 2][2], ir[i + 2][3], ir[i + 2][4] }
            optimized_ir[#optimized_ir + 1] = { ir[i + 3][1], ir[i + 3][2] }
            optimized_ir[#optimized_ir + 1] = { ir[i][1], ir[i][2], ir[i][3] }
            i = i + 4
        elseif -- <[≶] → <[≶]
            ir[i][1] == "<" and
            ir[i + 1][1] == "[" and
            is_in(ir[i + 2][1], { ">", "<" }) and
            ir[i + 3][1] == "]"
        then
            optimized_ir[#optimized_ir + 1] = { ir[i + 1][1], ir[i + 1][2], ir[i + 1][3], ir[i + 1][4] - ir[i][3] }
            optimized_ir[#optimized_ir + 1] = { ir[i + 2][1], ir[i + 2][2], ir[i + 2][3], ir[i + 2][4] }
            optimized_ir[#optimized_ir + 1] = { ir[i + 3][1], ir[i + 3][2] }
            optimized_ir[#optimized_ir + 1] = { ir[i][1], ir[i][2], ir[i][3] }
            i = i + 4
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
---
--- @tparam table ir intermediate representation
--- @tparam boolean functions whether to generate functions for loops
--- @tparam boolean debugging whether to generate calls to bf_debug
--- @tparam int maximum maximum value of a brainfuck cell
--- @tparam string output_header header that defines `data`, `ptr`, ...
--- @tparam string debug_header header that defines `bf_debug()`
--- @treturn string Lua code
bf_utils.convert_ir = function(ir, functions, debugging, maximum, output_header, debug_header)
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
    local mod_max = " % max"
    if maximum == 0 then
        mod_max = ""
    end

    local lua_code = output_header:format(maximum + 1)
    if debugging then
        lua_code = lua_code .. debug_header
    end

    for i = 1, #ir do
        local command = ir[i][1]
        local loops = ir[i][2]

        local output_write = function(str)
            lua_code = lua_code .. string.rep("\t", loops) .. str
        end

        if command == "[" then
            output_write("while data[ptr" .. ptr_offset(ir[i][4]) .. "] ~= 0 do\n")

            if functions then
                output_write("function loop" .. function_counter .. "()\n")
                function_names[loops] = function_counter
                function_counter = function_counter + 1
            end
        elseif command == "if" then
            output_write("if data[ptr] ~= 0 then\n")
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
            output_write("data[ptr" .. ptr_offset(ir[i][4]) .. "] = string.byte(io.read(1) or 0)\n")
        elseif command == "." then
            output_write(
                "io.write(string.char((data[ptr" .. ptr_offset(ir[i][4]) .. "]" ..
                ptr_offset(ir[i][3] or 0) .. ")" .. mod_max .. "))\n"
            )
        elseif command == "+" then
            output_write(
                "data[ptr" .. ptr_offset(ir[i][4]) ..
                "] = (data[ptr" .. ptr_offset(ir[i][4]) .. "] + " .. ir[i][3] .. ")" .. mod_max .. "\n"
            )
        elseif command == "-" then
            output_write(
                "data[ptr" .. ptr_offset(ir[i][4]) ..
                "] = (data[ptr" .. ptr_offset(ir[i][4]) .. "] - " .. ir[i][3] .. ")" .. mod_max .. "\n"
            )
        elseif command == "<" then
            output_write("ptr = ptr - " .. ir[i][3] .. "\n")
        elseif command == ">" then
            output_write("ptr = ptr + " .. ir[i][3] .. "\n")
        elseif command == "=" then
            if maximum > 0 then
                output_write("data[ptr" .. ptr_offset(ir[i][4]) .. "] = " .. (ir[i][3] % maximum) .. "\n") -- TODO! add option to disable this
            else
                output_write("data[ptr" .. ptr_offset(ir[i][4]) .. "] = " .. ir[i][3] .. mod_max .. "\n")
            end
        elseif command == "add-to2" then
            local add = ""
            if ir[i][3] > 0 then
                add = "+ " .. ir[i][3] .. " "
            elseif ir[i][3] < 0 then
                add = "- " .. -ir[i][3] .. " "
            end

            local multiply = ""
            if ir[i][4] == 1 then
                multiply = "+ "
            elseif ir[i][4] == -1 then
                multiply = "- "
            elseif ir[i][4] > 0 then
                multiply = "+ " .. ir[i][4] .. " * "
            elseif ir[i][4] < 0 then
                multiply = "- " .. -ir[i][4] .. " * "
            end

            output_write(
                "data[ptr" .. ptr_offset(ir[i][5]) .. "] = (data[ptr" .. ptr_offset(ir[i][5]) .. "] " .. add .. multiply .. "data[ptr" .. ptr_offset(ir[i][6]) .. "])" .. mod_max .. "\n"
            )
        elseif command == "move-to2" then
            local add = ""
            if ir[i][3] > 0 then
                add = " + " .. ir[i][3]
            elseif ir[i][3] < 0 then
                add = " - " .. -ir[i][3]
            end

            local multiply = ""
            if ir[i][4] == -1 then
                multiply = "-"
            elseif ir[i][4] ~= 1 then
                multiply = ir[i][4] .. " * "
            end

            if add == "" and multiply == "" then
                output_write(
                    "data[ptr" .. ptr_offset(ir[i][5]) .. "] = data[ptr" .. ptr_offset(ir[i][6]) .. "]\n"
                )
            else
                output_write(
                    "data[ptr" .. ptr_offset(ir[i][5]) .. "] = (" .. multiply .. "data[ptr" .. ptr_offset(ir[i][6]) .. "]" .. add .. ")" .. mod_max .. "\n"
                )
            end
        elseif command == "#" and debugging then
            output_write("bf_debug()\n")
        end
    end

    return lua_code
end

return bf_utils
