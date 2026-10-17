//=========================================================================
//
//  Part of PEG parser generator Mouse.
//
//  Copyright (C) 2017, 2020 by Roman R. Redziejowski (www.romanredz.se).
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
//    Version 1.9
//      Created.
//    Version 2.2
//      The class made public.
//      Use 'PEG.Expr': 'toShort' instead of 'simple'.
//    Version 2.3
//      Added methods 'left' and 'right',
//      returning two parts of the conflict as Lines of Items.
//
//=========================================================================

package mouse.explorer;

import mouse.peg.Expr;
import java.util.Comparator;
import java.util.Vector;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  Class Conflict
//
//-------------------------------------------------------------------------
//
//  Represents an LL1 violation in expression 'expr'.
//  It can be one of these:
//
//  (1) A pair of alternatives 'arg1', 'arg2' of a Choice
//      expression 'expr' where 'arg1' and 'arg2 Tail(expr)'
//      have non-disjoint first terminals.
//  (2) The argument 'arg1' of Plus, Star, or Query expression 'expr'
//      that has non-disjoint first terminal(s) with 'Tail(expr)'.
//  (3) The argument 'arg1' of PlusPlus or StarPlus expression 'expr'
//      that has non-disjoint first terminal(s) with 'arg2 Tail(expr)'.
//
//  In each case, the non-disjoint pairs of terminals are represented
//  by TermPair objects listed in 'termPairs'.
//
//  In case (2), 'arg2' is null.
//  The 'Tail(expr)' does not follow 'arg2' that has 'end' attribute.
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

public class Conflict
{
  //------------------------------------------------------------------
  //  Data.
  //------------------------------------------------------------------
  public Expr expr;             // Expression with the conflict
  public Expr left;             // Left-hand side of conflict
  public Expr right;            // Right-hand side of conflict
  public TermPair[] termPairs;  // Conflicting terminal pairs

  //------------------------------------------------------------------
  //  Constructor.
  //------------------------------------------------------------------
  public Conflict(Expr left,Expr right,Expr expr,Vector<TermPair> tp)
    {
      this.left  = left;
      this.right = right;
      this.expr  = expr;
      this.termPairs = tp.toArray(new TermPair[0]);
    }

  //------------------------------------------------------------------
  //  Return two parts of the conflict as Lines of Items.
  //------------------------------------------------------------------
  Line_Items left()
    { return new Line_Items(left); }

  Line_Items right()
    {
      if (right==null) return new Line_Items().addTail(expr);
      if (right.end)   return new Line_Items(right);
      return new Line_Items(right).addTail(expr);
    }

  //------------------------------------------------------------------
  //  Present both parts of the conflict as a String.
  //------------------------------------------------------------------
  public String asString()
    {
      if (right==null)
        return left.toShort() + "  <==>  Tail(" + expr.name + ")";
      else
        return left.toShort() + "  <==>  " + right.toShort() + (right.end? "" : " Tail(" + expr.name + ")");
    }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Comparator for sorting by name of 'expr'.
  //  (Conflicts are presented in the aphabetic order of expr.name.)
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class Compare implements Comparator<Conflict>
  {
    public int compare(Conflict e1, Conflict e2)
      { return (e1.expr.name).compareTo(e2.expr.name); }
  }
}
