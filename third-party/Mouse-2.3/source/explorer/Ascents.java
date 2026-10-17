//=========================================================================
//
//  Part of PEG parser generator Mouse.
//
//  Copyright (C) 2021 by Roman R. Redziejowski (www.romanredz.se).
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
//    Version 2.3
//      Moved out from explorer.Dual.
//
//=========================================================================

package mouse.explorer;

import mouse.peg.Expr;
import mouse.peg.PEG;
import mouse.peg.RecClass;
import java.util.Vector;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  Class Ascents
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

public class Ascents
{
  public static void create()
   {
     for (RecClass rc: PEG.recClasses)
      {
        createEntries(rc);
        for (Expr e: rc.members)
          createAscent(e);
      }
   }

  //=====================================================================
  //
  //  Create entries for recursion class 'rc'.
  //
  //---------------------------------------------------------------------
  //
  //  If the class has single entry 'e', create its object structure
  //  named 'e'.
  //  If the class has multiple entries, they would have identical
  //  object structures. To avoid duplication, construct single object
  //  structure for one of the entries with name '$$rc' where 'rc'
  //  is name of the recursion class.
  //  For each entry 'e' construct Choice expression with name 'e'
  //  and single argument '$$rc'.
  //
  //=====================================================================
  private static void createEntries(RecClass rc)
    {
      Expr e0 = rc.entries.elementAt(0);

      //---------------------------------------------------------------
      //  Class 'rc' has single entry.
      //---------------------------------------------------------------
      if (rc.entries.size()==1)
         createEntry(e0,e0.name);

      //---------------------------------------------------------------
      //  Class 'rc' has multiple entries.
      //---------------------------------------------------------------
      else
      {
        // Create common entry structure
        createEntry(e0,"$$"+rc.name);

        // Create individual entries to common structure
        for (Expr e: rc.entries)
        {
          Expr[] args = new Expr[1];
          args[0] = new Expr.Ref("$$"+rc.name); // Reference to '$$rc'
          Expr result = new Expr.Choice(args);  // Choice expression
          result.name = e.name;                 // Name is the entry name
          result.isNamed = true;                // Is named
          result.bind = 4;                      // Referenced only by name
          result.recClass = rc;
          Dual.entries.add(result);                  // Add to list of entries
          Dual.names.put(result.name,result);        // Add to name table
          Dual.I++;                                  // Count
        }
      }
    }

  //=====================================================================
  //
  //  Create entry expression for entry 'e' with name 'name'.
  //
  //---------------------------------------------------------------------
  //
  //  Creates object structure corresponding to entry e of class rc
  //
  //      e = s-1 pre(s_1) / ... / s-n pre(s-n)
  //
  //  where s-i are seeds of rc and pre(s-i) is the expression
  //
  //      $x-1 / ... / $x-m
  //
  //  where x-1 ... x-m are all exits of class rc containing s-i.
  //
  //=====================================================================
  private static void createEntry(Expr e,String name)
    {
      //---------------------------------------------------------------
      // Get recursion class of e. Check that e is its entry.
      //---------------------------------------------------------------
      RecClass rc = e.recClass;
      if (!rc.entries.contains(e)) throw new Error("SNOC");

      //---------------------------------------------------------------
      // The result will be Choice expression with argument for each seed.
      //---------------------------------------------------------------
      int nSeeds = rc.seeds.size();
      Expr[] eArgs = new Expr[nSeeds];

      //---------------------------------------------------------------
      // Build argument list.
      //---------------------------------------------------------------
      for (int i=0;i<rc.seeds.size();i++)
      {
        // Each argument is a two-argument Sequence.
        Expr[] sArgs = new Expr[2];
        Expr seed = rc.seeds.elementAt(i);
        sArgs[0] = Dual.copyExpr(seed);     // First arg: copy of seed
        sArgs[1] = createPre(seed,rc); // Second arg: pre(seed)
        Dual.subs.add(sArgs[1]);

        // Create the Sequence and add as argument of Choice.
        eArgs[i] = new Expr.Sequence(sArgs);
        eArgs[i].recClass = rc;
      }

      //---------------------------------------------------------------
      // Create the Choice
      //---------------------------------------------------------------
      Expr result = new Expr.Choice(eArgs);
        for (Expr arg: eArgs)
          Dual.subs.add(arg);

      //---------------------------------------------------------------
      // Return result
      //---------------------------------------------------------------
      result.name = name;              // Name is the entry name
      result.isNamed = true;           // Is named
      result.bind = 4;                 // Referenced only by name
      result.recClass = rc;
      Dual.entries.add(result);             // Add to list of entries
      Dual.names.put(result.name,result);   // Add to name table
      Dual.I++;                             // Count
    }

  //=====================================================================
  //
  //  Create ascent expression.
  //
  //---------------------------------------------------------------------
  //
  //  Builds object structure corresponding to ascent expression $e:
  //
  //        $e = rest(e) pre(e)
  //
  //  It is different for different sbclasses of Expr.
  //  They are handled by AscentVisitor.
  //
  //=====================================================================
  private static void createAscent(Expr e)
    {
      AscentVisitor ascentVisitor = new AscentVisitor();
      e.accept(ascentVisitor);
      Dual.A++;
    }

  //=====================================================================
  //
  //  Create Pre expression.
  //
  //---------------------------------------------------------------------
  //
  //  Builds object structure corresponding to expression pre(e).
  //
  //=====================================================================
  private static Expr createPre(Expr e,RecClass rc)
    {
      //---------------------------------------------------------------
      // Get expressions that have 'e' as first.
      //---------------------------------------------------------------
      Vector<Expr> pre = rc.haveAsFirst(e);

      //---------------------------------------------------------------
      // Their ascents are going to be args of resulting Choice
      //---------------------------------------------------------------
      int n = pre.size();
      Expr[] preArgs = new Expr[n];

      //---------------------------------------------------------------
      // All args are ascent expressions, that need not exist yet.
      // Represent them by Refs to be resolved later.
      //---------------------------------------------------------------
      for (int i=0;i<n;i++)
        preArgs[i] = new Expr.Ref('$' + pre.elementAt(i).name);

      //---------------------------------------------------------------
      // Create resulting Choice
      //---------------------------------------------------------------
      Expr.Choice choice = new Expr.Choice(preArgs);
      choice.recClass = rc;

      //---------------------------------------------------------------
      // If 'e' is an entry of 'rc', return Query with Choice as arg.
      //---------------------------------------------------------------
      if (rc.entries.contains(e))
      {
        Expr query = new Expr.Query(choice);
        Dual.subs.add(choice);
        query.recClass = rc;
        return query;
      }

      //---------------------------------------------------------------
      // Otherwise return Choice.
      //---------------------------------------------------------------
      return choice;
    }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  AscentVisitor - creates ascent expressions.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  static class AscentVisitor extends mouse.peg.Visitor
  {
    //-----------------------------------------------------------------
    //  Rule
    //-----------------------------------------------------------------
    public void visit(Expr.Rule expr)
      { doChoice(expr); }

    //-----------------------------------------------------------------
    //  Choice
    //-----------------------------------------------------------------
    public void visit(Expr.Choice expr)
      { doChoice(expr); }

    //-----------------------------------------------------------------
    //  Sequence
    //-----------------------------------------------------------------
    public void visit(Expr.Sequence expr)
      {
        int n = expr.args.length;
        Expr[] rest = new Expr[n];
        for (int i=1;i<n;i++)
          rest[i-1] = Dual.copyExpr(expr.args[i]);

        Expr pre = createPre(expr,expr.recClass);
        rest[n-1] = pre;
        Dual.subs.add(pre);
        Expr.Sequence ascent = new Expr.Sequence(rest);
        ascent.name = '$' + expr.name;
        ascent.isNamed = true;
        ascent.bind = 4;
        ascent.recClass = expr.recClass;
        Dual.ascents.add(ascent);
        Dual.names.put(ascent.name,ascent);
      }

    //-----------------------------------------------------------------
    //  Common for Rule and Choice
    //-----------------------------------------------------------------
    private void doChoice(Expr expr)
      {
        Expr ascent = createPre(expr,expr.recClass);
        ascent.name = '$' + expr.name;
        ascent.isNamed = true;
        ascent.bind = 4;
        ascent.recClass = expr.recClass;
        Dual.ascents.add(ascent);
        Dual.names.put(ascent.name,ascent);
      }

  }

}
