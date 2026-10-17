//=========================================================================
//
//  Part of PEG parser generator Mouse.
//
//  Copyright (C) 2010, 2011, 2020
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
//    Version 1.3
//      Created.
//    Version 1.4
//      Completed DiagVisitor with 'StarPlus' and 'PlusPlus'.
//    Version 1.9.3
//      Bug fix in DiagVisitor for Query:
//      Check for expr.expr.fal = false, not expr.expr.nul = true.
//    Version 2.0
//      The class is made static.
//      Partial redesign.
//      New diagnostics related to left-recursion.
//    Version 2.1
//      New code using 'index' from 'PEG'.
//    Version 2.2
//      Revised for changed design.
//
//=========================================================================

package mouse.peg;

import java.util.BitSet;
import java.util.Vector;
import mouse.utility.BitMatrix;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  Class Diagnose
//
//-------------------------------------------------------------------------
//
//  Contains methods to detect and write messages about:
//  - not well-formed expressions;
//  - cycles in the grammar;
//  - recursion classes without entry;
//  - recursive sequence expression with nullable first element;
//  - semantic actions not allowed for recursive rule;
//  - nullable argument of star and plus;
//  - expressions that never fail;
//  - superfluous '?' operators.
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

class Diagnose
{
  public static void apply()
    {
      //=================================================================
      //  Check that all expressions are well-formed.
      //=================================================================
      for (int i=0;i<PEG.N;i++)
      {
        Expr e = PEG.index[i];
        if (!e.def)
        {
          System.out.println("Error: " + e.toShort() + " is void.");
          PEG.errors++;
        }
      }

      //=================================================================
      //  Check for cycles.
      //=================================================================
      BitSet inCycles = new BitSet(PEG.R);

      // List Rules involved in cycles (cycle must contain a Rule)
      for (int i=0;i<PEG.R;i++)
        if (Relations.Clean.at(i,i)) inCycles.set(i);

      for (int i=0;i<PEG.R;i++)
      {
       // For a Rule involved in cyle
       if (inCycles.get(i))
        {
          // Complain
          System.out.println("Error: the grammar has cycle inolving "+ PEG.index[i].toShort() + ".");
          PEG.errors++;

          // Find other expressions in this cycle
          BitSet cycle = Relations.Clean.row(i);
          cycle.and(Relations.Clean.column(i));

          // Remove them from list
          inCycles.andNot(cycle);
        }
      }

      //=================================================================
      //
      //  Check recursion classes.
      //
      //=================================================================
      //---------------------------------------------------------------
      //  Class not used.
      //---------------------------------------------------------------
      for (RecClass rc: PEG.recClasses)
      {
        if (rc.entries.size()==0)
        { System.out.println("Info: recursion class of "  + rc.name + " is not used."); }
      }

      //=================================================================
      //
      //  Scan expressions using DiagVisitor.
      //
      //=================================================================
      DiagVisitor diagVisitor = new DiagVisitor();

      for (Expr e: PEG.index)
        e.accept(diagVisitor);
    }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  DiagVisitor - collects diagnostic information.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  static class DiagVisitor extends mouse.peg.Visitor
  {
    //-----------------------------------------------------------------
    //  Rule.
    //-----------------------------------------------------------------
    public void visit(Expr.Rule expr)
      {
        doChoice(expr,expr.args);
        if (expr.recClass==null) return;
        for (Action a: expr.onSucc)
        {
          if (a!=null && a.and)
          {
            System.out.println("Error: boolean action \"" + a.name
                 + "\" is not supported in recursive " + expr.toShort() + ".");
            PEG.errors++;
          }
        }
        for (Action a: expr.onFail)
        {
          if (a!=null)
          {
            System.out.println("Error: action on failure \"" + a.name
                 + "\" is not supported in recursive " + expr.toShort() + ".");
            PEG.errors++;
          }
        }
      }

    //-----------------------------------------------------------------
    //  Choice.
    //-----------------------------------------------------------------
    public void visit(Expr.Choice expr)
      { doChoice(expr,expr.args); }

    //-----------------------------------------------------------------
    //  Sequence.
    //-----------------------------------------------------------------
    public void visit(Expr.Sequence expr)
      {
        if (expr.recClass==null) return;
        if (expr.args[0].nul)
        {
          System.out.println("Error: left-recursive " + expr.toShort()
               + " starts with nullable expression.");
          PEG.errors++;
        }
      }

    //-----------------------------------------------------------------
    //  And predicate.
    //-----------------------------------------------------------------
    public void visit(Expr.And expr)
      {}

    //-----------------------------------------------------------------
    //  Not predicate.
    //-----------------------------------------------------------------
    public void visit(Expr.Not expr)
      {}

    //-----------------------------------------------------------------
    //  Plus.
    //-----------------------------------------------------------------
    public void visit(Expr.Plus expr)
      { if (expr.arg.nul) nullArg(expr); }

    //-----------------------------------------------------------------
    //  Star.
    //-----------------------------------------------------------------
    public void visit(Expr.Star expr)
      { if (expr.arg.nul) nullArg(expr); }

    //-----------------------------------------------------------------
    //  Query.
    //-----------------------------------------------------------------
    public void visit(Expr.Query expr)
      {
        if (!expr.arg.fal)
          System.out.println("Info: as " + expr.arg.toShort()
               + " never fails, '?' after it can be droppped.");
      }

    //-----------------------------------------------------------------
    //  StarPlus.
    //-----------------------------------------------------------------
    public void visit(Expr.StarPlus expr)
      { if (expr.arg1.nul) nullArg(expr); }

    //-----------------------------------------------------------------
    //  PlusPlus.
    //-----------------------------------------------------------------
    public void visit(Expr.PlusPlus expr)
      { if (expr.arg1.nul) nullArg(expr); }


    //-----------------------------------------------------------------
    //  Common for Rule and Choice.
    //-----------------------------------------------------------------
    private void doChoice(Expr expr, Expr[] args)
      {
        for (int i=0; i<args.length-1; i++)
          if (!args[i].fal)
            System.out.println("Info: " +args[i].toShort() + " in " + expr.toShort()
                 + " never fails and hides other alternative(s).");
      }

    //-----------------------------------------------------------------
    //  Nulable argument of star or plus.
    //-----------------------------------------------------------------
    private void nullArg(Expr expr)
      {
        System.out.println("Error: argument of " + expr.toShort() + " is nullable.");
        PEG.errors++;
      }
  }
}
