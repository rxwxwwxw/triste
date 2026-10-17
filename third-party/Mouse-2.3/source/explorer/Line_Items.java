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
//      Removed use of 'Item.NUL'.
//      Replaced 'copy' by copy constructor.
//      Moved 'prefix' and 'strip' from Paragraph_Explorer.
//    Version 2.2
//      Corrected 'flattenSeq'.
//    Version 2.3
//      Two-argument constructor replaced by constructors with list
//      of expressions and method 'addTail'.
//      Method 'expand' returns Vector of Line_Items.
//      Redesigned 'expandSeq' renamed to 'flattenSeq'.
//
//=========================================================================

package mouse.explorer;

import java.util.BitSet;
import java.util.Vector;
import mouse.peg.Expr;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  Line_Items
//
//-------------------------------------------------------------------------
//
//  A sequence of Items.
//  The Explorer operation "strip" removes the first Item from the line.
//  The operation may be repeated several times. The removed Items are
//  displayed as a prefix followed by " -- ". The prefix is not regarded
//  as part of the ine and is not selectable.
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

class Line_Items extends Line
{
  //=====================================================================
  //
  //  Contents of the Line.
  //
  //=====================================================================
  Vector<Item> items = new Vector<Item>(); // The Items
  String prefix = "";                      // The stripped prefix

  //===================================================================
  //
  //  Constructing the Line.
  //
  //===================================================================
  //-------------------------------------------------------------------
  //  Construct empty line.
  //-------------------------------------------------------------------
  Line_Items() {}

  //-------------------------------------------------------------------
  //  Construct Line containing list of Exprs.
  //-------------------------------------------------------------------
  Line_Items(Expr ... exprs)
    {
      for (Expr e: exprs)
        addItem(new Item_Expr(e));
    }

  //-------------------------------------------------------------------
  //  Construct Line containing list of Exprs.
  //-------------------------------------------------------------------
  Line_Items(Vector<Expr> exprs)
    {
      for (Expr e: exprs)
        addItem(new Item_Expr(e));
    }

  //-------------------------------------------------------------------
  //  Add Tail at the end.
  //-------------------------------------------------------------------
  Line_Items addTail(Expr e)
    {
      items.add(new Item_Tail(e));
      return this;
    }

  //-------------------------------------------------------------------
  //  Deep copy.
  //-------------------------------------------------------------------
  Line_Items(Line_Items from)
    {
      for (Item item: from.items)
        items.add(item.copy());
      prefix = from.prefix;
    }

  //=====================================================================
  //
  //  Operations on collection of items.
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Get number of Items.
  //-------------------------------------------------------------------
  int nItems()
    { return items.size(); }

  //-------------------------------------------------------------------
  //  Get item at position 'i'.
  //-------------------------------------------------------------------
  Item item(int i)
    { return items.elementAt(i); }

  //-------------------------------------------------------------------
  //  Add 'item' at the end.
  //-------------------------------------------------------------------
  void addItem(Item item)
    { items.add(item); }

  //-------------------------------------------------------------------
  //  Insert 'item' at position 'i'.
  //-------------------------------------------------------------------
  void insertItem(int i, Item item)
    { items.add(i,item); }

  //-------------------------------------------------------------------
  //  Remove item at position 'i'.
  //-------------------------------------------------------------------
  void removeItem(int i)
    { items.remove(i); }

  //-------------------------------------------------------------------
  //  Replace item at position 'i' by 'item'.
  //-------------------------------------------------------------------
  void replaceItemBy(int i, Item item)
    {
      items.remove(i);
      items.add(i,item);
    }

  //-------------------------------------------------------------------
  //  Replace item at position 'i' by Items from 'exprList'.
  //-------------------------------------------------------------------
  void replaceItemBy(int i, Expr[] exprList)
    {
      items.remove(i);
      int j = i;
      for (Expr e: exprList)
      {
        items.add(j,new Item_Expr(e));
        j++;
      }
    }

  //=====================================================================
  //
  //  Return set of (indexes of) first terminals for expression
  //  represented by this Line.
  //
  //=====================================================================
  BitSet terms()
    {
      BitSet result = new BitSet();
      for (Item item: items)
      {
        result.or(item.terms());
        if (!item.e.nul || item.e.end) break;
      }
      return result;
    }

  //=====================================================================
  //
  //  Return String representation of this Line.
  //
  //=====================================================================
  String asString()
    {
      StringBuffer sb = new StringBuffer();
      for (Item it: items)
         sb.append(it.asString()+" ");
      return sb.toString();
    }

  //=====================================================================
  //
  //  Flatten sequences.
  //  An unnamed Item_Expr object representing Sequence would be shown
  //  by 'toPrint' as sequence of its arguments, giving false impression
  //  that they are clickable, while only the sequence as a whole is.
  //  Expand such sequence to a sequence of Item_Expr's.
  //
  //=====================================================================
  public Line_Items flattenSeq()
    {
      boolean more = true;
      // There may be nested sequences to flatten.
      // Repeat while something was done.
      while(more)
      {
        //  Check Items in the Line starting at the end because
        //  expansion will affect numbering of Items that follow it.
        for (int i=nItems()-1;i>=0;i--)
        {
          more = false;
          if (item(i) instanceof Item_Expr // Last item can be Item_Tail
              && item(i).e instanceof Expr.Sequence
              && !item(i).e.isNamed)
          {
            Expr.Sequence seq = (Expr.Sequence)item(i).e;
            replaceItemBy(i,seq.args);
            more = true;
          }
        }
      }
      return this;
    }

  //=====================================================================
  //
  //  Explorer actions.
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Expand the i-th item, returning an array of one or more lines.
  //  Return null if the item cannot be expanded.
  //-------------------------------------------------------------------
  Vector<Line_Items> expand(int i)
    {
      Vector<Line_Items> newLines = new Vector<Line_Items>();

      Vector<Line_Items> expItem = item(i).expand();
      if (expItem==null) return null;

      // For each row in expansion of the Item
      for (Line_Items row: expItem)
      {
        // Create new copy of this Line
        Line_Items newLine = new Line_Items(this);

        // In the copy, replace the item
        // by its expansion
        newLine.removeItem(i);
        int j = i;
        for (Item item: row.items)
        {
          newLine.insertItem(j,item);
          j++;
        }
        newLine.flattenSeq();  // Flatten any nested sequences
        newLines.add(newLine); // Add to result
      }
      return newLines;
    }

  //-------------------------------------------------------------------
  //  Strip.
  //-------------------------------------------------------------------
  void strip()
    {
      if (nItems()==0) return;
      prefix = prefix + item(0).asString() + " ";
      removeItem(0);
    }

  //=====================================================================
  //
  //  Implementation of Line's abstract methods.
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Append text represented by this Line to the image of
  //  display area provided as StringBuffer 'display'.
  //  Set 'start' and 'end' to the starting and ending offset
  //  of the text within the image.
  //  Each Item must provide a method 'writeTo' that appends
  //  the formatted Item text to the image of display area.
  //-------------------------------------------------------------------
  void writeTo(StringBuffer display)
    {
      if (prefix.length()>0)
        display.append(prefix + "-- "); // Nonempty prefix ends with " "
      start = display.length();
      for (Item item: items)
        item.writeTo(display);
      end = display.length();
      display.append("\n");
    }

  //-------------------------------------------------------------------
  //  If 'offset' falls within an Item belonging to this Line in the
  //  display area, return an Element object identifying the Item.
  //  Otherwise return null.
  //  Each Item must provide a method 'find' that checks if a given
  //  offset within the display is within that Item.
  //-------------------------------------------------------------------
  Element find(int offset)
    {
      if (offset<start || offset>=end) return null;
      for (int i=0;i<nItems();i++)
      {
        Element elem = item(i).find(offset);
        if (elem!=null)
        {
          elem.item = i;
          return elem;
        }
      }
      return null;
    }

}

