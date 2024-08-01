/// JSON utilities.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module utils.json;

import std.json;

/// Optionally set the target from JSON.
///
/// Does not set value if key does not exist.
/// Example:
/// ---
/// JSONValue j = [
///   "test": 3
/// ];
/// int val;
/// optional(j, "test", val);
/// assert(val == 3);
/// ---
/// Params:
///   json = JSONValue to get value from.
///   name = JSON field name.
///   receiver = lvalue receiving the value.
/// Returns: True if receiver was set.
bool optional(T)(ref JSONValue json, string name, ref T receiver)
{
    const(JSONValue)* p = name in json;
    static if (is(T == JSONValue))
    {
        if (p) receiver = *p;
    }
    else
    {
        if (p) receiver = (*p).get!T;
    }
    return p != null;
}
/// Ditto
bool optional(T)(const(JSONValue) *json, string name, ref T receiver)
{
    const(JSONValue) *p = name in *json;
    static if (is(T == JSONValue))
    {
        if (p) receiver = *p;
    }
    else
    {
        if (p) receiver = (*p).get!T;
    }
    return p != null;
}
unittest
{
    JSONValue v;
    v["test"] = "value";
    
    string value;
    assert(optional(v, "test", value));
    assert(value == "value");
    
    assert(optional(v, "field_name_404", value) == false);
}

/// Optionally set the target from JSON.
///
/// Throws an exception if key was not found.
/// Example:
/// ---
/// JSONValue j = [
///   "test": 3
/// ];
/// int val;
/// required(j, "test", val);
/// assert(val == 3);
/// ---
/// Params:
///   json = JSONValue to get value from.
///   name = JSON field name.
///   receiver = lvalue receiving the value.
void required(T)(ref JSONValue json, string name, ref T receiver)
{
    static if (is(T == JSONValue))
        receiver = json[name];
    else
        receiver = json[name].get!T;
}
unittest
{
    JSONValue v;
    v["test"] = "value";
    
    string value;
    required(v, "test", value);
    
    assert(value == "value");
    
    try
    {
        required(v, "required_field", value);
        assert(false);
    }
    catch (Exception)
    {
        
    }
}

/+void setoptional(T)(ref JSONValue json, string name, T value)
{
    if (value == value.init)
        return;
    json[name] = value;
}+/