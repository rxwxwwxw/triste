//=========================================================================
//
//  Part of PEG parser generator Mouse.
//
//  Copyright (C) 2009, 2010, 2011, 2013, 2014, 2015, 2020
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
//    Version 1.1
//      Created.
//    Version 1.3
//      In error trace added name of the Phrase owning error info.
//      Added c.diag to arguments of begin in saved and savedInner.
//      In error trace changed current.name to current.diag.
//      Renamed 'startpos' to 'endpos' in tracing.
//    Version 1.4
//      Added methods to implement ^[s].
//    Version 1.5
//      Revised methods for ^[s] and ^[c].
//    Version 1.6
//      Removed code allowing m=0 (is now allowed in superclass).
//    Version 1.7
//      Removed method 'setMemo' that overrided 'setMemo' from the
//      superclass ParserMemo. This interfered with setting of the -m
//      from TestParser, meaning TestParser was always run with
//      the default value -m1.
//      Removed 'cashSize', which is no longer referenced.
//      It was, in fact, never used.
//      Replaced the separate services for predicates by 'acceptPred'
//      and 'rejectPred'.
//    Version 2.0
//      Added service methods for ascent procedures that override
//      methods from ParserBase.
//      New methods 'traceInit', 'traceComplete', and 'showStack'.
//      Added 'called at' in 'traceAccept' and 'traceReject'.
//    Version 2.1
//      Changed meaning of 'beginAsc' and 'endAsc'.
//      Deleted 'beginSeed', acceptAsc', 'rejectAsc', 'completeRule',
//      'completeInner', 'completeSeed'.
//      Added 'begin' and 'ascentSemantics' to override
//      methods from ParserBase.
//
//=========================================================================

package mouse.runtime;

import java.util.BitSet;
import java.util.Vector;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  ParserTest
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

public class ParserTest extends ParserMemo
{
  //-------------------------------------------------------------------
  //  Trace switches.
  //-------------------------------------------------------------------
  public boolean traceRules;        // Trace Rules
  public boolean traceInner;        // Trace inner expressions
  public boolean traceAsc;          // Trace ascent procedures
  public boolean traceError;        // Trace error info

  //-------------------------------------------------------------------
  //  Constructor
  //-------------------------------------------------------------------
  protected ParserTest()
    {}

  //-------------------------------------------------------------------
  //  Set trace
  //-------------------------------------------------------------------
  public void setTrace(String trace)
    {
      super.setTrace(trace);
      traceRules = trace.indexOf('r')>=0;
      traceInner = trace.indexOf('i')>=0;
      traceAsc   = trace.indexOf('a')>=0;
      traceError = trace.indexOf('e')>=0;
    }

  //-------------------------------------------------------------------
  //  Access to cache list
  //-------------------------------------------------------------------
  public Cache[] caches()
    { return (Cache[])caches; }

  //-------------------------------------------------------------------
  //  Write trace
  //-------------------------------------------------------------------
  void trace(String s)
    { System.out.println(s); }

  //=====================================================================
  //
  //  Service methods called from parsing procedures.
  //  Override methods in ParserMemo to provide trace and statistics.
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  If saved result found, use it, otherwise begin new procedure.
  //  Version for Rule.
  //-------------------------------------------------------------------
  protected boolean saved(String name, String diag, Cache c)
    {
      traceInit(c,traceRules);
      reuse = c.find();
      if (reuse!=null)
      {
        c.reuse++;
        if (traceRules) trace("REUSE " + (reuse.success? "succ " : "fail "));
        return true;
      }

      begin(name,diag);
      c.save(current);
      if (c.prevpos.get(pos)) c.rescan++;
      else c.prevpos.set(pos);
      return false;
    }

   protected boolean saved(String name, Cache c)
    { return saved(name,name,c); }

  //-------------------------------------------------------------------
  //  If saved result found, use it, otherwise begin new procedure.
  //  Version for Inner.
  //-------------------------------------------------------------------
  protected boolean savedInner(String name, String diag, Cache c)
    {
      traceInit(c,traceInner);
      reuse = c.find();
      if (reuse!=null)
      {
        c.reuse++;
        if (traceInner) trace("REUSE " + (reuse.success? "succ " : "fail "));
        return true;
      }

      begin(name,diag);
      c.save(current);
      if (c.prevpos.get(pos)) c.rescan++;
      else c.prevpos.set(pos);
      return false;
    }

  //=====================================================================
  //
  //  Service methods called from parsing procedures.
  //  Override methods in ParserBase to provide trace and statistics.
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Initialize processing of a nonterminal.
  //-------------------------------------------------------------------
  protected void begin(String name,String diag,Cache c)
    {
      traceInit(c,traceRules || traceInner);
      super.begin(name,diag);
    }

  //-------------------------------------------------------------------
  //  Accept Rule
  //-------------------------------------------------------------------
  protected boolean accept(Cache c)
    {
      traceAccept(c,traceRules);
      super.accept();
      return true;
    }

  //-------------------------------------------------------------------
  //  Accept Inner
  //-------------------------------------------------------------------
  protected boolean acceptInner(Cache c)
    {
      traceAccept(c,traceInner);
      super.acceptInner();
      return true;
    }

  //-------------------------------------------------------------------
  //  Accept Predicate
  //-------------------------------------------------------------------
  protected boolean acceptPred(Cache c)
    {
      traceAccept(c,traceInner);
      super.acceptPred();
      return true;
    }

  //-------------------------------------------------------------------
  //  Reject Rule
  //-------------------------------------------------------------------
  protected boolean reject(Cache c)
    {
      int endpos = pos;
      super.reject();
      traceReject(c,traceRules,endpos);
      return false;
    }

  //-------------------------------------------------------------------
  //  Reject Inner
  //-------------------------------------------------------------------
  protected boolean rejectInner(Cache c)
    {
      int endpos = pos;
      super.rejectInner();
      traceReject(c,traceInner,endpos);
      return false;
    }

  //-------------------------------------------------------------------
  //  Reject Predicate
  //-------------------------------------------------------------------
  protected boolean rejectPred(Cache c)
    {
      int endpos = pos;
      super.rejectPred();
      traceReject(c,traceInner,endpos);
      return false;
    }

  //=====================================================================
  //
  //  Service methods called from ascent procedures
  //  Override methods in ParserBase to provide trace and statistics.
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Begin ascent.
  //-------------------------------------------------------------------
  protected void beginAsc()
    {
      if (traceAsc) trace(source.where(pos) + " ------ plant " + current.name);
      super.beginAsc();
    }

  //-------------------------------------------------------------------
  //  End ascent
  //-------------------------------------------------------------------
  protected void endAsc()
    {
      if (traceAsc) trace(source.where(pos) + " ------ unplant " + current.name);
      super.endAsc();
    }

  //-------------------------------------------------------------------
  //  ascentSemantics
  //-------------------------------------------------------------------
  protected void ascentSemantics()
    {
      // If requested, show stack built by the ascent
      if (traceAsc)
      {
        Phrase E = ascents.peek();
        Phrase p = current;
        trace("------ " + E.name + " top");
        while(true)
        {
          trace(p.asString());
          if (p==E) break;
          p = p.parent;
        }
        trace("------ " + E.name + " bottom");
      }
      super.ascentSemantics();
    }

  //=====================================================================
  //
  //  Parsing methods for terminals.
  //  Override methods in ParserBase to provide trace and statistics.
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Execute expression 'c'
  //-------------------------------------------------------------------
  protected boolean next(char ch,Cache c)
    {
      int endpos = pos;
      boolean succ = super.next(ch);
      return traceTerm(endpos,succ,c);
    }

  //-------------------------------------------------------------------
  //  Execute expression ^'c'
  //-------------------------------------------------------------------
  protected boolean nextNot(char ch,Cache c)
    {
      int endpos = pos;
      boolean succ = super.nextNot(ch);
      return traceTerm(endpos,succ,c);
    }

  //-------------------------------------------------------------------
  //  Execute expression &'c', !^'c'
  //-------------------------------------------------------------------
  protected boolean ahead(char ch,Cache c)
    {
      int endpos = pos;
      boolean succ = super.ahead(ch);
      return traceTerm(endpos,succ,c);
    }

  protected boolean aheadNotNot(char ch,Cache c)
    { return ahead(ch,c); }

  //-------------------------------------------------------------------
  //  Execute expression !'c', &^'c'
  //-------------------------------------------------------------------
  protected boolean aheadNot(char ch,Cache c)
    {
      int endpos = pos;
      boolean succ = super.aheadNot(ch);
      return traceTerm(endpos,succ,c);
    }

  //-------------------------------------------------------------------
  //  Execute expression "s"
  //-------------------------------------------------------------------
  protected boolean next(String s,Cache c)
    {
      int endpos = pos;
      boolean succ = super.next(s);
      return traceTerm(endpos,succ,c);
    }

  //-------------------------------------------------------------------
  //  Execute expression &"s"
  //-------------------------------------------------------------------
  protected boolean ahead(String s,Cache c)
    {
      int endpos = pos;
      boolean succ = super.ahead(s);
      return traceTerm(endpos,succ,c);
    }

  //-------------------------------------------------------------------
  //  Execute expression !"s"
  //-------------------------------------------------------------------
  protected boolean aheadNot(String s,Cache c)
    {
      int endpos = pos;
      boolean succ = super.aheadNot(s);
      return traceTerm(endpos,succ,c);
    }

  //-------------------------------------------------------------------
  //  Execute expression [s]
  //-------------------------------------------------------------------
  protected boolean nextIn(String s,Cache c)
    {
      int endpos = pos;
      boolean succ = super.nextIn(s);
      return traceTerm(endpos,succ,c);
    }

  //-------------------------------------------------------------------
  //  Execute expression ^[s]
  //-------------------------------------------------------------------
  protected boolean nextNotIn(String s,Cache c)
    {
      int endpos = pos;
      boolean succ = super.nextNotIn(s);
      return traceTerm(endpos,succ,c);
    }

  //-------------------------------------------------------------------
  //  Execute expression &[s], !^[s]
  //-------------------------------------------------------------------
  protected boolean aheadIn(String s,Cache c)
    {
      int endpos = pos;
      boolean succ = super.aheadIn(s);
      return traceTerm(endpos,succ,c);
    }

  protected boolean aheadNotNotIn(String s,Cache c)
    { return aheadIn(s,c); }

  //-------------------------------------------------------------------
  //  Execute expression ![s], &^[s]
  //-------------------------------------------------------------------
  protected boolean aheadNotIn(String s,Cache c)
    {
      int endpos = pos;
      boolean succ = super.aheadNotIn(s);
      return traceTerm(endpos,succ,c);
    }

  //-------------------------------------------------------------------
  //  Execute expression [a-z]
  //-------------------------------------------------------------------
  protected boolean nextIn(char a, char z, Cache c)
    {
      int endpos = pos;
      boolean succ = super.nextIn(a,z);
      return traceTerm(endpos,succ,c);
    }

  //-------------------------------------------------------------------
  //  Execute expression &[a-z]
  //-------------------------------------------------------------------
  protected boolean aheadIn(char a, char z, Cache c)
    {
      int endpos = pos;
      boolean succ = super.aheadIn(a,z);
      return traceTerm(endpos,succ,c);
    }

  //-------------------------------------------------------------------
  //  Execute expression ![a-z]
  //-------------------------------------------------------------------
  protected boolean aheadNotIn(char a, char z, Cache c)
    {
      int endpos = pos;
      boolean succ = super.aheadNotIn(a,z);
      return traceTerm(endpos,succ,c);
    }

  //-------------------------------------------------------------------
  //  Execute expression _
  //-------------------------------------------------------------------
  protected boolean next(Cache c)
    {
      int endpos = pos;
      boolean succ = super.next();
      return traceTerm(endpos,succ,c);
    }

  //-------------------------------------------------------------------
  //  Execute expression &_
  //-------------------------------------------------------------------
  protected boolean ahead(Cache c)
    {
      int endpos = pos;
      boolean succ = super.ahead();
      return traceTerm(endpos,succ,c);
    }

  //-------------------------------------------------------------------
  //  Execute expression !_
  //-------------------------------------------------------------------
  protected boolean aheadNot(Cache c)
    {
      int endpos = pos;
      boolean succ = super.aheadNot();
      return traceTerm(endpos,succ,c);
    }

  //=====================================================================
  //
  //  Tracing.
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Trace init.
  //-------------------------------------------------------------------
  private void traceInit(Cache c, boolean cond)
    {
      if (cond)
      {
        trace(source.where(pos) + ": INIT " + c.name);
        if (traceError) trace(current.diag + "  --" + current.errMsg());
      }
      c.calls++;
    }

  //-------------------------------------------------------------------
  //  Trace accept.
  //-------------------------------------------------------------------
  private void traceAccept(Cache c, boolean cond)
    {
      if (cond)
      {
        trace(source.where(pos) + ": ACCEPT " + c.name
              + " --- called at " + source.where(current.createdAt));
        if (traceError) trace(current.diag + "  --" + current.errMsg());
      }
      c.succ++;
    }

  //-------------------------------------------------------------------
  //  Trace reject.
  //  This is preceded by call to 'reject' method and 'endpos'
  //  is input position before that call.
  //-------------------------------------------------------------------
  private void traceReject(Cache c, boolean cond, int endpos)
    {
      if (cond)
      {
        trace(source.where(endpos) + ": REJECT " + c.name
              + " --- called at " + source.where(current.createdAt));
        if (traceError) trace(current.diag + "  --" + current.errMsg());
      }
      if (pos==endpos) c.fail++; // No backtrack
      else                       // Backtrack
      {
        int b = endpos-pos;
        c.back++;
        c.totback += b;
        if (b>c.maxback)
        {
          c.maxback = b;
          c.maxbpos = pos;
        }
      }
    }

  //-------------------------------------------------------------------
  //  Trace completed.
  //-------------------------------------------------------------------
  private void traceComplete(String R, boolean cond)
    {
      if (cond)
        trace(source.where(endpos) + ": COMPL " + R);
    }

  //-------------------------------------------------------------------
  //  Trace terminal.
  //-------------------------------------------------------------------
  private boolean traceTerm(int endpos, boolean succ, Cache c)
    {
      c.calls++;
      if (c.prevpos.get(endpos)) c.rescan++;
      else c.prevpos.set(endpos);
      if (succ) { c.succ++; return true; }
      else { c.fail++; return false; }
    }

  //-------------------------------------------------------------------
  //  Show compile stack.
  //-------------------------------------------------------------------
  private void showStack()
    {
      System.out.println("----------");
      Phrase top = current;
      while (top.parent!=null)
      {
        System.out.println(top.asString());
        top = top.parent;
      }
      System.out.println("----------");
    }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Cache - extends ParserMemo.Cache with repository for statistics
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public class Cache extends ParserMemo.Cache
  {
    public String name; // name to appear in statistics
    public int calls  ; // Total number of calls
    public int rescan ; // How many were rescans without reuse
    public int reuse  ; // How many were rescans with reuse
    public int succ   ; // How many resulted in success
    public int fail   ; // How many resulted in failure, no backtrack
    public int back   ; // How many resulted in backtrack
    public int totback; // Accumulated amount of backtrack
    public int maxback; // Maximum length of backtrack
    public int maxbpos; // Position of naximal backtrack
    BitSet prevpos    ; // Scan history

    //-----------------------------------------------------------------
    //  Constructor.
    //-----------------------------------------------------------------
    public Cache(String name)
      {
        super();
        this.name = name ;
      }

    //-----------------------------------------------------------------
    //  Constructor.
    //-----------------------------------------------------------------
    void reset()
      {
        super.reset();
        calls   = 0;
        rescan  = 0;
        reuse   = 0;
        succ    = 0;
        fail    = 0;
        back    = 0;
        totback = 0;
        maxback = 0;
        maxbpos = 0;
        prevpos = new BitSet(60000);
      }
  }
}



