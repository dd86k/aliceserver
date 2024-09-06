/// Utilities for managing a shell environment.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module util.shell;

import std.ascii : isWhite;

/// Split arguments while accounting for quotes.
///
/// Uses the GC to append to the new array.
/// Params: text = Shell-like input.
/// Returns: Arguments.
/// Throws: Does not explicitly throw any exceptions.
string[] shellArgs(string text)
{
    // NOTE: This is mostly for the MI adapter
    //       Roughly follow gdb/mi/mi-parse.c
    
    // If the input is empty, there is nothing to do
    if (text == null || text.length == 0)
        return null;
    
    // TODO: Redo function more elegantly
    //       Could return both array and iterable struct
    
    string[] args;  // new argument list
    size_t i;       // Current character index
    size_t start;   // start of argument
    char stop;      // stop character
    
    // Get the first significant character
    for (; i < text.length; ++i)
    {
        switch (text[i]) {
        case '\n', '\r', 0:
            return args;
        case '"', '\'': // Match next '"' or '\''
            stop = text[i];
            start = i + 1;
            do
            {
                if (++i >= text.length)
                {
                    args ~= text[start..i-1];
                    return args;
                }
            }
            while (text[i] != stop);
            args ~= text[start..i++]; // exclude quote but need to skip it too
            continue;
        default:
            if (isWhite(text[i])) // skip whitespace
            {
                do
                {
                    if (++i >= text.length)
                        return args;
                }
                while (isWhite(text[i]));
            }
            
            // consume until whitespace
            start = i;
            do
            {
                if (++i >= text.length)
                {
                    args ~= text[start..i];
                    return args;
                }
                
                switch (text[i]) {
                case '\n', '\r':
                    args ~= text[start..i];
                    return args;
                // Quote within text
                // This is painful because `--option="test 2"` needs to be turned
                // into `--option=test 2` - which is not done yet
                case '"', '\'':
                    stop = text[i];
                    start = i + 1;
                    do
                    {
                        if (++i >= text.length)
                        {
                            args ~= text[start..i];
                            return args;
                        }
                    }
                    while (text[i] != stop);
                    args ~= text[start..i];
                    if (i + 1 >= text.length)
                        return args;
                    break;
                default:
                }
            }
            while (text[i] > ' ');
            args ~= text[start..i];
            continue;
        }
    }
    
    return args;
}
unittest
{
    // empty inputs
    assert(shellArgs(null) == null);
    assert(shellArgs("") == null);
    assert(shellArgs("    ") == null);
    assert(shellArgs("\t\n") == null);
    // spacing
    assert(shellArgs("hello") == [ "hello" ]);
    assert(shellArgs("     hello") == [ "hello" ]);
    assert(shellArgs("hello     ") == [ "hello" ]);
    assert(shellArgs("hello dave") == [ "hello", "dave" ]);
    assert(shellArgs("hello dave\n") == [ "hello", "dave" ]);
    assert(shellArgs("hello dave\nhello dave") == [ "hello", "dave" ]);
    assert(shellArgs("hello\tdave") == [ "hello", "dave" ]);
    assert(shellArgs("hello      dave") == [ "hello", "dave" ]);
    assert(shellArgs("hello dave      ") == [ "hello", "dave" ]);
    assert(shellArgs("     hello dave      ") == [ "hello", "dave" ]);
    // quotes
    assert(shellArgs(`hello "dave davidson"`) == [ "hello", "dave davidson" ]);
    assert(shellArgs(`hello 'dave davidson'`) == [ "hello", "dave davidson" ]);
    assert(shellArgs(`hello "test1" "test2"`) == [ "hello", "test1", "test2" ]);
    assert(shellArgs(`hello "test1" 'test2'`) == [ "hello", "test1", "test2" ]);
    assert(shellArgs(`hello 'test1' "test2"`) == [ "hello", "test1", "test2" ]);
    assert(shellArgs(`hello ""`) == [ "hello", "" ]);
    assert(shellArgs(`hello ''`) == [ "hello", "" ]);
    assert(shellArgs(`hello "" ""`) == [ "hello", "", "" ]);
    assert(shellArgs(`hello '' ''`) == [ "hello", "", "" ]);
    assert(shellArgs(`hello "a" ''`) == [ "hello", "a", "" ]);
    // combination of all the above
    assert(shellArgs(`"long/path" -o "dave davidson" 'super nice'`) ==
        [ "long/path", "-o", "dave davidson", "super nice" ]);
    /* TODO: Include when pattern appears
    assert(shellArgs(`"long/path test" --option="dave davidson"`) ==
        [ "long/path test", `--option="dave davidson"` ]);
    */
}