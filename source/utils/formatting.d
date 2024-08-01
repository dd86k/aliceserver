/// Text formatting utilities.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module utils.formatting;

import std.algorithm.iteration : splitter;
import std.algorithm.searching : count;
import std.conv : text;
import std.string : indexOf, strip, toStringz;
import core.stdc.stdio : sscanf;

/// Unformat any type of number.
/// Exceptions: None.
/// Params: str = Input string.
/// Returns: Unformatted number; Or zero.
int unformat(string str)
{
    int d = void;
    return sscanf(str.toStringz, "%i", &d) == 1 ? d : 0;
}

/// Parse string for integer using sscanf("%i").
/// Params:
///     input = Input string.
///     value = Parsed value.
/// Returns: True if successful.
bool parse(string input, long *value)
{
    assert(value);
    return sscanf(input.toStringz, "%lli", value) > 0;
}
unittest
{
    long v;
    assert(parse("123", &v));
    assert(v == 123L);
    assert(parse("0x123", &v));
    assert(v == 0x123L);
}
