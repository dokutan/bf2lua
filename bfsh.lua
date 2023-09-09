#!/usr/bin/env lua

--- Brainfuck shell

local bf_utils = require("bf_utils")
local has_readline, RL = pcall(function() return require("readline") end)

-- readline fallback
if not has_readline then
    print("Install the readline module for a better experience.")
    RL = {}
    RL.readline = function(prompt)
        io.write(prompt)
        return io.read()
    end
    RL.add_history = function(_) end
    RL.set_readline_name = function(_) end
end

--- Colors
local colors = {
    reset = "\x1b[0m",
    red = "\x1b[91m",
    yellow = "\x1b[93m",
    magenta = "\x1b[95m",
}

--- Brainfuck state
data = {}
ptr = 1
max = 256
setmetatable(data, {__index = function() return 0 end})
printlua = false
trace = nil
input = nil

local unescape = function(str)
    return str:gsub("\\n", "\n"):gsub("\\0", "\0"):gsub("\\\\", "\\")
end

local run_brainfuck = function(command, prompt, functions, optimization, debugging, maximum)
    local loops = bf_utils.count_brainfuck_loops(command)
    while loops > 0 do
        command = command .. "\n" .. RL.readline(loops .. prompt)
        loops = bf_utils.count_brainfuck_loops(command)
    end

    if loops < 0 then
        print(colors.red .. "unmatched ]" .. colors.reset)
        return
    end

    RL.add_history(command)
    io.stdin:setvbuf("no")

    -- convert brainfuck to Lua
    local bf_code = bf_utils.optimize_brainfuck(command, optimization, debugging)
    local ir = bf_utils.convert_brainfuck(bf_code)
    local lua_code = bf_utils.convert_ir(ir, functions, debugging, maximum, "", "")

    -- modify Lua code
    if trace then
        lua_code = "trace[#trace + 1] = ptr\n" .. lua_code
        lua_code = lua_code:gsub("(ptr = [^\n]*)", "%1; trace[#trace + 1] = ptr")
    end
    if input then
        lua_code = lua_code:gsub("(string.byte%(io.read%(%d*%)%))", "string.byte(input) or 0; input = input:sub(2)")
    end

    -- run Lua code
    if printlua then print(colors.yellow .. lua_code .. colors.reset) end
    local bf_fn = load(lua_code)
    if bf_fn then
        io.write(colors.magenta)
        bf_fn()
        io.write(colors.reset)
    else
        print(colors.red .. "failed to load lua code" .. colors.reset)
    end

    io.flush()
end

local run_command = function(command)
    command = command:gsub("^%s", ""):gsub("%s$", "")
    if command == "ptr" then
        print(ptr)
    elseif command:match("ptr%s+%d+") then
        ptr = tonumber(command:gmatch("%a+%s+(%d+)")())
    elseif command == "reset" then
        data = {}
        setmetatable(data, {__index = function() return 0 end})
        ptr = 1
        trace = nil
    elseif command == "get" then
        print(data[ptr], ((data[ptr] >= 32 and data[ptr] <= 126) and string.char(data[ptr]) or ""))
    elseif command:match("set%s+%d+") then
        data[ptr] = tonumber(command:gmatch("%a+%s+(%d+)")()) % max
    elseif command:match("inc%s+%d+") then
        data[ptr] = (data[ptr] + tonumber(command:gmatch("%a+%s+(%d+)")())) % max
    elseif command:match("dec%s+%d+") then
        data[ptr] = (data[ptr] - tonumber(command:gmatch("%a+%s+(%d+)")())) % max
    elseif command == "data" then
        io.write(ptr .. ": ")
        for i = -8, 8 do
            if i == 0 then io.write("[") end
            io.write(string.format("%03d", data[ptr+i] or 0))
            if i == 0 then io.write("]") end
            io.write(" ")
        end
        io.write("\n")
    elseif command:match("printlua%son") then
        printlua = true
    elseif command:match("printlua%s+off") then
        printlua = false
    elseif command:match("trace%son") then
        trace = {}
    elseif command:match("trace%s+off") then
        if not trace then
            print(colors.red .. "no trace started" .. colors.reset)
        else
            for _, p in ipairs(trace) do
                print(p)
            end
            trace = nil
        end
    elseif command:match("echo%s+.*") or command == "echo" then
        print(colors.yellow .. unescape(command:gsub("^%a+%s*", "")) .. colors.reset)
    elseif command == "input" then
        input = nil
    elseif command:match("input%s+.*") then
        input = unescape(command:gsub("^%a+%s*", ""))
    elseif command == "help" then
        print([[Enter brainfuck code or a command, available commands:

ptr [VALUE]
reset
get
set VALUE
inc VALUE
dec VALUE
data
help
printlua on|off
trace on|off
echo [TEXT]
input [TEXT]
        ]])
    else
        print(colors.red .. "unknown or wrong command" .. colors.reset)
    end
end

--- Main function.
local main = function()
    local functions = false -- use functions in the output ?
    local optimization = 0  -- optimization level
    local debugging = false -- enable debugging
    local maximum = 255     -- maximum value of a cell
    local default_prompt = "> "

    -- parse commandline args
    local i = 1
    while i <= #arg do
        if arg[i] == "-h" or arg[i] == "--help" then
            io.write(help_message)
            os.exit(0)
        elseif arg[i] == "-O" or arg[i] == "--optimize" then
            if arg[i + 1] == nil then
                print(colors.red .. "Option " .. arg[i] .. " requires an argument" .. colors.reset)
                os.exit(1)
            else
                optimization = tonumber(arg[i + 1]) or optimization
                i = i + 1
            end
        elseif arg[i] == "-m" or arg[i] == "--maximum" then
            if arg[i + 1] == nil then
                print(colors.red .. "Option " .. arg[i] .. " requires an argument" .. colors.reset)
                os.exit(1)
            else
                max = tonumber(arg[i + 1]) + 1 or maximum
                i = i + 1
            end
        elseif arg[i] == "-f" or arg[i] == "--functions" then
            functions = true
        elseif arg[i] == "-g" or arg[i] == "--debug" then
            debugging = true
        else
            print(colors.red .. "Unknown option " .. arg[i] .. colors.reset)
            os.exit(1)
        end
        i = i + 1
    end

    print("\x1b[1;96mbfsh - brainfuck shell")
    print("Enter `help` for a list of commands\x1b[0m")

    -- REPL
    local command = ""
    local prompt = default_prompt
    RL.set_readline_name("bfsh")
    while true do
        command = RL.readline(prompt)

        if command == nil then
            break -- EOF
        elseif command:match("^%s*//") then
            -- comment, do nothing
        elseif command:match("^%s*[a-zA-Z]") then
            run_command(command)
        else
            run_brainfuck(command, prompt, functions, optimization, debugging, maximum)
        end
    end
end

main()
