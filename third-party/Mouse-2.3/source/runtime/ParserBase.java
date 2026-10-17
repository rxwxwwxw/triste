//=========================================================================
//
//  Part of PEG parser generator Mouse.
//
//  Copyright (C) 2009, 2010, 2011, 2012, 2015, 2017, 2020, 2021
//  by Roman R. Redziejowski (www.romanredz.se).
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
//-------------------------------------------------------------------------
//
//  Change log
//    Version 1.2
//      Bug fix in accept(): upgrade error info on success.
//      Bug fix in rejectNot(): backtrack before registering failure.
//    Version 1.3
//      Bug fix in errMerge(Phrase): assignment to errText replaced
//      by clear + addAll (assignment produced alias resulting in
//      explosion of errText in memo version).
//      Changed errMerge(msg,pos) to errAdd(who).
//      Commented error handling.
//      Added 'boolReject'.
//      Convert result of 'listErr' to printable.
//    Version 1.4
//      Changed 'listErr' to separate 'not' texts as 'not expected'.
//      Added methods to implement ^[s].
//      Implemented method 'where' of Phrase.
//    Version 1.5
//      Revised methods for ^[s] and ^[c].
//      Implemented methods 'rule' and 'isTerm' of Phrase.
//    Version 1.5.1
//      (Steve Owens) Ensure failure() method does not emit blank
//      line when error info is absent.
//    Version 1.6
//      rhsText: return empty string for empty range.
//    Version 1.7
//      Removed inner class Phrase that became a class on its own.
//      The new class Phrase has an additional parameter ('source')
//      to the constructor that has been added to its calls.
//      Used new Phrase methods in all 'accept' and 'reject'
//      services. Coded these services in a systematic way, which
//      made it possible to unify the services for predicates
//      into 'acceptPred' and 'rejectPred'. Service 'boolReject'
//      could be removed.
//      Replaced method 'failure' by 'closeParser', called on both
//      successful and unsuccessful termination.
//      Added code in 'accept' and 'acceptInner' to propagate
//      deferred actions.
//    Version 1.9.2
//      Do not report failing Rule that just cleared error history.
//    Version 2.0
//      Added service methods for ascent procedures.
//      Added private method 'push'.
//      Set 'createdAt' in Phrases created by 'beginAsc'
//      and 'completeRule'. (It is set by default in Phrases
//      created by 'begin'.)
//    Version 2.1
//      Added stack of ascents and empty semantic action.
//      Changed meaning of 'beginAsc' and 'endAsc'.
//      Added 'endGrow', 'setAct'.
//      Deleted 'beginSeed', 'completeRule', 'acceptAsc', rejectAsc'.
//      Changed 'push' and 'pop' to 'protected'.
//      Add methods 'computeSemantics' and 'descend'.
//      In 'rejectRule': do not 'promote' error info for $-Rule.
//      Initialize semantics only if defined.
//   Version 2.3
//      New service method 'is'.
//      Erase error history if Rule was completed by a failure
//      (clean up of fix from Version 1.9.2).
//      Use 'FuncVV' instead of 'SemAction'.
//
//=========================================================================

package mouse.runtime;

import mouse.runtime.Source;
import java.util.Stack;
import java.util.Vector;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  ParserBase
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

public class ParserBase implements mouse.runtime.CurrentRule
{
  //-------------------------------------------------------------------
  //  Input
  //-------------------------------------------------------------------
  Source source;                    // Source of text to parse
  int endpos;                       // Position after the end of text
  int pos;                          // Current position in the text

  //-------------------------------------------------------------------
  //  Semantics (base)
  //-------------------------------------------------------------------
  protected mouse.runtime.SemanticsBase sem;

  //-------------------------------------------------------------------
  //  Trace string.
  //-------------------------------------------------------------------
  protected String trace = "";

  //-------------------------------------------------------------------
  //  Current phrase (top of parse stack).
  //-------------------------------------------------------------------
  Phrase current = null;

  //-------------------------------------------------------------------
  //  Stack of currently processed ascents.
  //  Entries are references to Phrases for Entry expressions.
  //  Top of the stack identifies current plant.
  //-------------------------------------------------------------------
  Stack<Phrase> ascents;

  //-------------------------------------------------------------------
  //  Empty semantic action.
  //-------------------------------------------------------------------
  protected FuncVV empty$$ = ()->{};

  //-------------------------------------------------------------------
  //  Constructor
  //-------------------------------------------------------------------
  protected ParserBase()
    {}

  //-------------------------------------------------------------------
  //  Initialize parsing
  //-------------------------------------------------------------------
  public void init(Source src)
    {
      source = src;
      pos = 0;
      endpos = source.end();
      current = new Phrase("","",0,source); // Dummy bottom of parse stack
      ascents = new Stack<Phrase>();
    }

  //-------------------------------------------------------------------
  //  Implementation of Parser interface CurrentRule
  //-------------------------------------------------------------------
  public Phrase lhs()
    { return current; }

  public Phrase rhs(int i)
    { return current.rhs.elementAt(i); }

  public int rhsSize()
    { return current.rhs.size(); }

  public String rhsText(int i,int j)
    {
      if (j<=i) return "";
      return source.at(rhs(i).start,rhs(j-1).end);
    }

  //-------------------------------------------------------------------
  //  Set trace
  //-------------------------------------------------------------------
  public void setTrace(String trace)
    {
      this.trace = trace;
      if (sem!=null) sem.trace = trace;
    }

  //-------------------------------------------------------------------
  //  Close parser: print messages (if not caught otherwise).
  //-------------------------------------------------------------------
  protected void closeParser(boolean ok)
    {
      current.actExec();
      if (!ok && current.hwm>=0)
        System.out.println(current.errMsg());
    }

  //=====================================================================
  //
  //  Service methods called from parsing procedures
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Initialize processing of a nonterminal:
  //  create new Phrase and push it on compile stack.
  //-------------------------------------------------------------------
  protected void begin(String name,String diag)
    { push(new Phrase(name,diag,pos,source)); }

  protected void begin(String name)       // Sets diag = name
    { begin(name,name); }

  //-------------------------------------------------------------------
  //  Accept Rule.
  //-------------------------------------------------------------------
  protected boolean accept()
    {
      Phrase p = pop();                // Pop the finishing Phrase
                                       // Finalize p:
      p.success = true;                //   Indicate p successful
      p.rhs.removeAllElements();       //   Discard rhs of p
                                       // Update parent Phrase:
      current.end = pos;               //   End of text
      current.rhs.add(p);              //   Add p to the rhs
      current.hwmUpdFrom(p);           //   Update failure history
      current.defAct.addAll(p.defAct); //   Propagate deferred actions
      return true;
    }

  //-------------------------------------------------------------------
  //  Accept Inner.
  //-------------------------------------------------------------------
  protected boolean acceptInner()
    {
      Phrase p = pop();                // Pop the finishing Phrase
                                       // Finalize p:
      p.success = true;                //   Indicate p successful
                                       // Update parent Phrase:
      current.end = pos;               //   End of text
      current.rhs.addAll(p.rhs);       //   Append p's rhs to the rhs
      current.hwmUpdFrom(p);           //   Update failure history
      current.defAct.addAll(p.defAct); //   Propagate deferred actions
      return true;
    }

  //-------------------------------------------------------------------
  //  Accept predicate.
  //-------------------------------------------------------------------
  protected boolean acceptPred()
    {
      Phrase p = pop();                // Pop the finishing Phrase
      pos = p.start;                   // Do not consume input
                                       // Finalize p:
      p.end = pos;                     //   Reset end of text
      p.success = true;                //   Indicate p successful
      p.rhs = null;                    //   Discard rhs of p
      p.hwmClear();                    //   Remove failure history
                                       // Update parent Phrase:
      current.end = pos;               //   End of text
      return true;
    }

  //-------------------------------------------------------------------
  //  Reject Rule.
  //-------------------------------------------------------------------
  protected boolean reject()
    {
      Phrase p = pop();                // Pop the finishing Phrase
      pos = p.start;                   // Do not consume input
                                       // Finalize p:
      p.end = pos;                     //   Reset end of text
      p.success = false;               //   Indicate p failed
      p.rhs = null;                    //   Discard rhs of p
                                       //   Update error info
      if (pos<p.hwm);                  //     There was later failure
      else if(p.hwm==-2) p.hwm = -1;   //     Ignore indicator was set
      else if (p.hwm==-1 ||            //     If no error yet..
               p.name.charAt(0)!='$')  //     ..or this is not ascent
        p.hwmSet(p.diag,p.start);      //     ..register failure of p
                                       // Update parent Phrase:
      current.end = pos;               //   End of text
      current.hwmUpdFrom(p);           //   Update failure history
      return false;
    }

  //-------------------------------------------------------------------
  //  Reject Inner.
  //-------------------------------------------------------------------
  protected boolean rejectInner()
    {
      Phrase p = pop();                // Pop the finishing Phrase
      pos = p.start;                   // Do not consume input
                                       // Finalize p:
      p.end = pos;                     //   Reset end of text
      p.success = false;               //   Indicate p failed
      p.rhs = null;                    //   Discard rhs of p
                                       // Update parent Phrase:
      current.end = pos;               //   End of text
      current.hwmUpdFrom(p);           //   Update failure history
      return false;
    }

  //-------------------------------------------------------------------
  //  Reject predicate.
  //-------------------------------------------------------------------
  protected boolean rejectPred()
    {
      Phrase p = pop();                // Pop the finishing Phrase
      pos = p.start;                   // Do not consume input
                                       // Finalize p:
      p.end = pos;                     //   Reset end of text
      p.success = false;               //   Indicate p failed
      p.rhs = null;                    //   Discard rhs of p
      p.hwmSet(p.diag,pos);            //   Register 'xxx (not) expected'
                                       // Update parent Phrase:
      current.end = pos;               //   End of text
      current.hwmUpdFrom(p);           //   Update failure history
      return false;
    }

  //=====================================================================
  //
  //  Service method for operation 'a:b' and a:!b'
  //
  //=====================================================================
  protected boolean is(boolean ok, FuncVB a,FuncVB b)
    {
      int savestart = pos;
      if (!a.exec()) return false;
      int saveend = pos;
      Phrase p = current;                // Save current

      current = new Phrase("dummy","dummy",pos,source);
      pos = savestart;
      endpos = saveend;

      boolean match = b.exec() && pos==endpos;

      pos = saveend;
      endpos = source.end();
      current = p;

      if (match==ok) return true;
      p.hwmSet("is expression",savestart);
      return false;
    }

  //=====================================================================
  //
  //  Service methods called from ascent procedures
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Begin ascent.
  //-------------------------------------------------------------------
  protected void beginAsc()
    { ascents.push(current); }

  //-------------------------------------------------------------------
  //  End ascent
  //-------------------------------------------------------------------
  protected void endAsc()
    { ascents.pop(); }

  //-------------------------------------------------------------------
  //  End grow
  //-------------------------------------------------------------------
  protected boolean endGrow()
    {
      // If current Phrase is not for this entry
      if (!current.diag.equals(ascents.peek().name)) return false;

      // If no semantics
      if (sem==null) return true;

      // Otherwise compute semantics of ascent
      ascentSemantics();
      return true;
    }

  //-------------------------------------------------------------------
  //  Set semantic action in Phrase
  //-------------------------------------------------------------------
  protected void setAction(FuncVV act)
    { current.semAct = act; }

  //=====================================================================
  //
  //  Parsing methods for terminals
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Execute expression 'c'
  //-------------------------------------------------------------------
  protected boolean next(char ch)
    {
      if (pos<endpos && source.at(pos)==ch) return consume(1);
      else return fail("'" + ch + "'");
    }

  //-------------------------------------------------------------------
  //  Execute expression ^'c'
  //-------------------------------------------------------------------
  protected boolean nextNot(char ch)
    {
      if (pos<endpos && source.at(pos)!=ch) return consume(1);
      else return fail("not '" + ch + "'");
    }

  //-------------------------------------------------------------------
  //  Execute expression &'c', !^'c'
  //-------------------------------------------------------------------
  protected boolean ahead(char ch)
    {
      if (pos<endpos && source.at(pos)==ch) return true;
      else return fail("'" + ch + "'");
    }

  protected boolean aheadNotNot(char ch)  // temporary
    { return ahead(ch); }

  //-------------------------------------------------------------------
  //  Execute expression !'c', &^'c'
  //-------------------------------------------------------------------
  protected boolean aheadNot(char ch)
    {
      if (pos<endpos && source.at(pos)==ch) return fail("not '" + ch + "'");
      else return true;
    }

  //-------------------------------------------------------------------
  //  Execute expression "s"
  //-------------------------------------------------------------------
  protected boolean next(String s)
    {
      int lg = s.length();
      if (pos+lg<=endpos && source.at(pos,pos+lg).equals(s)) return consume(lg);
      else return fail("'" + s + "'");
    }

  //-------------------------------------------------------------------
  //  Execute expression &"s"
  //-------------------------------------------------------------------
  protected boolean ahead(String s)
    {
      int lg = s.length();
      if (pos+lg<=endpos && source.at(pos,pos+lg).equals(s)) return true;
      else return fail("'" + s + "'");
    }

  //-------------------------------------------------------------------
  //  Execute expression !"s"
  //-------------------------------------------------------------------
  protected boolean aheadNot(String s)
    {
      int lg = s.length();
      if (pos+lg<=endpos && source.at(pos,pos+lg).equals(s)) return fail("not '" + s + "'");
      else return true;
    }

  //-------------------------------------------------------------------
  //  Execute expression [s]
  //-------------------------------------------------------------------
  protected boolean nextIn(String s)
    {
      if (pos<endpos && s.indexOf(source.at(pos))>=0) return consume(1);
      else return fail("[" + s + "]");
    }

  //-------------------------------------------------------------------
  //  Execute expression ^[s]
  //-------------------------------------------------------------------
  protected boolean nextNotIn(String s)
    {
      if (pos<endpos && s.indexOf(source.at(pos))<0) return consume(1);
      else return fail("not [" + s + "]");
    }

  //-------------------------------------------------------------------
  //  Execute expression &[s], !^[s]
  //-------------------------------------------------------------------
  protected boolean aheadIn(String s)
    {
      if (pos<endpos && s.indexOf(source.at(pos))>=0) return true;
      else return fail("[" + s + "]");
    }

  protected boolean aheadNotNotIn(String s) // temporary
    { return aheadIn(s); }

  //-------------------------------------------------------------------
  //  Execute expression ![s], &^[s]
  //-------------------------------------------------------------------
  protected boolean aheadNotIn(String s)
    {
      if (pos<endpos && s.indexOf(source.at(pos))>=0) return fail("not [" + s + "]");
      else return true;
    }

  //-------------------------------------------------------------------
  //  Execute expression [a-z]
  //-------------------------------------------------------------------
  protected boolean nextIn(char a, char z)
    {
      if (pos<endpos && source.at(pos)>=a && source.at(pos)<=z)
        return consume(1);
      else return fail("[" + a + "-" + z + "]");
    }

  //-------------------------------------------------------------------
  //  Execute expression &[a-z]
  //-------------------------------------------------------------------
  protected boolean aheadIn(char a, char z)
    {
      if (pos<endpos && source.at(pos)>=a && source.at(pos)<=z)
        return true;
      else return fail("[" + a + "-" + z + "]");
    }

  //-------------------------------------------------------------------
  //  Execute expression ![a-z]
  //-------------------------------------------------------------------
  protected boolean aheadNotIn(char a, char z)
    {
      if (pos<endpos && source.at(pos)>=a && source.at(pos)<=z)
        return fail("not [" + a + "-" + z + "]");
      else return true;
    }

  //-------------------------------------------------------------------
  //  Execute expression _
  //-------------------------------------------------------------------
  protected boolean next()
    {
      if (pos<endpos) return consume(1);
      else return fail("any character");
    }

  //-------------------------------------------------------------------
  //  Execute expression &_
  //-------------------------------------------------------------------
  protected boolean ahead()
    {
      if (pos<endpos) return true;
      else return fail("any character");
    }

  //-------------------------------------------------------------------
  //  Execute expression !_
  //-------------------------------------------------------------------
  protected boolean aheadNot()
    {
      if (pos<endpos) return fail("end of text");
      else return true;
    }
  //-------------------------------------------------------------------
  //  Consume terminal
  //-------------------------------------------------------------------
  private boolean consume(int n)
    {
      Phrase p = new Phrase("","",pos,source);
      pos += n;
      p.end = pos;
      current.rhs.add(p);
      current.end = pos;
      return true;
    }

  //-------------------------------------------------------------------
  //  Fail
  //-------------------------------------------------------------------
  private boolean fail(String msg)
    {
      current.hwmUpd(msg,pos);
      return false;
    }

  //=====================================================================
  //
  //  Compiler stack operations
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Push Phrase on compile stack, returning previous top of stack.
  //-------------------------------------------------------------------
  protected Phrase push(Phrase p)
    {
      Phrase top = current;
      p.parent = top;
      current = p;
      return top;
    }

  //-------------------------------------------------------------------
  //  Pop Phrase from compile stack
  //-------------------------------------------------------------------
  protected Phrase pop()
    {
      Phrase p = current;
      current = p.parent;
      p.parent = null;
      return p;
    }

  //=====================================================================
  //
  //  Compute ascent semantics
  //
  //=====================================================================
  protected void ascentSemantics()
    {
      Phrase E = ascents.peek();
      Phrase Erhs = descend(current,E).elementAt(0);
      E.end = Erhs.end;
      E.value = Erhs.value;
    }

  //-------------------------------------------------------------------
  //  Descends the ascent stack from $P to E
  //  and identifies the text consumed by P.
  //  Returns a Vector of Phrases representing parts of that text,
  //  each part carrying its semantic value.
  //-------------------------------------------------------------------
  protected Vector<Phrase> descend(Phrase $P,Phrase E)
    {
      Phrase $R = $P.parent;

      //---------------------------------------------------------------
      // $P is lowest in the ascent stack and represents $S.
      // Its rhs represents the text consumed by seed S.
      //---------------------------------------------------------------
      if ($R==E)
        return $P.rhs;

      //---------------------------------------------------------------
      // $P is not lowest in the ascent stack.
      //---------------------------------------------------------------
      else
      {
        // $R represents the first element of P,
        // and the rhs of $P represents the rest.
        // Construct Vector p representing all of P.
        Vector<Phrase> p = new Vector<Phrase>(descend($R,E));
        p.addAll($P.rhs);

        // If P is not a Rule (no semantic actions)
        // return the constructed Vector.
        if ($P.semAct==null) return p;

        // Otherwise apply semantic action to p.
        else
        {
          // Imitate lhs + rhs on top of stack
          push(new Phrase($P.diag,$P.diag,p.firstElement().start,source));
          current.rhs = p;
          current.end = p.lastElement().end;

          // Apply semantic action and discard rhs
          $P.semAct.exec();
          current.rhs = null;

          // Return result: a single-element Vector
          Vector<Phrase> result = new Vector<Phrase>();
          result.add(pop()); // Add and remove from stack
          return result;
        }
      }
    }
}



