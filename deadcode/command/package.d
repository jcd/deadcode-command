module deadcode.command;

public import deadcode.command.command;

void registerCommandParameterMsgPackHandlers()()
{
    static import msgpack;
    import std.conv;

    static void commandParameterPackHandler(ref msgpack.Packer packer, ref CommandParameter param)
    {
        import std.variant;
        param.tryVisit!( (uint p) { int id = 1; packer.pack(id); packer.pack(p); },
                         (int p) { int id = 2; packer.pack(id); packer.pack(p); },
                         (string p) { int id = 3; packer.pack(id); packer.pack(p); },
                         (float p) { int id = 4; packer.pack(id); packer.pack(p); }, 
                         (bool p) { int id = 5; packer.pack(id); packer.pack(p); } 
                         );
    }

    static void commandParameterUnpackHandler(ref msgpack.Unpacker u, ref CommandParameter p)
    {
        int id;
        u.unpack(id);
        switch (id)
        {
            case 1:
                uint r;
                u.unpack(r);
                p = r;
                break;
            case 2:
                int r;
                u.unpack(r);
                p = r;
                break;
            case 3:
                string r;
                u.unpack(r);
                p = r;
                break;
            case 4:
                float r;
                u.unpack(r);
                p = r;
                break;
            case 5:
                bool r;
                u.unpack(r);
                p = r;
                break;
            default:
                throw new Exception("Cannot unpack CommandParamter with type " ~ id.to!string);
        }
    }
    
    static void commandParameterDefinitionsPackHandler(ref msgpack.Packer packer, ref CommandParameterDefinitions p)
    {
        packer.pack(p.parameters);
        packer.pack(p.parameterNames);
        packer.pack(p.parameterDescriptions);
        packer.pack(p.parametersAreNull);
    }

    static void commandParameterDefinitionsUnpackHandler(ref msgpack.Unpacker packer, ref CommandParameterDefinitions p)
    {
        packer.unpack(p.parameters);
        packer.unpack(p.parameterNames);
        packer.unpack(p.parameterDescriptions);
        packer.unpack(p.parametersAreNull); 
    }

    msgpack.registerPackHandler!(CommandParameter, commandParameterPackHandler);
    msgpack.registerUnpackHandler!(CommandParameter, commandParameterUnpackHandler);

    msgpack.registerPackHandler!(CommandParameterDefinitions, commandParameterDefinitionsPackHandler);
    msgpack.registerUnpackHandler!(CommandParameterDefinitions, commandParameterDefinitionsUnpackHandler);
}
