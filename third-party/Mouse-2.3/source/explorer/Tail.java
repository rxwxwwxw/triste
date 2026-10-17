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
//      Created
//    Version 1.9.1
//      Total redesign.
//    Version 1.9.2
//      Corrected comment in 'asString'.
//    Version 2.2
//      'Tail.Strand' made into a separate class 'Tail_Strand'.
//    Version 2.3
//      Major redesign.
//
//=========================================================================

package mouse.explorer;

import mouse.peg.Expr;
import java.util.BitSet;
import java.util.Vector;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  Class Tail
//
//-------------------------------------------------------------------------
//
//  Represents the set of input strings that may follow a successful call
//  to expression 'e'. It is a Vector of TailStrands, each representing
//  what may follow when 'e' is called from within expression 'E',
//  for all 'E' that contain 'e'.
//
//  The Tail of 'e' is empty if 'e' has the 'end' attribute.
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

public class Tail extends Vector<TailStrand>
{
  //=====================================================================
  //
  //  Data.
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Whose Tail it is.
  //-------------------------------------------------------------------
  Expr e;

  //-------------------------------------------------------------------
  //  First terminals.
  //-------------------------------------------------------------------
  BitSet firstTerms = new BitSet();

  //=====================================================================
  //
  //  Constructor.
  //
  //=====================================================================
  Tail(Expr e)
    { this.e = e; }

  //=====================================================================
  //
  //  Refine.
  //
  //=====================================================================
  void refine()
    {
      //---------------------------------------------------------------
      // Repeatedly expand tails of unnamed expressions.
      //---------------------------------------------------------------
      boolean more = true;
      while(more)
      {
        more = false;
        for (int i=this.size()-1;i>=0;i--)
        {
          TailStrand strand = elementAt(i);
          Expr E = strand.tail;
          if (E==null || E.isNamed) continue;

          for (TailStrand s: E.tail)
          {
            removeElementAt(i);
            add(new TailStrand(strand.follow,s.follow,s.tail));
            more = true;
          }
        }
      }

      //---------------------------------------------------------------
      // Remove duplicate strands.
      //---------------------------------------------------------------
      Vector<String> list = new Vector<String>();
      for (int i=this.size()-1;i>=0;i--)
      {
        String s = elementAt(i).asString();
        if (list.contains(s))
          removeElementAt(i);
        else
          list.add(s);
      }
    }

  //=====================================================================
  //
  //  Tail as String. Each strand is a separate line.
  //
  //=====================================================================
  public String asString()
    {
      StringBuffer sb = new StringBuffer();
      String nl = "";
      for (TailStrand strand: this)
      {
        sb.append(nl + strand.asString());
        nl = "\n";
      }
      return sb.toString();
    }

  //=====================================================================
  //
  //  Create tails for all expressions.
  //
  //---------------------------------------------------------------------
  //
  //  This method first creates empty tails for all expressions,
  //  then looks at each expression in turn and adds strands to tails
  //  of expressions called by it.
  //  It ends by computing first terminals of the created tails.
  //
  //=====================================================================
  public static void create()
    {
      //---------------------------------------------------------------
      // Create empty Tail objects for all expressions.
      //---------------------------------------------------------------
      for (Expr e: Dual.index)
        e.tail = new Tail(e);

      //---------------------------------------------------------------
      // Use tailVisitor to add TailStrand objects
      // to expressions called by the visited one.
      //---------------------------------------------------------------
      TailVisitor tailVisitor = new TailVisitor();
      for (Expr E: Dual.index)
        E.accept(tailVisitor);
      tailVisitor = null;

      //---------------------------------------------------------------
      //  Refine Tails.
      //---------------------------------------------------------------
      for (Expr e: Dual.index)
		e.tail.refine();

      //---------------------------------------------------------------
      //  Compute first terminals of Tails by iteration to fixpoint.
      //---------------------------------------------------------------
      int iter = 0;       // Number of steps
      int lastCount = 0;  // Last number of first terminals

      while(true)
      {
        int count = 0;      // Number of first terminals
        //-------------------------------------------------------------
        //  Consider each expression in the index.
        //-------------------------------------------------------------
        for (Expr e: Dual.index)
        {
          //-----------------------------------------------------------
          //  Update first terminals of all strands
          //  and update first terminals of tail.
          //-----------------------------------------------------------
          for (TailStrand strand: e.tail)
          {
            strand.firstTerms();
            e.tail.firstTerms.or(strand.firstTerms);
	      }

          //-----------------------------------------------------------
          //  Add up numbers of ones for all tails
          //-----------------------------------------------------------
          count += e.tail.firstTerms.cardinality();
        }

        //-----------------------------------------------------------
        //  Break iteration if no change.
        //-----------------------------------------------------------
        if (count==lastCount) break;

        //-----------------------------------------------------------
        //  To next step
        //-----------------------------------------------------------
        lastCount = count;
        iter++;
      }
      /*
      System.out.println(iter + " iterations for first tail terminals");

      for (Expr e: Dual.index)
		System.out.println("\nTail of "+e.toShort()+"\n"+e.tail.asString());
	  */
    }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  TailVisitor
  //
  //-----------------------------------------------------------------------
  //
  //  The visitor is used by static method 'create'.
  //  It visits the expression 'E' and adds TailStrand
  //  'follow(e,E) Tail(E)' to tail of each expression 'e' called by 'E'.
  //  No strand is created if 'e' has 'end' attribute.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  static class TailVisitor extends mouse.peg.Visitor
  {
    //-----------------------------------------------------------------
    //  Rule.
    //-----------------------------------------------------------------
    public void visit(Expr.Rule E)
      { throw new Error("Visiting Rule " + E.toShort()); }

    //-----------------------------------------------------------------
    //  Choice.
    //  The called expressions 'e' are the 'args'.
    //  For each of them 'follow(e,E)' is empty.
    //-----------------------------------------------------------------
    public void visit(Expr.Choice E)
      {
        for (Expr e: E.args)
          if (!e.end) e.tail.add(new TailStrand(E));
      }

    //-----------------------------------------------------------------
    //  Sequence.
    //  The called expressions 'e' are the 'args'. For each of them,
    //  'follow(e,E)' consists of 'args' that follow 'e'.
    //-----------------------------------------------------------------
    public void visit(Expr.Sequence E)
      {
        // This will be changed to null if the last 'arg' has 'end'.
        Expr tail = E;

        // Make a copy of 'args', stop at 'end' attribute.
        Vector<Expr> follow = new Vector<Expr>();
        for (int i=0;i<E.args.length;i++)
        {
          follow.add(E.args[i]);
          if (E.args[i].end)
          {
			tail = null;
			break;
	      }
        }

        // Create strands for all args,
        // with remaining ones as 'follow'.
        while(!follow.isEmpty())
        {
          Expr e = follow.remove(0);
          if (!e.end) e.tail.add(new TailStrand(follow,tail));
        }
      }

    //-----------------------------------------------------------------
    //  Plus.
    //  The called expression 'e' is the 'arg',
    //  and 'follow(e,E)' is 'e*', the same as 'E / empty'.
    //  Create two strands for these two cases.
    //  No strand if 'arg' has 'end'.
    //-----------------------------------------------------------------
    public void visit(Expr.Plus E)
      {
        Expr e = E.arg;
        if (e.end) return;
        e.tail.add(new TailStrand(E,E));
        e.tail.add(new TailStrand(E));
      }

    //-----------------------------------------------------------------
    //  Star.
    //  The called expression 'e' is the 'arg',
    //  and 'follow(e,E)' is 'e*', the same as 'E'.
    //  No strand if 'arg' has 'end'.
    //-----------------------------------------------------------------
    public void visit(Expr.Star E)
      {
        Expr e = E.arg;
        if (e.end) return;
        e.tail.add(new TailStrand(E,E));
      }

    //-----------------------------------------------------------------
    //  Query.
    //  The called expression 'e' is the 'arg',
    //  and 'follow(e,E)' is empty.
    //  No strand if 'arg' has 'end'.
    //-----------------------------------------------------------------
    public void visit(Expr.Query E)
      {
        Expr e = E.arg;
        if (e.end) return;
        e.tail.add(new TailStrand(E));
      }

    //-----------------------------------------------------------------
    //  PlusPlus.
    //  The called expressions are the 'args';
    //  'follow(arg1,E)' is 'arg1* arg2', the same as 'E / arg2'.
    //  'follow(arg2,E)' is empty.
    //  Always fails if 'arg1' has 'end'. No strand.
    //  No strand if 'arg2' has 'end'.
    //-----------------------------------------------------------------
    public void visit(Expr.PlusPlus E)
      {
        Expr a = E.arg1;
        Expr b = E.arg2;
        if (a.end || b.end) return;
        a.tail.add(new TailStrand(E,E));
        a.tail.add(new TailStrand(E,b));
        b.tail.add(new TailStrand(E));
      }

    //-----------------------------------------------------------------
    //  StarPlus.
    //  The called expressions are the 'args';
    //  'follow(arg1,E)' is 'arg1* arg2', the same as 'E'.
    //  'follow(arg2,E)' is empty.
    //  Always fails if 'arg1' has 'end'. No strand.
    //  No strand if 'arg2' has 'end'.
    //-----------------------------------------------------------------
    public void visit(Expr.StarPlus E)
      {
        Expr a = E.arg1;
        Expr b = E.arg2;
        if (a.end || b.end) return;
        a.tail.add(new TailStrand(E,E));
        b.tail.add(new TailStrand(E));
      }

    //-----------------------------------------------------------------
    //  Is.
    //  The called expressions are the 'args';
    //  'follow(arg1,E)' is empty. No strand if 'arg1' has end.
    //  No strand for 'arg2'.
    //-----------------------------------------------------------------
    public void visit(Expr.Is E)
      {
        Expr a = E.arg1;
        if (!a.end) a.tail.add(new TailStrand(E));
      }

    //-----------------------------------------------------------------
    //  IsNot
    //  The called expressions are the 'args';
    //  'follow(arg1,E)' is empty. No strand if 'arg1' has end.
    //  No strand for 'arg2'.
    //-----------------------------------------------------------------
    public void visit(Expr.IsNot E)
      {
        Expr a = E.arg1;
        if (!a.end) a.tail.add(new TailStrand(E));
      }
  }

}

