#!/usr/bin/env lua

--- Brainfuck to Lua transpiler
-- @script bf2lua

local bf_utils = require("bf_utils")

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
-O --optimize 0-2 optimization level, the default is 1
-f --functions    create a function for each loop
                  this improves compatibility with luajit and lua<5.4
-g --debug        enable the '#' command, which prints debug info to stderr
-m --maximum      set the maximum value of a cell, default is 255 = 8-bit cells
                  use 0 to disable wrapping cells
]]

local output_header = [[
#!/usr/bin/env lua
local data = {}
local ptr = 1
local max = %d

setmetatable(data, {__index = function() return 0 end})

]]

local debug_header = [[
function bf_debug()
    io.stderr:write(ptr .. ": ")
    for i = -8, 8 do
		if i == 0 then io.stderr:write("[") end
		io.stderr:write(string.format("%03d", data[ptr+i] or 0))
		if i == 0 then io.stderr:write("]") end
		io.stderr:write(" ")
	end
    io.stderr:write("\n")
end

]]

--- Main function.
local main = function()
    local infile = nil      -- input filename
    local outfile = nil     -- output filename
    local bfcode = ""       -- Brainfuck code
    local ir = {}           -- intermediate representation
    local output            -- output file
    local run = false       -- run the output ?
    local functions = false -- use functions in the output ?
    local optimization = 1  -- optimization level
    local debugging = false -- enable debugging
    local maximum = 255     -- maximum value of a cell

    -- parse commandline args
    local i = 1
    while i <= #arg do
        if arg[i] == "-h" or arg[i] == "--help" then
            io.write(help_message)
            os.exit(0)
        elseif arg[i] == "-i" or arg[i] == "--input" then
            if arg[i + 1] == nil then
                print("Option " .. arg[i] .. " requires an argument")
                os.exit(1)
            else
                infile = tostring(arg[i + 1])
                i = i + 1
            end
        elseif arg[i] == "-o" or arg[i] == "--output" then
            if arg[i + 1] == nil then
                print("Option " .. arg[i] .. " requires an argument")
                os.exit(1)
            else
                outfile = tostring(arg[i + 1])
                i = i + 1
            end
        elseif arg[i] == "-O" or arg[i] == "--optimize" then
            if arg[i + 1] == nil then
                print("Option " .. arg[i] .. " requires an argument")
                os.exit(1)
            else
                optimization = tonumber(arg[i + 1]) or optimization
                i = i + 1
            end
        elseif arg[i] == "-m" or arg[i] == "--maximum" then
        if arg[i + 1] == nil then
            print("Option " .. arg[i] .. " requires an argument")
            os.exit(1)
        else
            maximum = tonumber(arg[i + 1]) or maximum
            i = i + 1
        end
        elseif arg[i] == "-f" or arg[i] == "--functions" then
            functions = true
        elseif arg[i] == "-g" or arg[i] == "--debug" then
            debugging = true
        else
            print("Unknown option " .. arg[i])
            os.exit(1)
        end
        i = i + 1
    end

    -- read input
    if infile == nil then
        print("Missing argument -i, run " .. arg[0] .. " -h for help")
        os.exit(1)
    elseif infile == "-" then
        bfcode = bf_utils.read_brainfuck(io.input())
    else
        local input = io.open(infile)
        if input == nil then
            print("Couldn't open " .. infile)
            os.exit(1)
        end
        bfcode = bf_utils.read_brainfuck(input)
        input:close()
    end

    -- check for unmatched loops
    local loops = bf_utils.count_brainfuck_loops(bfcode)
    if loops > 0 then
        print("Error: missing " .. loops .. " ]")
        os.exit(1)
    elseif loops < 0 then
        print("Error: missing " .. -loops .. " [")
        os.exit(1)
    end

    -- optimize brainfuck code
    bfcode = bf_utils.optimize_brainfuck(bfcode, optimization, debugging)
    ir = bf_utils.convert_brainfuck(bfcode)
    local ir_length = #ir + 1
    while #ir ~= ir_length do
        ir_length = #ir
        ir = bf_utils.optimize_ir2(ir, optimization)
        ir = bf_utils.optimize_ir(ir, optimization, maximum)
        ir = bf_utils.optimize_ir(ir, optimization, maximum)
        ir = bf_utils.optimize_ir(ir, optimization, maximum)
        ir = bf_utils.optimize_ir(ir, optimization, maximum)
        ir = bf_utils.optimize_ir(ir, optimization, maximum)
        ir = bf_utils.optimize_ir(ir, optimization, maximum)
        ir = bf_utils.optimize_ir(ir, optimization, maximum)
        ir = bf_utils.optimize_ir(ir, optimization, maximum)
        ir = bf_utils.optimize_ir(ir, optimization, maximum)
        ir = bf_utils.optimize_ir(ir, optimization, maximum)
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
    output:write(bf_utils.convert_ir(ir, functions, debugging, maximum, output_header, debug_header))
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
