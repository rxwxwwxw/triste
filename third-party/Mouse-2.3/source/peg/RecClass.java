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
//    Use 'index' from 'PEG'.
//  Version 2.2
//    Allow seed to appear in many exits.
//    Use 'toShort' instead of 'toPrint' in messages.
//  Version 2.3
//    Show seeds in the order they are defined.
//
//=========================================================================

package mouse.peg;

import java.util.BitSet;
import java.util.HashSet;
import java.util.Vector;
import mouse.utility.BitIter;
import mouse.utility.BitMatrix;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  Class RecClass
//
//-------------------------------------------------------------------------
//
//  Represents left-recursion class.
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

public class RecClass

{
  //=====================================================================
  //
  //  Data.
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Name of the class - the name of Rule used in constructor.
  //-------------------------------------------------------------------
  public String name;

  //-------------------------------------------------------------------
  //  The class as set of indexes of members.
  //-------------------------------------------------------------------
  public BitSet memberIndex = new BitSet();

  //-------------------------------------------------------------------
  //  The class listed as Vector of members.
  //-------------------------------------------------------------------
  public Vector<Expr> members = new Vector<Expr>();

  //-------------------------------------------------------------------
  //  Lists of entries, exits, and seds.
  //-------------------------------------------------------------------
  public Vector<Expr> entries = new Vector<Expr>();
  public Vector<Expr> exits = new Vector<Expr>();
  public Vector<Expr> seeds = new Vector<Expr>();

  //=====================================================================
  //
  //  Constructor - creates RecClass object containing Rule 'rule'.
  //
  //=====================================================================
  public RecClass(Expr.Rule rule)
    {
      //---------------------------------------------------------------
      // The 'rule' should be left-recursive without recursion class.
      //---------------------------------------------------------------
      int r = rule.index;
      if (!Relations.First.at(r,r) || rule.recClass!=null)
        throw new Error("Incorrect call");

      //---------------------------------------------------------------
      // The class is named after 'rule'
      //---------------------------------------------------------------
      name = rule.name;

      //---------------------------------------------------------------
      //  Identify members of the class
      //---------------------------------------------------------------
      memberIndex = Relations.First.row(r);
      memberIndex.and(Relations.First.column(r));

      //---------------------------------------------------------------
      //  List members and mark their membership
      //---------------------------------------------------------------
      for (BitIter bit=new BitIter(memberIndex);bit.hasNext();)
       {
        int i = bit.next();
        members.add(PEG.index[i]);
        PEG.index[i].recClass = this;
      }

      //---------------------------------------------------------------
      //  Identify entries: members called from outside the class.
      //  Member with index 0 is assumed to be called on start.
      //---------------------------------------------------------------
      for (Expr member: members)
      {
        int i = member.index;
        BitSet callers = Relations.calls.column(i);
        callers.andNot(memberIndex);
        if (!callers.isEmpty() || i==0)
          entries.add(member);
      }

      //---------------------------------------------------------------
      //  Identify exits and seeds.
      //---------------------------------------------------------------
      MemberVisitor memberVisitor = new MemberVisitor();

      for (Expr member: members)
        member.accept(memberVisitor);

      memberVisitor = null;

    }

  //=====================================================================
  //
  //  Get expressions that have 'expr' as first.
  //
  //=====================================================================
  public Vector<Expr> haveAsFirst(Expr expr)
    {
      BitSet prec = Relations.first.column(expr.index);
      prec.and(memberIndex);
      Vector<Expr> result = new Vector<Expr>();
      for (BitIter bit=new BitIter(prec);bit.hasNext();)
      {
        int i = bit.next();
        result.add(PEG.index[i]);
      }
      return result;
    }

  //=====================================================================
  //
  //  Display members of the class.
  //
  //=====================================================================
  void show()
    {
      //---------------------------------------------------------------
      //  Show members of the class.
      //---------------------------------------------------------------
      System.out.println("\nRecursion class " + name + "\n  members: ");
      for (Expr member: members)
      {
        //-------------------------------------------------------------
        //  Show member indicating if it is entry or exit.
        //-------------------------------------------------------------
        System.out.print("    " + member.toShort());
        if (entries.contains(member))
           System.out.print(" (entry)");
        if (exits.contains(member))
           System.out.print(" (exit)");
        System.out.print("\n");
      }
      //---------------------------------------------------------------
      //  Show seeds of the class.
      //---------------------------------------------------------------
      System.out.println("  seeds: ");
      for (Expr seed: seeds)
      {
        //-------------------------------------------------------------
        //  Show seed with containing entry (entries).
        //-------------------------------------------------------------
        Vector<Expr> inExit = haveAsFirst(seed);
        String inexits = "";
        String sep = " ";
        for (Expr inexit: inExit)
        {
          inexits += (sep+ inexit.toShort());
          sep = ", ";
        }
        System.out.println("    " + seed.toShort() + " (in" + inexits + ")");
      }
    }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  MemberVisitor - identifies seeds and exits; detects unsupported.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  class MemberVisitor extends mouse.peg.Visitor
  {
    public void visit(Expr.Rule expr)     { getSeeds(expr,expr.args); }
    public void visit(Expr.Choice expr)   { getSeeds(expr,expr.args); }
    public void visit(Expr.And expr)      { notSupported(expr); }
    public void visit(Expr.Not expr)      { notSupported(expr); }
    public void visit(Expr.Plus expr)     { notSupported(expr); }
    public void visit(Expr.Star expr)     { notSupported(expr); }
    public void visit(Expr.Query expr)    { notSupported(expr); }
    public void visit(Expr.PlusPlus expr) { notSupported(expr); }
    public void visit(Expr.StarPlus expr) { notSupported(expr); }
    public void visit(Expr.Is expr)       { notSupported(expr); }
    public void visit(Expr.IsNot expr)    { notSupported(expr); }

    // Sequence can not be an exit.
    // Terminals are not recursive.

 //--------------------------------------------------------------------
 //  Identify seeds an exits.
 //--------------------------------------------------------------------
 private void getSeeds(Expr expr, Expr args[])
    {
      // One-argument recursive Rule or Choice is not an exit.
      if (args.length==1) return;

      // Check for args outside the class: they are seeds.
      boolean isExit = false;
      for (Expr arg: args)
      {
        if (arg.recClass!=RecClass.this) // arg is a seed
        {
          if (!seeds.contains(arg))      // If not already in list..
            seeds.add(arg);              // ..add
          isExit = true;                 // expr is an exit
        }
      }
      if (isExit) exits.add(expr);       // Add exit to list
    }

 //--------------------------------------------------------------------
 //  Indicate not supported.
 //--------------------------------------------------------------------
  private void notSupported(Expr expr)
    {
      System.out.println("Error: " + expr.toShort()
                         + " is not supported in left-recursion.");
      PEG.errors++;
    }
  }
}



