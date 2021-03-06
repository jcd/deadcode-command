module deadcode.command.command;

public import deadcode.command.commandparameter;

import std.algorithm;
import std.conv;
import std.exception;
import std.range : empty;
import std.string : toLower;
import std.typecons;
import deadcode.core.attr;
import deadcode.core.signals;
import deadcode.util.string; 

struct CompletionEntry
{
	string label;
	string data;
}

CompletionEntry[] toCompletionEntries(string[] strs)
{
	import std.algorithm;
    import std.array;
	return array(strs.map!(a => CompletionEntry(a,a))());
}

enum Hints : ubyte
{
	off =	       0,
	completion  =  1,
	description =  2,
	all = ubyte.max,
}

interface ICommand
{
	@property
	{
		string name() const;
		string description() const;
		bool mustRunInFiber() const;
	}
	void setCommandParameterDefinitions(CommandParameterDefinitions defs);
	CommandParameterDefinitions getCommandParameterDefinitions();
	final bool hasCommandParameterDefinitions() 
	{ 
		auto pd = getCommandParameterDefinitions();
		return pd !is null && !pd.empty;
	}
	void onLoaded();
	void onUnloaded();
    void execute(CommandParameter[] data);
    bool executeWithMissingArguments(ref CommandParameter[] data);
	void undo(CommandParameter[] data);
    int getCompletionSessionID();
    bool beginCompletionSession(int sessionID);
    void endCompletionSession();
    final CompletionEntry[] getCompletions(string input)
	{
		CommandParameter[] ps;
		auto defs = getCommandParameterDefinitions();
		if (defs is null)
			return null;
		defs.parseValues(ps, input);
		return getCompletions(ps);
	}
    CompletionEntry[] getCompletions(CommandParameter[] data);
}

class Command : ICommand
{
	private CommandParameterDefinitions _commandParamtersTemplate;
    static int sNextID = 1;
    int id;
	@property
	{
		string name() const
		{
			import std.algorithm;
			import std.range;
			import std.string;
			import std.uni;

			auto toks = this.classinfo.name.splitter('.').retro;

			string className = null;
			// class Name is assumed PascalCase ie. FooBarCommand and the Command postfix is stripped
			// The special case of extension.FunctionCommand!(xxxx).FunctionCommand
			// is for function commands and the xxx part is pulled out instead.
			if (toks.front == "ExtensionCommandWrap")
			{
				toks.popFront();
				auto idx = toks.front.lastIndexOf('(');
				if (idx == -1)
					className = "invalid-command-name:" ~ this.classinfo.name;
				else
				{
					auto idx2 = toks.front.lastIndexOf(',');
					className ~= toks.front[idx+1].toUpper;
					className ~= toks.front[idx+2..idx2];
				}
			}
			else
			{
				className = toks.front;
			}

			return classNameToCommandName(className.chomp("Command"));
		}

		static protected string classNameToCommandName(string className)
		{
			string cmdName;
			cmdName ~= className[0].toLower;
                        className = className[1..$];
			cmdName ~= className.munch("[a-z0-9_]");
			if (!className.empty)
			{
				cmdName ~= ".";
				cmdName ~= className.munch("A-Z").toLower;
				cmdName ~= className;
			}
			return cmdName;

			//string cmdName;
			//
			//while (!className.empty)
			//{
			//    if (!cmdName.empty)
			//        cmdName ~= ".";
			//    cmdName ~= className.munch("A-Z")[0].toLower;
			//    cmdName ~= className.munch("[a-z0-9_]");
			//}
			//return cmdName;
		}

        string description() const
        {
            if (_commandParamtersTemplate is null)
                return null;

            string res;
            foreach (i; 0.._commandParamtersTemplate.length)
            {
                res ~= _commandParamtersTemplate[i].name;
                res ~= "(";
                auto d = _commandParamtersTemplate[i].description;
                if (d.length != 0)
                {
                    res ~= d;
                    res ~= " ";
                }
                if (_commandParamtersTemplate[i].isNull)
                {
                    res ~= "mandatory";
                }
                else
                {
                    res ~= "default: ";
                    auto p = _commandParamtersTemplate[i].parameter;
                    res ~= (cast(CommandParameter)p).toString();
                }
                res ~= ")";
            }
            return res;
        }

        //string shortcut() const
        //{
        //    return null;
        //}
        //
        //int hints() const
        //{
        //    return Hints.all;
        //}

		bool mustRunInFiber() const 
		{
			return false;
		}
	}

	this(CommandParameterDefinitions paramsTemplate = null)
	{
        id = sNextID++;
		_commandParamtersTemplate = paramsTemplate;
	}

	void setCommandParameterDefinitions(CommandParameterDefinitions defs)
	{
		_commandParamtersTemplate = defs;
	}

	CommandParameterDefinitions getCommandParameterDefinitions()
	{
		return _commandParamtersTemplate;
	}

	/// Called once the command has been loaded e.g. on app startup
	void onLoaded()
	{
		// no-op
	}

	// Called just before unloading the command e.g. on app shutdown
	void onUnloaded()
	{
		// no-op
	}

	@RPC
    abstract void execute(CommandParameter[] data);

    bool executeWithMissingArguments(ref CommandParameter[] data) { return false; /* false => not handled by method */ }

	void undo(CommandParameter[] data) { }

    int getCompletionSessionID() { return -1; /* no session support */ }
    bool beginCompletionSession(int sessionID) { return false; }
    void endCompletionSession() {}

	CompletionEntry[] getCompletions(CommandParameter[] data)
	{
		return null;
	}
}

class DelegateCommand : Command
{
	private string _name;
	private string _description;

	override @property string name() const { return _name; }
	override @property string description() const { return _description; }

	void delegate(CommandParameter[] d) executeDel;
	void delegate(CommandParameter[] d) undoDel;
	CompletionEntry[] delegate (CommandParameter[] d) completeDel;

	this(string nameIn, string descIn, CommandParameterDefinitions paramDefs,
		 void delegate(CommandParameter[]) executeDel, void delegate(CommandParameter[]) undoDel = null)
	{
		super(paramDefs);
		_name = nameIn;
		_description = descIn;
		this.executeDel = executeDel;
		this.undoDel = undoDel;
	}

	final override void execute(CommandParameter[] data)
	{
		executeDel(data);
	}

	final override void undo(CommandParameter[] data)
	{
		if (undoDel !is null)
			undoDel(data);
	}

	override CompletionEntry[] getCompletions(CommandParameter[] data)
	{
		if (completeDel !is null)
			return completeDel(data);
		return null;
	}
}

// First way to do it
class CommandHello : Command
{
	override @property const
	{
		string name() { return "test.hello"; }
		string description() { return "Echo \"Hello\" to stdout"; }
	}

	this()
	{
		super(null);
	}

	override void execute(CommandParameter[] data)
	{
        import std.stdio;
		version (linux)
            writeln("Hello");
	}
}

// Second way to do it
auto helloCommand()
{
    static import std.stdio;
	return new DelegateCommand("test.hello", "Echo \"Hello\" to stdout",
							   null,
	                           delegate (CommandParameter[] data) { std.stdio.writeln("Hello"); });
}


//@Command("edit.cursorDown", "Moves cursor count lines down");
//void cursorDown(int count = 1)
//{
//
//}

interface ICommandManager
{    
    void add(ICommand command);
	bool exists(string commandName);
    void execute(string commandName, CommandParameter[] params);
	void execute(T)(string cmd, T arg1)
	{
        execute(cmd, [ CommandParameter(arg1) ]);
    }
}

class CommandManager : ICommandManager
{
	// Runtime check that only one instance is created ie. not for use in singleton pattern.
	private static CommandManager _the; // assert only singleton
    private int _nextCompletionSessionID = 1;
    private ICommand[int] _completionSessions;

	mixin Signal!(CommandCall) onCommandExecuted;

    this()
	{
		assert(_the is null);
		_the = this;
	}

	// name -> Command
	enum NeedFiber : byte
	{
		invalid,
		unknown,
		yes,
		no
	}

	struct CommandEntry
	{
		ICommand cmd;
		NeedFiber needFiber;
	}
	private CommandEntry[string] commands; 
	
    bool delegate(ICommand) mustRunInFiberDlg;

	// TODO: Rename to create(..) when dmd supports overloading on parameter that is delegates with different params. Currently this method
	//       conflicts with the method below because of dmd issues.
	DelegateCommand create(string name, string description, CommandParameterDefinitions paramDefs,
						   void delegate(CommandParameter[]) executeDel,
						   void delegate(CommandParameter[]) undoDel = null)
	{
		auto c = new DelegateCommand(name, description, paramDefs, executeDel, undoDel);
		add(c);
		return c;
	}

	//DelegateCommand create(T)(string name ,string description, void delegate(Nullable!T) executeDel, void delegate(Nullable!T) undeDel = null) if ( ! is(T == class ))
	//{
	//    create(name, description,
	//           (Variant v) {
	//                auto d = v.peek!(Nullable!T);
	//                if (d is null)
	//           },
	//           undoDel is null ? null : (Variant) { });
	//}

	//DelegateCommand create(T)(string name ,string description, void delegate(T) executeDel, void delegate(T) undeDel = null) if ( is(T == class ))
	//{
	//    static assert(0);
	//}


/*	DelegateCommand create(string name, string description, void delegate() del)
	{
		return create(name, description, del, null);
	}
*/
	void add(ICommand command)
	{

		add(command, NeedFiber.no);
	}

	/** Add a command
	 *
	 * Params:
	 * command = Command to add
	 * name = if not null then set as the name of the command. Else command.name is used.
	 * description = if not null then set as the description of the command. Else command.description is used.
	 */
	void add(ICommand command, NeedFiber n)
	{
		enforceEx!Exception(!(command.name in commands), text("Trying to add existing command ", command.name, " ", command.classinfo.name));
		commands[command.name] = CommandEntry(command, n);
	}

	/** Remove a command
	 */
	void remove(ICommand cmd)
	{
        foreach (k, v; commands)
        {
            if (v.cmd is cmd)
            {
                commands.remove(k);
                break;
            }
        }

	}

    /// ditto
	void remove(string commandName)
	{
		commands.remove(commandName);
	}

    void remove(bool delegate(string, ICommand) pred)
	{
        // TODO: Do smarter
        bool doCheck = true;
        while (doCheck)
        {
            doCheck = false;
            foreach (k; commands.byKey)
            {
                if (pred(k, commands[k].cmd))
                {
                    commands.remove(k);
                    doCheck = true;
                    break;
                }
            }
        }
	}

	void execute(CommandCall c)
	{
		auto cmd = lookup(c.name);
		execute(cmd, c.arguments);
	}

	void execute(string cmdName, CommandParameter[] args = null)
	{
		auto cmd = lookup(cmdName);
		execute(cmd, args);
	}

	private void execute(ICommand cmd, CommandParameter[] args)
	{
		// TODO: handle fibers
        if (cmd is null)
            return;

		import core.thread;
		if (mustRunInFiber(cmd))
        {
			new Fiber({execute(cmd, args);}).call();
		}
        else
        {
			cmd.execute(args);
        }
	}

    void parseAndExecute(string cmdNameAndArgs)
	{
        auto cmdName = cmdNameAndArgs.munch("^ ");
        cmdNameAndArgs.munch(" ");

        auto cmd = lookup(cmdName);
        if (cmd is null)
            return; // TODO: error handling

		import core.thread;
        if (mustRunInFiber(cmd))
        {
            new Fiber({
                auto args = parseArguments(cmd, cmdNameAndArgs);
                execute(cmd, args);
            }).call();
        }
        else
        {
		    auto args = parseArguments(cmd, cmdNameAndArgs);
		    execute(cmd, args);
        }
	}
	
	void parseArgumentsAndExecute(string cmdName, string argsString)
    {
        auto cmd = lookup(cmdName);
        if (cmd is null)
            return; // TODO: error handling

		import core.thread;
        if (mustRunInFiber(cmd))
        {
            new Fiber({parseArgumentsAndExecute(cmdName, argsString);}).call();
        }
        else
        {
            execute(cmd, parseArguments(cmd, argsString));
        }
    }

	CommandParameter[] parseArguments(ICommand cmd, string argsString)
    {
        enforce(mustRunInFiber(cmd) == false);

        CommandParameter[] args;
        auto defs = cmd.getCommandParameterDefinitions();
        if (defs !is null)
            defs.parseValues(args, argsString);
		return args;
	}

	CommandCall parse(string cmdNameAndArgs)
	{
		auto cmdName = cmdNameAndArgs.munch("^ ");
		cmdNameAndArgs.munch(" ");
		auto args = parseCommandArguments(cmdName, cmdNameAndArgs);
		return CommandCall(cmdName, args);
	}

    CommandParameter[] parseCommandArguments(string cmdName, string argsString)
    {
        auto cmd = lookup(cmdName);
        if (cmd is null)
            return null;
		return parseArguments(cmd, argsString);
    }

    private final bool mustRunInFiber(ICommand cmd)
    {
		import core.thread;
        return Fiber.getThis() is null && 
            ( (mustRunInFiberDlg is null && cmd.mustRunInFiber) || mustRunInFiberDlg(cmd) );
    }

    bool executeWithMissingArguments(string cmdName, ref CommandParameter[] args)
    {
		auto cmd = lookup(cmdName);
		// TODO: handle fibers
		if (cmd !is null)
		{
			import core.thread;
			if (mustRunInFiber(cmd))
            {
				new Fiber( () { cmd.executeWithMissingArguments(args); } ).call(); // TODO: handle return value
            }
			else
            {
				return cmd.executeWithMissingArguments(args);
            }
		}
        return false;
    }

	CommandParameterDefinitions getCommandParameterDefinitions(string commandName)
	{
		auto cmd = lookup(commandName);
		if (cmd is null)
			return null;

		return cmd.getCommandParameterDefinitions();
	}

	private ICommand lookup(string commandName)
	{
		auto c = commandName in commands;
		if (c !is null) return c.cmd;
		return null;
	}

	bool exists(string commandName)
	{
		auto c = commandName in commands;
		return c !is null;
	}

	NeedFiber getCommandFiberNeed(string commandName)
	{
		auto c = commandName in commands;
		if (c !is null) return c.needFiber;
		return NeedFiber.invalid;
	}

	auto lookupByPrefix(string commandNameStartsWith)
	{
		return commands
				.byKey
				.filter!(a => a.startsWith(commandNameStartsWith));
	}

	auto lookupFuzzy(string searchString, bool includeEmptySearch = false)
    {
        import std.algorithm;
        import std.array;

        return commands
            .byKey
			.rank(searchString, includeEmptySearch)
            .array
            .sort!((a,b) => a[0] > b[0]);

/*
		static struct SortEntry
        {
            double rank;
            Command cmd;
        }
commands.
        SortEntry[] entries;
		foreach (key, cmd; commands)
		{
            auto r = key.rank(searchString);
            if (r != 0.0)
                entries ~= SortEntry(r, cmd);
        }

        Command[] result;
        return entries
            .map!(a => a.cmd)
            .array();
        */
    }

	CompletionEntry[] getCompletions(string cmdName, string data)
	{
		auto cmd = lookup(cmdName);
		if (cmd is null)
			return null;
		return cmd.getCompletions(data);
	}

	CompletionEntry[] getCompletions(string cmdName, CommandParameter[] data)
	{
		auto cmd = lookup(cmdName);
		if (cmd is null)
			return null;
		return cmd.getCompletions(data);
	}

	final bool hasCommandParameterDefinitions(string cmdName) 
	{
		auto cmd = lookup(cmdName);
		if (cmd is null)
			return false;
		return cmd.hasCommandParameterDefinitions();
	}

    int beginCompletionSession(string cmdName)
    {
        auto cmd = lookup(cmdName);
        if (cmd is null)
            return -1;

        if (cmd.beginCompletionSession(_nextCompletionSessionID++))
        {
            _completionSessions[_nextCompletionSessionID-1] = cmd;
            return _nextCompletionSessionID-1;
        }
        return -1; // cmd disallowed the session
    }

    bool endCompletionSession(int sessionID)
    {
        if (auto s = sessionID in _completionSessions)
        {
            s.endCompletionSession();
            _completionSessions.remove(sessionID);
            return true;
        }
        return false;
    }
}

// TODO: fix
/* API:
View	 		TextView
RegionSet		RegionSet
Region			Region
Edit			N/A
Window 			Window
Settings		N/A

Base Classes:

EventListener
ApplicationCommand
WindowCommand
TextCommand
*/
/*
// Application wide command. One instance for the application.
class ApplicationCommand : Command
{
	this(string name, string desc) { super(name, desc); }
}


// Window wide command. One instance per window.
class WindowCommand : Command
{
	this(string name, string desc) { super(name, desc); }
}

// Editor wide command. One instance per editor.
class EditCommand : Command
{
	this(string name, string desc) { super(name, desc); }
}

*/
