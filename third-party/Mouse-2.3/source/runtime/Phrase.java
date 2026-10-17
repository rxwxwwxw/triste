//=========================================================================
//
//  Part of PEG parser generator Mouse.
//
//  Copyright (C) 2009, 2011, 2015, 2017, 2020
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
//    Version 1.7
//      Extracted from Parser Base and made into a separate class,
//      replacing the interface 'Phrase'.
//      This required an additional variable 'source' and constructor
//      parameter to set it.
//      Error history is renamed to 'high-water mark', with methods
//      'hwmClear', 'hwmSet', 'hwmUpd' and 'hwmUpdFrom' accessible
//      only from package 'runtime'.
//      All methods previously accessible via interface 'Phrase'
//      are preserved and public, plus new method 'errAdd'.
//      Added 'defAct' to keep deferred actions, and methods
//      'actAdd', 'actClear', and 'actExec' for handling them.
//    Version 1.9.2
//      Mark that error history was recently cleared.
//    Version 2.0
//      Added field 'createdAt' and method 'hwmCopyFrom'.
//      Added method 'asString' to aid debugging.
//    Version 2.1
//      Added 'semAct'.
//    Version 2.2
//      Use 'mouse.utility.Convert' instead of local code.
//    Version 2.3
//      Previous change was a bug. Convert is not in mouse.runtime:
//      code copied back into 'addToPrint'.
//      Use 'FuncVV' instead of 'Deferred'.
//      Clean up of fix from Version 1.9.2.
//
//=========================================================================

package mouse.runtime;

import mouse.runtime.Source;
import java.util.Vector;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  Phrase
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

public class Phrase
{
  //===================================================================
  //
  //  Data
  //
  //===================================================================
  //-----------------------------------------------------------------
  //  For Rules and Subs: name of creating expression.
  //  For Terminals: empty string. Accessed by 'isA' and 'isTerm'.
  //-----------------------------------------------------------------
  String name;

  //-----------------------------------------------------------------
  //  For Rules and Subs: identification in error messages.
  //  For Terminals: null. Their parser methods create identification.
  //-----------------------------------------------------------------
  String diag;

  //-----------------------------------------------------------------
  //  Text represented by this Phrase: start and end positions
  //  in input represented by 'source'.
  //-----------------------------------------------------------------
  int start;
  int end;
  Source source;

  //-----------------------------------------------------------------
  //  Input position where this Phrase was created.
  //  (Ascent procedures create Phrases with 'start'
  //  different from current input position.)
  //-----------------------------------------------------------------
  int createdAt;

  //-----------------------------------------------------------------
  //  Right-hand side.
  //-----------------------------------------------------------------
  Vector<Phrase> rhs = new Vector<Phrase>(10,10);

  //-----------------------------------------------------------------
  //  Syntactic value.
  //-----------------------------------------------------------------
  Object value = null;

  //-----------------------------------------------------------------
  //  Parent in parser stack.
  //-----------------------------------------------------------------
  Phrase parent = null;

  //-----------------------------------------------------------------
  //  Success indicator. The Memo and Test versions save also
  //  Phrases for expressions that failed. They are saved with
  //  success = false and end = start.
  //-----------------------------------------------------------------
  boolean success;

  //-----------------------------------------------------------------
  //  Information about the failure farthest down in the text
  //  encountered while processing this Phrase.
  //  It can only be failure of a rule, predicate, or terminal.
  //  - 'hwm' (high water mark) is the position of the failure,
  //     or -1 if there was none.
  //  - 'hwmExp' identifies the expression(s) that failed at 'hwm'.
  //     There may be several such expressions if 'hwm' was reached
  //     on several attempts. The expressions are identified
  //     by their diagnostic names.
  //-----------------------------------------------------------------
  int hwm = -1;
  Vector<String> hwmExp = new Vector<String>();

  //-----------------------------------------------------------------
  //  Deferred actions
  //-----------------------------------------------------------------
  Vector<FuncVV> defAct = new Vector<FuncVV>();

  //-----------------------------------------------------------------
  //  Semantic action in recursive ascent
  //-----------------------------------------------------------------
  FuncVV semAct = null;

  //===================================================================
  //
  //  Constructor
  //
  //===================================================================
  protected Phrase(String name,String diag,int start,Source source)
    {
      this.name = name;
      this.diag = diag;
      this.start = start;
      this.end = start;
      this.createdAt = start;
      this.source = source;
    }

  //===================================================================
  //
  //  Methods called from semantic procedures
  //
  //===================================================================
  //-----------------------------------------------------------------
  //  Set value
  //-----------------------------------------------------------------
  public void put(Object o)
    { value = o; }

  //-----------------------------------------------------------------
  //  Get value
  //-----------------------------------------------------------------
  public Object get()
    { return value; }

  //-----------------------------------------------------------------
  //  Get text
  //-----------------------------------------------------------------
  public String text()
    { return source.at(start,end); }

  //-------------------------------------------------------------------
  //  Get i-th character of text
  //-------------------------------------------------------------------
  public char charAt(int i)
    { return source.at(start+i); }

  //-----------------------------------------------------------------
  //  Is text empty?
  //-----------------------------------------------------------------
  public boolean isEmpty()
    { return start==end; }

  //-------------------------------------------------------------------
  //  Get name of rule that created this Phrase.
  //-------------------------------------------------------------------
  public String rule()
    { return name; }

  //-------------------------------------------------------------------
  //  Was this Phrase created by rule 'rule'?
  //-------------------------------------------------------------------
  public boolean isA(String rule)
    { return name.equals(rule); }

  //-------------------------------------------------------------------
  //  Was this Phrase created by a terminal?
  //-------------------------------------------------------------------
  public boolean isTerm()
    { return name.isEmpty(); }

  //-----------------------------------------------------------------
  //  Describe position of i-th character of the Phrase in source text.
  //-----------------------------------------------------------------
  public String where(int i)
    { return source.where(start+i); }

  //-----------------------------------------------------------------
  //  Get error message
  //-----------------------------------------------------------------
  public String errMsg()
    {
      if (hwm<0) return "";
      return source.where(hwm) + ":" + listErr();
    }

  //-----------------------------------------------------------------
  //  Clear error information
  //-----------------------------------------------------------------
  public void errClear()
    { hwmClear(); }

  //-----------------------------------------------------------------
  //  Add information about 'expr' failing at the i-th character
  //  of this Phrase.
  //-----------------------------------------------------------------
  public void errAdd(String expr, int i)
    { hwmSet(expr,start+i); }

  //-----------------------------------------------------------------
  //  Clear deferred actions
  //-----------------------------------------------------------------
  public void actClear()
    { defAct.clear(); }

  //-----------------------------------------------------------------
  //  Add deferred action
  //-----------------------------------------------------------------
  public void actAdd(FuncVV a)
    { defAct.add(a); }

  //-----------------------------------------------------------------
  //  Execute deferred actions
  //-----------------------------------------------------------------
  public void actExec()
    {
      for (FuncVV a: defAct) a.exec();
      defAct.clear();
    }

  //-----------------------------------------------------------------
  //  Return string that represents this object.
  //  Used for diagnostics.
  //-----------------------------------------------------------------
  public String asString()
    {
      String result = name+" "+start+"-"+end+" text="+source.at(start,end)+" v="+value+" msg="+errMsg();
      if (rhs==null || rhs.isEmpty()) return result;
      result += " rhs: ";
      for (Phrase p: rhs)
      {
      //  result += p.name;
          if (p==this){result += "\n   !"+p.name; break;}
          result += "\n    "+ p.asString();
      }
      return result;
    }

  //===================================================================
  //
  //  Metods called from Parser
  //
  //===================================================================
  //-----------------------------------------------------------------
  //  Clear high-water mark.
  //  Setting -2 as hwm marks the use of 'hwmClear'.
  //-----------------------------------------------------------------
  void hwmClear()
    {
      hwmExp.clear();
      hwm = -2;
    }

  //-----------------------------------------------------------------
  //  Set fresh mark ('what' failed 'where'), discarding any previous.
  //-----------------------------------------------------------------
  void hwmSet(String what, int where)
    {
      hwmExp.clear();
      hwmExp.add(what);
      hwm = where;
    }

  //-----------------------------------------------------------------
  //  Add info about 'what' failing at position 'where'.
  //-----------------------------------------------------------------
  void hwmUpd(String what,int where)
    {
      if (hwm>where) return;   // If 'where' older: forget
      if (hwm<where)           // If 'where' newer: replace
      {
        hwmExp.clear();
        hwm = where;
      }
                               // If same position: add
      hwmExp.add(what);
    }

  //-----------------------------------------------------------------
  //  Update high-water mark with that from Phrase 'p'.
  //-----------------------------------------------------------------
  void hwmUpdFrom(Phrase p)
    {
      if (hwm>p.hwm) return;   // If p's info older: forget
      if (hwm<p.hwm)           // If p's info  newer: replace
      {
        hwmExp.clear();
        hwm = p.hwm;
      }
      hwmExp.addAll(p.hwmExp); // If same position: add
    }

  //-----------------------------------------------------------------
  //  Copy high-water mark with that from Phrase 'p'.
  //-----------------------------------------------------------------
  void hwmCopyFrom(Phrase p)
    {
      hwmExp.clear();
      hwmExp.addAll(p.hwmExp);
      hwm = p.hwm;
    }

  //===================================================================
  //
  //  Private methods
  //
  //===================================================================
  //-----------------------------------------------------------------
  //  Translate high-water mark into error message.
  //-----------------------------------------------------------------
  private String listErr()
    {
      StringBuilder one = new StringBuilder();
      StringBuilder two = new StringBuilder();
      Vector<String> done = new Vector<String>();
      for (String s: hwmExp)
      {
        if (done.contains(s)) continue;
        done.add(s);
        if (s.startsWith("not "))
          addToPrint(" or " + s.substring(4),two);
        else
          addToPrint(" or " + s,one);
      }

      if (one.length()>0)
      {
        if (two.length()==0)
          return " expected " + one.toString().substring(4);
        else
          return " expected " + one.toString().substring(4) +
                 "; not expected " + two.toString().substring(4);
      }
      else
        return " not expected " + two.toString().substring(4);
    }

  //-----------------------------------------------------------------
  //  Convert string to printable and append to StringBuilder.
  //  Copied from mouse.utility.Convert.
  //-----------------------------------------------------------------
  private void addToPrint(String s, StringBuilder sb)
    {
      for (int i=0;i<s.length();i++)
        sb.append(toRange(s.charAt(i),32,255));
    }

  //-----------------------------------------------------------------
  //  Copied from mouse.utility.Convert.
  //-----------------------------------------------------------------
  private static String toRange(char c,int low,int high)
    {
      switch(c)
      {
        case '\b': return("\\b");
        case '\f': return("\\f");
        case '\n': return("\\n");
        case '\r': return("\\r");
        case '\t': return("\\t");
        default:
          if (c<low || c>high)
          {
            String u = "000" + Integer.toHexString(c);
            return("\\u" + u.substring(u.length()-4,u.length()));
          }
          else return Character.toString(c);
      }
    }
}
