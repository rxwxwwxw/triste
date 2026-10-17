//=========================================================================
//
//  Part of PEG parser generator Mouse.
//
//  Copyright (C) 2017, 2020, 2021
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
//    Version 1.9
//      Created.
//    Version 1.9.1
//      Removed use of 'NUL' attribute of Expr.
//      Renamed 'Expr.first' to 'Expr.firstTerms'.
//    Version 2.2.
//      Use PEG.Expr and PEG.Visitor.
//      In 'expand': reset 'expanded' in the Visitor.
//      Added StarPlus and PlusPlus to the Visitor.
//      Modified 'asString', using 'toPrint'.
//    Version 2.3.
//      Method 'expand' returns Vector of Line_Items.
//
//=========================================================================

package mouse.explorer;

import java.util.BitSet;
import java.util.Vector;
import mouse.peg.Expr;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  class Item_Expr
//
//-------------------------------------------------------------------------
//
//  Item shown on an Explorer line, representing expression 'e'.
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

class Item_Expr extends Item
{
  //=====================================================================
  //
  //  Data.
  //
  //=====================================================================
  static ExpandVisitor expandVisitor = new ExpandVisitor();

  //=====================================================================
  //
  //  Constructor.
  //
  //=====================================================================
  Item_Expr(Expr e)
    { this.e = e; }

  //=====================================================================
  //
  //  Implementation of Item's abstract methods.
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Return a copy of this Item.
  //-------------------------------------------------------------------
  Item_Expr copy()
    { return new Item_Expr(e); }

  //-------------------------------------------------------------------
  //  Return String representation of this Item.
  //-------------------------------------------------------------------
  String asString()
    {
      if (e.isNamed) return e.name;
      if (e.bind==0)
        return("("+e.toPrint()+")");
      else
        return(e.toPrint());
    }

  //-------------------------------------------------------------------
  //  Return first terminals of 'e'.
  //-------------------------------------------------------------------
  BitSet terms()
    { return e.firstTerms; }

  //-------------------------------------------------------------------
  //  Expand this Item.
  //  Returns a Vector of Line_Items replacing the expanded expression,
  //  or null if there is no expansion.
  //-------------------------------------------------------------------
  Vector<Line_Items> expand()
    {
      expandVisitor.result = new Vector<Line_Items>();
      e.accept(expandVisitor);
      if (expandVisitor.result.isEmpty()) return null;
      return expandVisitor.result;
    }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Expand Visitor
  //
  //-------------------------------------------------------------------
  //
  //  Expands the visited Expression and places result in 'result'.
  //  'Colon' expressions are not expanded.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  static class ExpandVisitor extends mouse.peg.Visitor
  {
    Vector<Line_Items> result;

    //-----------------------------------------------------------------
    //  Choice.
    //-----------------------------------------------------------------
    public void visit(Expr.Choice e)
      {
        for (Expr arg: e.args)
          result.add(new Line_Items(arg));
      }

    //-----------------------------------------------------------------
    //  Sequence.
    //-----------------------------------------------------------------
    public void visit(Expr.Sequence e)
      {
        result.add(new Line_Items(e.args));
      }

    //-----------------------------------------------------------------
    //  Plus.
    //  e = aa* is replaced by a(aa*/empty) = ae/a.
    //-----------------------------------------------------------------
    public void visit(Expr.Plus e)
      {
        result.add(new Line_Items(e.arg,e));
        result.add(new Line_Items(e.arg));
      }

    //-----------------------------------------------------------------
    //  Star.
    //  e = a* is replaced by aa*/empty = ae/empty.
    //-----------------------------------------------------------------
    public void visit(Expr.Star e)
      {
        result.add(new Line_Items(e.arg,e));
        result.add(new Line_Items());
      }

    //-----------------------------------------------------------------
    //  Query.
    //  e = a? is replaced by a/empty.
    //-----------------------------------------------------------------
    public void visit(Expr.Query e)
      {
        result.add(new Line_Items(e.arg));
        result.add(new Line_Items());
      }

    //-----------------------------------------------------------------
    //  PlusPlus.
    //  e = aa*b = a(aa*/empty)b = aaa*b/b is replaced by ae/ab.
    //-----------------------------------------------------------------
    public void visit(Expr.PlusPlus e)
      {
        result.add(new Line_Items(e.arg1,e));
        result.add(new Line_Items(e.arg1,e.arg2));
      }

    //-----------------------------------------------------------------
    //  StarPlus.
    //  e = a*b = (aa*/empty)b = aa*b/b is replaced by ae/b.
    //-----------------------------------------------------------------
    public void visit(Expr.StarPlus e)
      {
        result.add(new Line_Items(e.arg1,e));
        result.add(new Line_Items(e.arg2));
      }
  }
}