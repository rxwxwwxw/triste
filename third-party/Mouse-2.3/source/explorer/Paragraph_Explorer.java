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
//    Version 1.9.1
//      Moved handling of 'prefix' to Line_Items.
//    Version 2.2
//      Use 'Dual.Properties' instead of 'PEG.Relations'.
//    Version 2.3
//      Construct from given Line of Items and flatten this Line.
//      Use 'Terminals' to compute crashes.
//      Method 'expand' returns Vector instead of array
//      and removes duplicate lines.
//      Added 'asString'.
//
//=========================================================================

package mouse.explorer;

import java.util.BitSet;
import java.util.Vector;
import mouse.peg.Expr;
import mouse.utility.BitMatrix;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  Paragraph_Explorer
//
//-------------------------------------------------------------------------
//
//  The main paragraph of GUI_Explorer.
//  Contains lines of Items that represent expressions being manipulated.
//  It may be regarded to represent a Choice expressions with alternatives
//  represented by the lines, each line representing a Sequence expression.
//  The contents is changed by Explorer metods of both the paragraph
//  and its lines.
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

class Paragraph_Explorer extends Paragraph_Lines<Line_Items>
{
  //=====================================================================
  //
  //  Construct Paragraph with a given Line of Items.
  //
  //=====================================================================
  Paragraph_Explorer(Line_Items line)
    { addLine(line.flattenSeq()); }

  //=====================================================================
  //
  //  Return set of (indexes of) first terminals for all lines
  //  in this Paragraph.
  //
  //=====================================================================
  BitSet terms()
    {
      BitSet result = new BitSet();
      for (Line_Items line: lines)
        result.or(line.terms());
      return result;
    }

  //=====================================================================
  //
  //  Return String representation of this Paragraph.
  //
  //=====================================================================
  String asString()
    {
      StringBuffer sb = new StringBuffer();
      for (Line_Items line: lines)
         sb.append(line.asString()+"\n");
      return sb.toString();
    }

  //=====================================================================
  //
  //  Explorer methods.
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Expand i-th item in n-th line.
  //-------------------------------------------------------------------
  void expand(int i,int n)
    {
      Vector<Line_Items> expanded = line(n).expand(i);
      if (expanded==null) return;
      replaceLineBy(n,expanded);

      // Remove duplicate lines
      Vector<String> list = new Vector<String>();
      for (int j=lines.size();j>0;j--)
      {
        String s = lines.elementAt(j-1).asString();
        if (list.contains(s))
          lines.removeElementAt(j-1);
        else
          list.add(s);
      }
    }

  //-------------------------------------------------------------------
  //  Used in 'Filter':
  //  Remove from this Paragraph all lines with first terminals
  //  disjoint with all terminals in the set 'terms'.
  //-------------------------------------------------------------------
  void filterWith(BitSet terms)
  {
      for (int i=nLines()-1;i>=0;i--)
      {
        Line_Items line = line(i);
        BitMatrix coincidence = BitMatrix.product(terms,line.terms(),Dual.E);
        BitMatrix crashes = coincidence.and(Terminals.nonDisjoint);
        if (crashes.weight()==0) removeLine(i);
      }
  }

  //-------------------------------------------------------------------
  //  Used to process selected terminal pair:
  //  Remove from this Paragraph all lines that do not have 'term'
  //  in the set of first terminals.
  //-------------------------------------------------------------------
  void selectWithFirst(Expr term)
    {
      for (int i=nLines()-1;i>=0;i--)
      {
        Line_Items line = line(i);
        if (!line.terms().get(term.index)) removeLine(i);
      }
   }

  //-------------------------------------------------------------------
  //  Strip: remove first item from all lines.
  //  All lines must have identical first item. (Items are considered
  //  identical if the have the same string representation.)
  //-------------------------------------------------------------------
  void strip()
    {
      if (nLines()==0) return;

      // Check that all lines have identical first item.
      // Do nothing and return if not.
      Line_Items firstLine = line(0);
      if (firstLine.nItems()==0) return;
      String firstItem = firstLine.item(0).asString();
      for (int i=1;i<nLines();i++)
      {
        Line_Items line = line(i);
        if (line.nItems()==0) return;
        if (!line.item(0).asString().equals(firstItem)) return;
      }

      // Strip all lines
      for (Line_Items line: lines)
        line.strip();
    }
}

