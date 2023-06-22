#!/usr/bin/env lua

local help_message = [[
bf2.lua - convert Brainfuck to Lua

Convert:
bf2.lua -i input.bf -o output.lua

Convert and run:
bf2.lua -i input.bf

Options:
-h --help		print this message
-i --input		input file, - for stdin
-o --output		output file, - for stdout
]]

local output_header = [[
#!/usr/bin/env lua
data = {}
ptr = 1
max = 256

]]

-- read brainfuck code from file
read_brainfuck = function(file)
    local program = {}

    repeat
        local command = file:read(1)

        if command ~= fail and string.match(command, "[<>%+%-%.,%[%]]") ~= fail then
            program[#program + 1] = command
        end
    until command == fail -- EOF

    return table.concat(program, "")
end

-- removes useless sequences of commands from a brainfuck program
optimise_brainfuck = function(program)
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

        -- the current cell is guaranteed to be zero after a loop
        ["%]0"] = "]",
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

-- counts the number of unmatched loop commands, should return 0 for a valid program
count_brainfuck_loops = function(program)
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

-- converts Brainfuck code to an intermediate representation
convert_brainfuck = function(program)
    local loops = 0
    local counter = 1 -- used to count and join repeating commands
    local skipped_zero = false -- indicates if zeroing a cell has been omitted from the output
    local ir = {}

    for i = 1, #program do

        if string.sub(program, i, i) == "[" then
            -- output_write("while (data[ptr] or 0) ~= 0 do\n")
            ir[#ir + 1] = {"[", loops}
            loops = loops + 1
        elseif string.sub(program, i, i) == "]" then
            loops = loops - 1
            ir[#ir + 1] = {"]", loops}
        elseif string.sub(program, i, i) == "," then
            ir[#ir + 1] = {",", loops}
        elseif string.sub(program, i, i) == "." then
            ir[#ir + 1] = {".", loops}
        elseif string.sub(program, i, i) == "+" then
            if string.sub(program, i + 1, i + 1) == "+" then
                counter = counter + 1
            elseif skipped_zero then
                ir[#ir + 1] = {"=", loops, counter}
                counter = 1
                skipped_zero = false
            else
                ir[#ir + 1] = {"+", loops, counter}
                counter = 1
            end
        elseif string.sub(program, i, i) == "-" then
            if string.sub(program, i + 1, i + 1) == "-" then
                counter = counter + 1
            elseif skipped_zero then
                ir[#ir + 1] = {"=", loops, -counter}
                counter = 1
                skipped_zero = false
            else
                ir[#ir + 1] = {"-", loops, counter}
                counter = 1
            end
        elseif string.sub(program, i, i) == "<" then
            if string.sub(program, i + 1, i + 1) == "<" then
                counter = counter + 1
            else
                ir[#ir + 1] = {"<", loops, counter}
                counter = 1
            end
        elseif string.sub(program, i, i) == ">" then
            if string.sub(program, i + 1, i + 1) == ">" then
                counter = counter + 1
            else
                ir[#ir + 1] = {">", loops, counter}
                counter = 1
            end
        elseif string.sub(program, i, i) == "0" then
            if string.sub(program, i + 1, i + 1) == "+" or
                string.sub(program, i + 1, i + 1) == "-" then
                -- setting this cell to zero can be skipped, because the value will be set with the next instruction
                skipped_zero = true
            else
                ir[#ir + 1] = {"0", loops}
            end
        end

        if loops < 0 then break end
    end

    return ir
end

-- converts the intermediate representation to Lua code
convert_ir = function(ir, output)
    output:write(output_header)

    for i = 1, #ir do
        local command = ir[i][1]
        local loops = ir[i][2]

        local output_write = function(str)
            output:write(string.rep("\t", loops) .. str)
        end

        if command == "[" then
            output_write("while (data[ptr] or 0) ~= 0 do\n")
        elseif command == "]" then
            output_write("end\n")
        elseif command == "," then
            output_write("data[ptr] = string.byte(io.read(1))\n")
        elseif command == "." then
            output_write("io.write(string.char(data[ptr] or 0))\n")
        elseif command == "+" then
            output_write("data[ptr] = ((data[ptr] or 0) + " .. ir[i][3] ..
                             ") % max\n")
        elseif command == "-" then
            output_write("data[ptr] = ((data[ptr] or 0) - " .. ir[i][3] ..
                             ") % max\n")
        elseif command == "<" then
            output_write("ptr = ptr - " .. ir[i][3] .. "\n")
        elseif command == ">" then
            output_write("ptr = ptr + " .. ir[i][3] .. "\n")
        elseif command == "0" then
            output_write("data[ptr] = 0\n")
        elseif command == "=" then
            output_write("data[ptr] = " .. ir[i][3] .. " % max\n")
        end

        if loops < 0 then break end
    end
end

-- main function
main = function()
    local infile = nil -- input filename
    local outfile = nil -- output filename
    local bfcode = "" -- Brainfuck code
    local ir = {} -- intermediate representation
    local output -- output file
    local run = false

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
        end
    end

    -- read input
    if infile == nil then
        print("Missing argument -i, run " .. arg[0] .. " -h for help")
        os.exit(1)
    elseif infile == "-" then
        bfcode = read_brainfuck(io.input())
    else
        input = io.open(infile)
        if input == fail then
            print("Couldn't open " .. infile)
            os.exit(1)
        end
        bfcode = read_brainfuck(input)
        input:close()
    end

    -- optimise brainfuck code
    bfcode = optimise_brainfuck(bfcode)
    ir = convert_brainfuck(bfcode)

    -- check for unmatched loops
    local loops = count_brainfuck_loops(bfcode)
    if loops > 0 then
        print("Error: missing " .. loops .. " ]")
        os.exit(1)
    elseif loops < 0 then
        print("Error: missing " .. -loops .. " [")
        os.exit(1)
    end

    -- open output
    if outfile == nil then
        outfile = os.tmpname()
        output = io.open(outfile, "w")
        if output == fail then
            print("Couldn't open a temporary file")
            os.exit(1)
        end
        run = true
    elseif outfile == "-" then
        output = io.output()
    else
        output = io.open(outfile, "w")
        if output == fail then
            print("Couldn't open " .. outfile)
            os.exit(1)
        end
    end

    -- convert brainfuck to lua and write to output
    convert_ir(ir, output)
    output:close()

    -- run output
    if run then
        dofile(outfile)
        os.remove(outfile)
    end
end

main()
