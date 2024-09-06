/// JSON utilities.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module util.json;

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

/// Require JSON value by key.
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
/// Throws: Throws JSONException if key was not found.
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
        assert(false); // didn't throw
    }
    catch (Exception) {}
}

/// Require JSON value by key.
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
/// Returns: Value by requested type.
/// Throws: Throws JSONException if key was not found.
T required(T)(ref JSONValue json, string name)
{
    static if (is(T == JSONValue))
        return json[name];
    else
        return json[name].get!T;
}
unittest
{
    JSONValue v;
    v["test"] = "value";
    
    assert(required!string(v, "test") == "value");
    
    try
    {
        assert(required!string(v, "required_field") == ""); // force comparison
        assert(false); // didn't throw
    }
    catch (Exception) {}
}