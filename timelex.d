debug import std.stdio;
import std.datetime;
import std.string;
import std.regex;
import std.range;
import std.traits;

private enum split_decimal = ctRegex!(`([\.,])`);

package final class TimeLex(Range) if (isInputRange!Range && isSomeChar!(ElementType!Range))
{
    //Fractional seconds are sometimes split by a comma
    private Range instream;
    private string charstack;
    private string[] tokenstack;

    this(Range r)
    {
        instream = r;
    }

    /**
     This function breaks the time string into lexical units (tokens), which
     can be parsed by the parser. Lexical units are demarcated by changes in
     the character set, so any continuous string of letters is considered
     one unit, any continuous string of numbers is considered one unit.

     The main complication arises from the fact that dots ('.') can be used
     both as separators (e.g. "Sep.20.2009") or decimal points (e.g.
     "4:30:21.447"). As such, it is necessary to read the full context of
     any dot-separated strings before breaking it into tokens; as such, this
     function maintains a "token stack", for when the ambiguous context
     demands that multiple tokens be parsed at once.
     */
    string get_token()
    {
        import std.algorithm.searching : count;
        import std.uni : isNumber, isSpace, isAlpha;

        if (instream.empty)
            return string.init;

        if (tokenstack)
        {
            auto f = tokenstack.front;
            tokenstack.popFront;
            return f;
        }

        bool seenletters = false;
        string token;
        string state;

        // This is just a state machine, use enums and switch to speed up
        while (!instream.empty)
        {
            // We only realize that we've reached the end of a token when we
            // find a character that's not part of the current token - since
            // that character may be part of the next token, it's stored in the
            // charstack.
            dchar nextchar;

            if (!charstack.empty)
            {
                nextchar = charstack.front;
                charstack.popFront;
            }
            else
            {
                nextchar = instream.front;
                instream.popFront;

                while (nextchar == '\x00')
                {
                    nextchar = instream.front;
                    instream.popFront;
                }
            }

            if (state.empty)
            {
                // First character of the token - determines if we're starting
                // to parse a word, a number or something else.
                token ~= nextchar;
                if (isAlpha(nextchar))
                {
                    state = "a";
                }
                else if (isNumber(nextchar))
                {
                    state = "0";
                }
                else if (isSpace(nextchar))
                {
                    token = " ";
                    break; //emit token
                }
                else
                {
                    break; //emit token
                }
            }
            else if (state == "a")
            {
                // If we've already started reading a word, we keep reading
                // letters until we find something that's not part of a word.
                seenletters = true;
                if (isAlpha(nextchar))
                {
                    token ~= nextchar;
                }
                else if (nextchar == '.')
                {
                    token ~= nextchar;
                    state = "a.";
                }
                else
                {
                    charstack ~= nextchar;
                    break; //emit token
                }
            }
            else if (state == "0")
            {
                // If we've already started reading a number, we keep reading
                // numbers until we find something that doesn't fit.
                if (isNumber(nextchar))
                {
                    token ~= nextchar;
                }
                else if (nextchar == '.' || (nextchar == ',' && token.length >= 2))
                {
                    token ~= nextchar;
                    state = "0.";
                }
                else
                {
                    charstack ~= nextchar;
                    break; //emit token
                }
            }
            else if (state == "a.")
            {
                // If we've seen some letters and a dot separator, continue
                // parsing, and the tokens will be broken up later.
                seenletters = true;
                if (nextchar == '.' || isAlpha(nextchar))
                {
                    token ~= nextchar;
                }
                else if (isNumber(nextchar) && token[$ - 1] == '.')
                {
                    token ~= nextchar;
                    state = "0.";
                }
                else
                {
                    charstack ~= nextchar;
                    break; //emit token
                }
            }
            else if (state == "0.")
            {
                // If we've seen at least one dot separator, keep going, we'll
                // break up the tokens later.
                if (nextchar == '.' || isNumber(nextchar))
                {
                    token ~= nextchar;
                }
                else if (isAlpha(nextchar) && token[-1] == '.')
                {
                    token ~= nextchar;
                    state = "a.";
                }
                else
                {
                    charstack ~= nextchar;
                    break; //emit token
                }
            }
        }

        if ((state == "a." || state == "0.") || (seenletters
                || token.count('.') > 1 || (token[$ - 1] == '.' || token[$ - 1] == ',')))
        {
            auto l = token.split(split_decimal);
            token = l[0];
            foreach (tok; l[1 .. $])
            {
                if (tok.length > 0)
                {
                    tokenstack ~= tok;
                }
            }
        }

        if (state == "0." && token.count('.') == 0)
        {
            token = token.replace(",", ".");
        }

        return token;
    }

    string[] split()
    {
        string[] data;

        while (true)
        {
            auto element = get_token();

            if (element.length != 0)
                data ~= element;
            else
                break;
        }

        return data;
    }
}
