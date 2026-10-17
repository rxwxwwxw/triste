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
//      Replaced relation 'follow' by 'Expr.firstTailTerms'.
//      Removed abstract method 'NUL'.
//      Changed for the redesigned Tail class.
//    Version 1.9.2
//      Corrected bug in 'expand'.
//    Version 2.2
//      Use 'TailStrand' instead of 'Tail.Strand'.
//    Version 2.3
//      Use 'Tail.expand' instad of 'Tail.expandUnique'.
//      Use 'Tail.Strand.next' instead of Tail.Strand.follow'.
//      Use 'TailStrand' instead of 'Tail_Strand'.
//      Moved 'firstTailTerms' to Tail as 'firstTerms'.
//      Method 'expand' returns a Vector of Line_Items.
//
//=========================================================================

package mouse.explorer;

import java.util.BitSet;
import java.util.Vector;
import mouse.peg.Expr;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  Item_Tail
//
//-------------------------------------------------------------------------
//
//  Item shown on Explorer line, representing 'Tail(e)'.
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

class Item_Tail extends Item
{
  //=====================================================================
  //
  //  Constructors.
  //
  //=====================================================================
  Item_Tail(Expr e)
    { this.e = e; }

  //=====================================================================
  //
  //  Implementation of Item's abstract methods.
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Return a copy of this Item.
  //-------------------------------------------------------------------
  Item_Tail copy()
    { return new Item_Tail(e); }

  //-------------------------------------------------------------------
  //  Return String representation of this Item.
  //-------------------------------------------------------------------
  String asString()
    { return("Tail("+e.name+")"); }

  //-------------------------------------------------------------------
  //  Return first terminals of 'Tail(e)'.
  //-------------------------------------------------------------------
  BitSet terms()
    { return e.tail.firstTerms; }

  //-------------------------------------------------------------------
  //  Expand this Item.
  //  Returns a Vector of Line_Items for strands of the expanded Tail.
  //-------------------------------------------------------------------
  Vector<Line_Items> expand()
    {
      Vector<Line_Items> result = new Vector<Line_Items>();
      for (TailStrand strand: e.tail)
      {
        Line_Items line = new Line_Items(strand.follow);
        if (strand.tail!=null) line.addTail(strand.tail);
        result.add(line);
      }
      return result;
    }
}
