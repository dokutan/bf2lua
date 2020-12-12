# bf2lua
Brainfuck to Lua transpiler

## Usage
- Clone this repository
- Make sure that you have Lua installed
- Convert ``input.bf`` to ``output.lua``
```
./bf2lua -i input.bf -o output.lua
```
or
```
lua bf2lua -i input.bf -o output.lua
```
- Convert and run ``input.bf``
```
./bf2lua -i input.bf
```
or
```
lua bf2lua -i input.bf
```

## Optimisations and checks
- Useless combinations of Brainfuck commands like ``+-``, ``[]``, ``<>`` or ``+[]-`` are ignored
- Successive identical commands are combined into a single line of Lua code
- The total number of loop commands (``[`` and ``]``) is checked to be balanced
