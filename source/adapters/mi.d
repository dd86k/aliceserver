/// GDB/MI adapter.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module adapters.mi;

// NOTE: Not supported!
//       MI  was introduced in GDB 5.1
//       MI2 was introduced in GDB 6.0
//       MI3 was introduced in GDB 9.1
//       MI4 was introduced in GDB 13.1
//       mi-async 1 (target-async in <= gdb 7.7)

// Reference:
// - https://ftp.gnu.org/old-gnu/Manuals/gdb/html_chapter/gdb_22.html
// - https://sourceware.org/gdb/current/onlinedocs/gdb.html/GDB_002fMI.html
// - https://github.com/lldb-tools/lldb-mi
// - gdb: gdb/mi

import adapters;
import transports;
import logging;

class MIAdapter : Adapter
{
    // TODO: version parameter
    this(ITransport t)
    {
        super(t);
    }
    
    override
    AdapterRequest listen()
    {
        return AdapterRequest();
    }
    
    override
    void reply(AdapterReply msg)
    {
        
    }
    
    override
    void reply(AdapterError msg)
    {
        
    }
    
    override
    void event(AdapterEvent msg)
    {
        
    }
}