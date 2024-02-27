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
/// Params: str = 
/// Returns: Unformatted number; Or zero.
int unformat(string str)
{
    int d = void;
    return sscanf(str.toStringz, "%i", &d) == 1 ? d : 0;
}

/// Wrap body with HTTP header, only Content-Length is added.
/// Params: data = HTTP data.
/// Returns: Formatted message.
const(char)[] encodeHTTP(const(char)[] data)
{
    return text(
        "Content-Length: ", data.length, "\r\n",
        "\r\n",
        data);
}
unittest
{
    assert(encodeHTTP("It's me") ==
        "Content-Length: 7\r\n"~
        "\r\n"~
        "It's me");
}