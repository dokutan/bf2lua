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
    program = string.gsub(program, "[^><%+%-.,%]%[]", "")

    local substitutions = {
        ["<>"] = "",
        ["><"] = "",
        ["%+%-"] = "",
        ["%-%+"] = "",
        ["%[%-%]"] = "0",
        ["%[%+%]"] = "0"
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

-- converts Brainfuck code to Lua code
convert_brainfuck = function(program, output)
    local loops = 0
    local counter = 1

    local output_write = function(str)
        output:write(string.rep("\t", loops) .. str)
    end

    output_write(output_header)

    for i = 1, #program do

        if string.sub(program, i, i) == "[" then
            output_write("while (data[ptr] or 0) ~= 0 do\n")
            loops = loops + 1
        elseif string.sub(program, i, i) == "]" then
            output_write("end\n")
            loops = loops - 1
        elseif string.sub(program, i, i) == "," then
            output_write("data[ptr] = string.byte(io.read(1))\n")
        elseif string.sub(program, i, i) == "." then
            output_write("io.write(string.char(data[ptr] or 0))\n")
        elseif string.sub(program, i, i) == "+" then
            if string.sub(program, i + 1, i + 1) == "+" then
                counter = counter + 1
            else
                output_write("data[ptr] = ((data[ptr] or 0) + " .. counter ..
                                 ") % max\n")
                counter = 1
            end
        elseif string.sub(program, i, i) == "-" then
            if string.sub(program, i + 1, i + 1) == "-" then
                counter = counter + 1
            else
                output_write("data[ptr] = ((data[ptr] or 0) - " .. counter ..
                                 ") % max\n")
                counter = 1
            end
        elseif string.sub(program, i, i) == "<" then
            if string.sub(program, i + 1, i + 1) == "<" then
                counter = counter + 1
            else
                output_write("ptr = ptr - " .. counter .. "\n")
                counter = 1
            end
        elseif string.sub(program, i, i) == ">" then
            if string.sub(program, i + 1, i + 1) == ">" then
                counter = counter + 1
            else
                output_write("ptr = ptr + " .. counter .. "\n")
                counter = 1
            end
        elseif string.sub(program, i, i) == "0" then
            output_write("data[ptr] = 0\n")
        end

        if loops < 0 then break end
    end
end

-- main function
main = function()
    local infile = nil -- input filename
    local outfile = nil -- output filename
    local bfcode = "" -- Brainfuck code
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
    convert_brainfuck(bfcode, output)
    output:close()

    -- run output
    if run then
        dofile(outfile)
        os.remove(outfile)
    end
end

main()
