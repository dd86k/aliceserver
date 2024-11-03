/// Implements a MI type that can be used like std.json.JSONValue.
///
/// Currently only implements write operations, since there is no need to parse MI.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module util.mi;

import std.array : Appender, appender; // std.json uses this for toString()
import std.conv : text;
import std.traits : isArray;

enum MIType : ubyte
{
    null_,
    string_,
    boolean_,
    
    integer,
    uinteger,
    floating,
    
    object_,
    array,
}

struct MIValue
{
    string str()
    {
        if (type != MIType.string_)
            throw new Exception(text("Not a string, it is ", type));
        return store.string_;
    }
    string str(string v)
    {
        type = MIType.string_;
        return store.string_ = v;
    }
    
    bool boolean()
    {
        if (type != MIType.boolean_)
            throw new Exception(text("Not a boolean, it is ", type));
        return store.boolean;
    }
    bool boolean(bool v)
    {
        type = MIType.boolean_;
        return store.boolean = v;
    }
    
    long integer()
    {
        if (type != MIType.integer)
            throw new Exception(text("Not an integer, it is ", type));
        return store.integer;
    }
    long integer(long v)
    {
        type = MIType.integer;
        return store.integer = v;
    }
    
    // Get value by index
    ref typeof(this) opIndex(return scope string key)
    {
        if (type != MIType.object_)
            throw new Exception(text("Attempted to index non-object, it is ", type));
        
        if ((key in store.object_) is null)
            throw new Exception(text("Value not found with key '", key, "'"));
        
        return store.object_[key];
    }
    
    // Set value by key index
    void opIndexAssign(T)(auto ref T value, string key)
    {
        // Only objects can have properties set in them
        switch (type) with (MIType) {
        case object_, null_: break;
        default: throw new Exception(text("MIValue must be object or null, it is ", type));
        }
        
        MIValue mi = void;
        
        static if (is(T : typeof(null)))
        {
            mi.type = MIType.null_;
        }
        else static if (is(T : string))
        {
            mi.type = MIType.string_;
            mi.store.string_ = value;
        }
        else static if (is(T : bool))
        {
            mi.type = MIType.boolean_;
            mi.store.boolean = value;
        }
        else static if (is(T : int) || is(T : long))
        {
            mi.type = MIType.integer;
            mi.store.integer = value;
        }
        else static if (is(T : uint) || is(T : ulong))
        {
            mi.type = MIType.uinteger;
            mi.store.uinteger = value;
        }
        else static if (is(T : float) || is(T : double))
        {
            mi.type = MIType.floating;
            mi.store.floating = value;
        }
        else static if (isArray!T)
        {
            mi.type = MIType.array;
            static if (is(T : void[]))
            {
                mi.store.array = []; // empty MIValue[]
            }
            else
            {
                MIValue[] values = new MIValue[value.length];
                foreach (i, v; value)
                {
                    values[i] = v;
                }
                mi.store.array = values;
            }
        }
        else static if (is(T : MIValue))
        {
            mi = value;
        }
        else static assert(false, "Not implemented for type "~T.stringof);
        
        type = MIType.object_;
        store.object_[key] = mi;
    }
    
    string toString() const
    {
        // NOTE: Formatting, it's like JSON, but...
        //       - Field names are not surrounded by quotes
        //       - All values are string-formatted
        //       - Root level has no base type
        switch (type) with (MIType) {
        case string_:
            return store.string_;
        case boolean_:
            return store.boolean ? "true" : "false";
        case integer:
            return text( store.integer );
        case array:
            Appender!string str = appender!string;
            
            size_t count;
            foreach (value; store.array)
            {
                if (count++)
                    str.put(`,`);
                
                str.put(`"`);
                str.put(value.toString());
                str.put(`"`);
            }
            
            return str.data();
        case object_:
            Appender!string str = appender!string;
            
            size_t count;
            foreach (key, value; store.object_)
            {
                if (count++)
                    str.put(`,`);
                
                char schar = void, echar = void; // start and ending chars
                switch (value.type) with (MIType) {
                case object_:
                    schar = '{';
                    echar = '}';
                    break;
                case array:
                    schar = '[';
                    echar = ']';
                    break;
                default:
                    schar = echar = '"';
                    break;
                }
                
                str.put(key);
                str.put(`=`);
                str.put(schar);
                str.put(value.toString());
                str.put(echar);
            }
            
            return str.data();
        default:
            throw new Exception(text("toString type unimplemented for: ", type));
        }
    }
    
private:
    union Store
    {
        string string_;
        long integer;
        ulong uinteger;
        double floating;
        bool boolean;
        MIValue[string] object_;
        MIValue[] array;
    }
    Store store;
    MIType type;
}
unittest
{
    // Type testing
    {
        MIValue mistring;
        mistring["key"] = "value";
        assert(mistring["key"].str == "value");
        assert(mistring.toString() == `key="value"`);
    }
    {
        MIValue mibool;
        mibool["boolean"] = true;
        assert(mibool["boolean"].boolean == true);
        assert(mibool.toString() == `boolean="true"`);
    }
    {
        MIValue miint;
        miint["int"] = 2;
        assert(miint["int"].integer == 2);
        assert(miint.toString() == `int="2"`);
    }
    {
        MIValue miint;
        miint["int"] = 2;
        assert(miint["int"].integer == 2);
        assert(miint.toString() == `int="2"`);
    }
    
    /*
    ^done,threads=[
    {id="2",target-id="Thread 0xb7e14b90 (LWP 21257)",
    frame={level="0",addr="0xffffe410",func="__kernel_vsyscall",
            args=[]},state="running"},
    {id="1",target-id="Thread 0xb7e156b0 (LWP 21254)",
    frame={level="0",addr="0x0804891f",func="foo",
            args=[{name="i",value="10"}],
            file="/tmp/a.c",fullname="/tmp/a.c",line="158",arch="i386:x86_64"},
            state="running"}],
    current-thread-id="1"
    */
    
    import std.algorithm.searching : canFind, count, startsWith, endsWith; // Lazy & AA will sort keys
    
    MIValue t2;
    t2["id"] = 2;
    t2["thread-id"] = "Thread 0xb7e14b90 (LWP 21257)";
    t2["state"] = "running";
    
    // id="2",target-id="Thread 0xb7e14b90 (LWP 21257)",state="running"
    string t2string = t2.toString();
    assert(t2string.canFind(`id="2"`));
    assert(t2string.canFind(`thread-id="Thread 0xb7e14b90 (LWP 21257)"`));
    assert(t2string.canFind(`state="running"`));
    assert(t2string.count(`,`) == 2);
    
    MIValue t2frame;
    t2frame["level"] = 0;
    t2frame["addr"]  = "0xffffe410";
    t2frame["func"]  = "__kernel_vsyscall";
    t2frame["args"]  = [];

    // Test objects in objects
    MIValue t2t;
    t2t["frame"] = t2frame;
    // frame={level="0",addr="0xffffe410",func="__kernel_vsyscall",args=[]}
    string t2tstring = t2t.toString();
    assert(t2tstring.canFind(`level="0"`));
    assert(t2tstring.canFind(`addr="0xffffe410"`));
    assert(t2tstring.canFind(`func="__kernel_vsyscall"`));
    assert(t2tstring.canFind(`args=[]`));
    assert(t2tstring.count(`,`) == 3);
    assert(t2tstring.startsWith(`frame={`));
    assert(t2tstring.endsWith(`}`));
    
    // Test all
    t2["frame"] = t2frame;
    string t2final = t2.toString();
    assert(t2final.canFind(`id="2"`));
    assert(t2final.canFind(`thread-id="Thread 0xb7e14b90 (LWP 21257)"`));
    assert(t2final.canFind(`state="running"`));
    assert(t2final.canFind(`level="0"`));
    assert(t2final.canFind(`addr="0xffffe410"`));
    assert(t2final.canFind(`func="__kernel_vsyscall"`));
    assert(t2final.canFind(`args=[]`));
    
    /*
    MIValue t1;
    t1["id"] = 1;
    t1["thread-id"] = "Thread 0xb7e156b0 (LWP 21254)";
    
    MIValue t1frame;
    t1frame["level"] = 0;
    t1frame["addr"] = 0xffffe410;
    t1frame["func"] = "__kernel_vsyscall";
    t1frame["args"] = [];
    t1frame["state"] = "running";
    t1["frame"] = t1frame;
    
    MIValue root;
    root["thread"] = [ t1, t2 ];
    root["current-thread-id"] = 1;
    
    assert(root.toString() ==
        `threads=[`~
            `{`~
                `id="2",`~
                `target-id="Thread 0xb7e14b90 (LWP 21257)",`~
                `frame={`~
                    `level="0",`~
                    `addr="0xffffe410",`~
                    `func="__kernel_vsyscall",`~
                    `args=[]`~
                `},`~
                `state="running"`~
            `},`~
            `{`~
                `id="1",`~
                `target-id="Thread 0xb7e156b0 (LWP 21254)",`~
                `frame={`~
                    `level="0",`~
                    `addr="0x0804891f",`~
                    `func="foo",`~
                    `args=[{name="i",value="10"}],`~
                    `file="/tmp/a.c",`~
                    `fullname="/tmp/a.c",`~
                    `line="158",`~
                    `arch="i386:x86_64"`~
                `},`~
                `state="running"`~
            `}`~
        `],`~
        `current-thread-id="1"`
    );
    */
}