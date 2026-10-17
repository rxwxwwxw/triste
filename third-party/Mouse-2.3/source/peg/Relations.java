//=========================================================================
//
//  Part of PEG parser generator Mouse.
//
//  Copyright (C) 2020, 2021
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
//  Version 2.0
//    Created.
//  Version 2.1
//    'index' and its construction moved to 'PEG'.
//  Version 2.2
//    'open' renamed to 'clean'.
//  Version 2.3
//    'Is' and 'IsNot' included in MatrixVisitor.
//
//=========================================================================

package mouse.peg;

import java.util.BitSet;
import mouse.utility.BitMatrix;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  Relations
//
//-------------------------------------------------------------------------
//
//  Holds relations between Expressions in the PEG class.
//  The relations are represented by BitMatrix objects.
//  Each expression is assigned an index in the matrix.
//  The index is held in 'index' field of the Expression.
//  The array 'index' translates indices to the corresponding expressions.
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

public class Relations
{
  //=====================================================================
  //
  //  Data.
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Relation 'first'.
  //  first[i,j] = true means that expression i may call expression j
  //  at its starting position.
  //-------------------------------------------------------------------
  public static BitMatrix first;

  //-------------------------------------------------------------------
  //  Relation 'First'. The transitive closure of 'first'.
  //  First[i,j] = true means that expression i may call,
  //  directly or indirectly, expression j at its starting position.
  //  It is used to detect left recursion.
  //-------------------------------------------------------------------
  public static BitMatrix First;

  //-------------------------------------------------------------------
  //  Relation 'calls'.
  //  It is used to identify entry expressions of recursion class.
  //-------------------------------------------------------------------

  public static BitMatrix calls;

  //-------------------------------------------------------------------
  //  Relation 'clean'.
  //  clean[i,j] = true means that expression i may call expression j
  //  without consuming input.
  //  Computed only for expressions i that support left recursion.
  //-------------------------------------------------------------------
  public static BitMatrix clean;

  //-------------------------------------------------------------------
  //  Relation 'Clean'. The transitive closure of 'clean'.
  //  Clean[i,j] = true means that expression i may call,
  //  directly or indirectly, expression j  without consuming input.
  //  It is used to detect cycles in the grammar.
  //-------------------------------------------------------------------
  public static BitMatrix Clean;

  //=====================================================================
  //
  //  Compute relations.
  //
  //=====================================================================
  public static void compute()
  {
    //---------------------------------------------------------------
    //  Initialize matrices.
    //---------------------------------------------------------------
    int E = PEG.E;
    first = BitMatrix.empty(E);
    calls = BitMatrix.empty(E);
    clean = BitMatrix.empty(E);

    //---------------------------------------------------------------
    //  Construct matrices using MatrixVisitor.
    //---------------------------------------------------------------
    MatrixVisitor matrixVisitor = new MatrixVisitor();
    for (Expr e: PEG.index)
      e.accept(matrixVisitor);

    //---------------------------------------------------------------
    //  Compute closures.
    //---------------------------------------------------------------
    First = first.closure();
    Clean = clean.closure();
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Matrix Visitor - builds matrices.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  static class MatrixVisitor extends mouse.peg.Visitor
  {
    //-----------------------------------------------------------------
    //  Rule.
    //-----------------------------------------------------------------
    public void visit(Expr.Rule expr)
      { doChoice(expr,expr.args); }

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
        for (int i=0; i<expr.args.length; i++)
        {
          first.set(expr.index,expr.args[i].index);  // arg i is in first
          if (!expr.args[i].nul) break;              // rest is not first
        }

        for (Expr arg: expr.args)
          calls.set(expr.index,arg.index);

        for (int i=0; i<expr.args.length; i++)
        {
          if (expr.args[i].isTerm) continue;
          boolean alNul = true;
          for (int j=0; j<expr.args.length; j++)
            if (j!=i && !expr.args[j].nul)
              alNul = false;
          if (alNul) clean.set(expr.index,expr.args[i].index);
        }
      }

    //-----------------------------------------------------------------
    //  And predicate.
    //-----------------------------------------------------------------
    public void visit(Expr.And expr)
      {
        first.set(expr.index,expr.arg.index);
        calls.set(expr.index,expr.arg.index);
      }

    //-----------------------------------------------------------------
    //  Not predicate.
    //-----------------------------------------------------------------
    public void visit(Expr.Not expr)
      {
        first.set(expr.index,expr.arg.index);
        calls.set(expr.index,expr.arg.index);
      }

    //-----------------------------------------------------------------
    //  Plus.
    //-----------------------------------------------------------------
    public void visit(Expr.Plus expr)
      {
        first.set(expr.index,expr.arg.index);
        calls.set(expr.index,expr.arg.index);
      }

    //-----------------------------------------------------------------
    //  Star.
    //-----------------------------------------------------------------
    public void visit(Expr.Star expr)
      {
        first.set(expr.index,expr.arg.index);
        calls.set(expr.index,expr.arg.index);
      }

    //-----------------------------------------------------------------
    //  Query.
    //-----------------------------------------------------------------
    public void visit(Expr.Query expr)
      {
        first.set(expr.index,expr.arg.index);
        calls.set(expr.index,expr.arg.index);
      }

    //-----------------------------------------------------------------
    //  StarPlus.
    //-----------------------------------------------------------------
    public void visit(Expr.StarPlus expr)
      {
        first.set(expr.index,expr.arg1.index);
        first.set(expr.index,expr.arg2.index);
        calls.set(expr.index,expr.arg1.index);
        calls.set(expr.index,expr.arg2.index);
    }

    //-----------------------------------------------------------------
    //  PlusPlus.
    //-----------------------------------------------------------------
    public void visit(Expr.PlusPlus expr)
      {
        first.set(expr.index,expr.arg1.index);
        first.set(expr.index,expr.arg2.index);
        calls.set(expr.index,expr.arg1.index);
        calls.set(expr.index,expr.arg2.index);
   }

    //-----------------------------------------------------------------
    //  Is.
    //-----------------------------------------------------------------
    public void visit(Expr.Is expr)
      {
        first.set(expr.index,expr.arg1.index);
        first.set(expr.index,expr.arg2.index);
        calls.set(expr.index,expr.arg1.index);
        calls.set(expr.index,expr.arg2.index);
   }

    //-----------------------------------------------------------------
    //  IsNot.
    //-----------------------------------------------------------------
    public void visit(Expr.IsNot expr)
      {
        first.set(expr.index,expr.arg1.index);
        first.set(expr.index,expr.arg2.index);
        calls.set(expr.index,expr.arg1.index);
        calls.set(expr.index,expr.arg2.index);
   }

    //-----------------------------------------------------------------
    //  Common for Rule and Choice.
    //-----------------------------------------------------------------
    private void doChoice(Expr expr, Expr[] args)
      {
        for (Expr arg: args)
        {
          first.set(expr.index,arg.index);
          calls.set(expr.index,arg.index);
          clean.set(expr.index,arg.index);
        }
      }
  }


}