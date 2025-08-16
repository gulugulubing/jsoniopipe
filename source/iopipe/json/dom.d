/**
 * Mechanism to parse JSON data into a JSON object tree. Some aspects borrowed
 * from std.json.
 */
module iopipe.json.dom;
import iopipe.json.parser;
public import iopipe.json.common;
import iopipe.traits;
import std.traits;
import iopipe.json.serialize;

enum JSONType
{
    Integer,
    Floating,
    String,
    Obj,
    Array,
    Null,
    Bool,
}

struct JSONValue(SType)
{
    // basically a tagged union.
    JSONType type;
    union
    {
        long integer;
        real floating;
        JSONValue[] array;
        JSONValue[immutable(SType)] object;
        SType str;
        bool boolean;
    }
}

private JSONValue!SType buildValue(SType, Tokenizer, P)(ref Tokenizer parser, JSONItem item, ref P policy)
{
    // Check depth before proceeding
    if (policy.maxDepthAvailable <= 0) {
        throw new JSONIopipeException("Maximum JSON nesting depth exceeded");  
    }
    
    
    import std.conv;

    alias JT = JSONValue!SType;
    with(JSONToken) switch (item.token)
    {
    case ObjectStart:
        policy.maxDepthAvailable--;
        auto obj = parser.buildObject!SType(policy);
        policy.maxDepthAvailable++;
        return obj;
    case ArrayStart:
        policy.maxDepthAvailable--;
        auto arr = parser.buildArray!SType(policy);
        policy.maxDepthAvailable++;
        return arr;
    case String:
        // See if we require copying.
        {
            JT result;
            result.type = JSONType.String;
            result.str = extractString!SType(item, parser.chain);
            return result;
        }
    case Number:
        {
            // if it's an integer, parse as an integer. If not, parse as a float.
            // TODO: really this should be done while parsing, not that hard.
            import std.conv: parse;
            JT result;
            auto str = item.data(parser.chain);
            if(item.hint == JSONParseHint.Int)
            {
                result.type = JSONType.Integer;
                result.integer = parse!long(str);
                assert(str.length == 0);
                return result;
            }
            else
            {
                // floating point or with exponent
                result.type = JSONType.Floating;
                result.floating = parse!real(str);
                assert(str.length == 0);
                return result;
            }
        }
    case Null:
        {
            JT result;
            result.type = JSONType.Null;
            return result;
        }
    case True:
        {
            JT result;
            result.type = JSONType.Bool;
            result.boolean = true;
            return result;
        }
    case False:
        {
            JT result;
            result.type = JSONType.Bool;
            result.boolean = false;
            return result;
        }
    default:
        throw new JSONIopipeException("Error in JSON data");
    }
}

private JSONValue!SType buildObject(SType, Tokenizer, P)(ref Tokenizer parser, ref P policy)
{

    alias JT = JSONValue!SType;
    auto item = parser.next();
    JT obj;
    obj.type = JSONType.Obj;
    while(item.token != JSONToken.ObjectEnd)
    {
        if(item.token == JSONToken.Comma)
        {
            item = parser.next;
            continue;
        }
        // the item must be a string
        assert(item.token == JSONToken.String);
        auto name = parser.buildValue!SType(item, policy);
        item = parser.next();
        // should always be colon
        assert(item.token == JSONToken.Colon);
        item = parser.next();
        obj.object[name.str.idup] = parser.buildValue!SType(item, policy);
        // release any parsed data.
        if(policy.relPol == ReleasePolicy.afterMembers)
            parser.releaseParsed();
        item = parser.next();
    }
    return obj;
}

private JSONValue!SType buildArray(SType, Tokenizer, P)(ref Tokenizer parser, ref P policy)
{
    alias JT = JSONValue!SType;
    auto item = parser.next();
    JT arr;
    arr.type = JSONType.Array;
    while(item.token != JSONToken.ArrayEnd)
    {
        arr.array ~= parser.buildValue!SType(item, policy);
        if(policy.relPol == ReleasePolicy.afterMembers)
            parser.releaseParsed();
        item = parser.next();
        if(item.token == JSONToken.Comma)
            item = parser.next();
    }
    return arr;
}

/** Parse into JSONValue tree until end of root object.
 * Throws:
 * 	JSONIopipeException on parser error.
 */
auto parseJSON(Tokenizer, P)(ref Tokenizer tokenizer, ref P policy) if (isInstanceOf!(JSONTokenizer, Tokenizer))
{
    return parseJSON!(WindowType!(typeof(tokenizer.chain)))(tokenizer, policy);
}

auto parseJSON(SType, Tokenizer, P)(ref Tokenizer tokenizer, ref P policy) if (isInstanceOf!(JSONTokenizer, Tokenizer))
{
    auto item = tokenizer.next();
    auto result = tokenizer.buildValue!SType(item, policy);
    if(policy.relPol == ReleasePolicy.afterMembers)
        tokenizer.releaseParsed();
    return result;
}

auto parseJSON(SType = void, Chain)(Chain chain) if (isIopipe!Chain && is(SType == void))
{
    return parseJSON!(WindowType!Chain)(chain);
}

auto parseJSON(SType, Chain)(Chain chain) if (isIopipe!Chain)
{
    enum shouldReplaceEscapes = is(typeof(chain.window[0] = chain.window[1]));
    auto tokenizer = (chain).jsonTokenizer!(ParseConfig(shouldReplaceEscapes));
    auto policy = DefaultDeserializationPolicy!false();
    return tokenizer.parseJSON!SType(policy);
}

void printTree(JT)(JT item)
{
    import std.stdio;
    final switch(item.type) with (JSONType)
    {
    case Obj:
        {
            write("{");
            bool first = true;
            foreach(n, v; item.object)
            {
                if(first)
                    first = false;
                else
                    write(", ");
                writef(`"%s" : `, n);
                printTree(v);
            }
            write("}");
        }
        break;
    case Array:
        {
            write("[");
            bool first = true;
            foreach(v; item.array)
            {
                if(first)
                    first = false;
                else
                    write(", ");
                printTree(v);
            }
            write("]");
        }
        break;
    case Integer:
        write(item.integer);
        break;
    case Floating:
        write(item.floating);
        break;
    case Null:
        write("null");
        break;
    case Bool:
        write(item.boolean);
        break;
    case String:
        writef(`"%s"`, item.str);
        break;
    }
}

unittest
{
    auto jt = parseJSON(q"{{"a" : [1, 2.5, "x", true, false, null]}}");
    //printTree(jt);
    auto jt2 = parseJSON!(wstring)(q"{{"a" : [1, 2.5, "x\ua123", true, false, null]}}");
    //printTree(jt2);
}
