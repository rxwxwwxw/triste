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
//    Version 2.3.
//      Split from 'Properties'.
//      Added 'SigmaStar' to 'TrmProcessor'.
//      Added sparate processing for 'Is' and 'IsNot'.
//      Uses Java 16 version of 'instanceof'.
//
//=========================================================================

package mouse.explorer;

import java.util.BitSet;
import java.util.Vector;
import mouse.peg.Expr;
import mouse.peg.Visitor;
import mouse.utility.BitMatrix;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  Terminals
//
//-------------------------------------------------------------------------
//
//  Constructs and holds information about disjoint Terminals.
//  Expressions e1 and e2 are 'disjoint' if no word in language of e1
//  is a prefix of word in language of e2 and vice-versa.
//  'Colon' expressions e1:e2 and e1:!e2 where e2 is a String
//  or String list are regarded as terminals.
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

public class Terminals
{
  //-------------------------------------------------------------------
  //  Relation disjoint.
  //  disjoint[i,j] = true means that expressions
  //  with indexes i,j are checked to be disjoint.
  //  nonDisjoint[i,j] = true means they may be not disjoint.
  //-------------------------------------------------------------------
  public static BitMatrix disjoint;
  public static BitMatrix nonDisjoint;

  //-------------------------------------------------------------------
  //  Shorthands.
  //  Terminals have indexes from N to E-1.
  //  'Colon' expressions have indexes from N1 to N-1.
  //-------------------------------------------------------------------
  private static Expr[] index = Dual.index;
  private static int E = Dual.E;
  private static int N = Dual.N;
  private static int N1 = N-Dual.C;

  //=====================================================================
  //
  //  Compute.
  //
  //=====================================================================
  public static void compute()
    {
      //---------------------------------------------------------------
      //  Compute 'disjoint' for Terminals.
      //---------------------------------------------------------------
      disjoint = BitMatrix.empty(E);

      TerminalVisitor terminalVisitor = new TerminalVisitor();
      for (int i=N;i<E;i++)
        index[i].accept(terminalVisitor);
      terminalVisitor = null;

      //---------------------------------------------------------------
      //  Compute 'nonDisjoint' for Terminals.
      //  It is used in the next step via method 'disjoint'.
      //---------------------------------------------------------------
      nonDisjoint = disjoint.not();

      //---------------------------------------------------------------
      // Compute 'disjoint' elements for 'colon' expressions.
      //---------------------------------------------------------------
      IsVisitor isVisitor = new IsVisitor();
      for (int i=N1;i<N;i++)
        index[i].accept(isVisitor);
      isVisitor = null;

      //---------------------------------------------------------------
      // Compute 'nonDisjoint'.
      //---------------------------------------------------------------
      nonDisjoint = disjoint.not();

      /* Trace
      System.out.println("\nCONFLICTS WITH");

      for (int i=N1;i<E;i++)
      {
        Expr  e = index[i];
        BitSet nD = nonDisjoint.row(i);
        nD.clear(0,N1);
        System.out.println(i + " " + e.toShort() + " " +  nD);
      }
      */
   }

  //=====================================================================
  //
  //  Compute collisions between two sets of 'Terminals'.
  //
  //--------------------------------------------------------------------
  //
  //  Given two sets of expression, A and B, identified by their indexes.
  //  Identify pairs (i,j) where i is from A and j from B that are not
  //  checked as disjoint. These pairs are representes by BitMatrix
  //  'collisions' as collisions[i,j] = true.
  //
  //=====================================================================
   public static BitMatrix collisions(BitSet A,BitSet B)
     {
       BitMatrix coincidence = BitMatrix.product(A,B,E);
       return coincidence.and(nonDisjoint);
     }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Private procedures used in Visitors
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //-------------------------------------------------------------------
  //  Set elments [x,y] and [y,x] of 'disjoint' to true.
  //-------------------------------------------------------------------
  private static void setDisjoint(Expr x, Expr y)
    {
      disjoint.set(x.index,y.index);
      disjoint.set(y.index,x.index);
    }

  //-------------------------------------------------------------------
  //  Return true if first terminals of e1, e2 are disjoint.
  //-------------------------------------------------------------------
  private static boolean disjoint(Expr e1,Expr e2)
    {
      BitMatrix collisions = collisions(e1.firstTerms,e2.firstTerms);
      return collisions.weight()==0;
    }

  //-------------------------------------------------------------------
  //  Return list of Strings represented by a 'String list' expression.
  //-------------------------------------------------------------------
  private static Vector<String> stringList(Expr expr)
    {
      Vector<String> result = new  Vector<String>();

      if (expr instanceof Expr.Choice e)
        for (Expr arg: e.args)
          result.addAll(stringList(arg));

      else if (expr instanceof Expr.StringLit e)
        result.add(e.s);

      return result;
    }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  TerminalVisitor - builds matrix 'disjoint' for Terminals.
  //
  //-----------------------------------------------------------------------
  //
  //  The visitor is invoked for all Terminals in the order of indices.
  //  When invoked for Terminal with index 'i' it checks that Terminal
  //  against all Terminals with higher indices. It was already checked
  //  by previous calls against Terminals with lower indices.
  //  It is obviously not disjoint with itself.
  //  The Terminals of class Any are not disjoint with anything,
  //  so they are not checked.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  static class TerminalVisitor extends Visitor
  {
    //-----------------------------------------------------------------
    //  StringLit.
    //-----------------------------------------------------------------
    public void visit(Expr.StringLit x)
    {
      int i = x.index;
      for (int j=i+1;j<E;j++)
      {
        if      (index[j] instanceof Expr.StringLit str) check(x,str);
        else if (index[j] instanceof Expr.CharClass cla) check(x,cla);
        else if (index[j] instanceof Expr.Range rng)     check(x,rng);
      }
    }

    //-----------------------------------------------------------------
    //  CharClass.
    //-----------------------------------------------------------------
    public void visit(Expr.CharClass x)
    {
      int i = x.index;
      for (int j=i+1;j<E;j++)
      {
        if      (index[j] instanceof Expr.StringLit str) check(str,x);
        else if (index[j] instanceof Expr.CharClass cla) check(x,cla);
        else if (index[j] instanceof Expr.Range rng)     check(x,rng);
      }
    }

    //-----------------------------------------------------------------
    //  Range.
    //-----------------------------------------------------------------
    public void visit(Expr.Range x)
    {
      int i = x.index;
      for (int j=i+1;j<E;j++)
      {
        if      (index[j] instanceof Expr.StringLit str) check(str,x);
        else if (index[j] instanceof Expr.CharClass cla) check(cla,x);
        else if (index[j] instanceof Expr.Range rng)     check(x,rng);
      }
    }

    //-----------------------------------------------------------------
    //  End.
    //-----------------------------------------------------------------
    public void visit(Expr.End x)
    {
      for (Expr y: Dual.terms)
        setDisjoint(x,y);
    }

    //=================================================================
    //
    //  Checks for disjointness
    //
    //=================================================================
    //-----------------------------------------------------------------
    //  String - String
    //-----------------------------------------------------------------
    private void check(Expr.StringLit x, Expr.StringLit y)
      {
        if (!x.s.startsWith(y.s) && !y.s.startsWith(x.s))
          setDisjoint(x,y);
      }

    //-----------------------------------------------------------------
    //  String - Class
    //-----------------------------------------------------------------
    private void check(Expr.StringLit x, Expr.CharClass y)
      {
        if (y.s.indexOf(x.s.charAt(0))<0) // First of x not in y
        { if (!y.hat) setDisjoint(x,y);}
        else                              // First of x in y
        { if (y.hat) setDisjoint(x,y);}
      }

    //-----------------------------------------------------------------
    //  String - Range
    //-----------------------------------------------------------------
    private void check(Expr.StringLit x, Expr.Range y)
      {
        char c = x.s.charAt(0);
        if (c<y.a || c>y.z) setDisjoint(x,y);
      }

    //-----------------------------------------------------------------
    //  Class - Class
    //-----------------------------------------------------------------
    private void check(Expr.CharClass x, Expr.CharClass y)
      {
        if ( (!x.hat && !y.hat && disjoint(x.s,y.s))
          || (x.hat && !y.hat && contains(x.s,y.s))
          || (!x.hat && y.hat && contains(y.s,x.s)))
          setDisjoint(x,y);
        // If both x and y have ^, they are disjoint only if they
        // together contain the whole character set.
      }

    //-----------------------------------------------------------------
    //  Class - Range
    //-----------------------------------------------------------------
    private void check(Expr.CharClass x, Expr.Range y)
      {
        for (char c=y.a;c<=y.z;c++)
          if (x.s.indexOf(c)>=0) return;
        setDisjoint(x,y);
      }

    //-----------------------------------------------------------------
    //  Range - Range
    //-----------------------------------------------------------------
    private void check(Expr.Range x, Expr.Range y)
      {
        if (x.z<y.a || y.z<x.a)
          setDisjoint(x,y);
      }

    //-----------------------------------------------------------------
    //  Set x,y disjoint:
    //  all elements of class x disjoint with all in class y.
    //-----------------------------------------------------------------
    private void setDisjoint(Expr x, Expr y)
      {
        disjoint.set(x.index,y.index);
        disjoint.set(y.index,x.index);
      }

    //-----------------------------------------------------------------
    //  Do 'x' and 'y' have no common letters?
    //-----------------------------------------------------------------
    private boolean disjoint(String x, String y)
      {
        for (int k=0;k<y.length();k++)
          if (x.indexOf(y.charAt(k))>=0) return false;
        return true;
      }

    //-----------------------------------------------------------------
    //  Does 'x' contain all letters from 'y'?
    //-----------------------------------------------------------------
    private boolean contains(String x, String y)
      {
        for (int k=0;k<y.length();k++)
          if (x.indexOf(y.charAt(k))<0) return false;
        return true;
      }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  IsVisitor - completes matrix 'disjoint' wth 'colon' expressions.
  //
  //-----------------------------------------------------------------------
  //
  //  The visitor is invoked for expressions in the order of indices.
  //  When invoked for expression with index 'i' it checks that expression
  //  against all expressions with higher indices. It was already checked
  //  by previous calls against expressions with lower indices.
  //  It is obviously not disjoint with itself.
  //  When this Visitor is used, 'nonDisjoint' matrix that is used
  //  by 'disjoint' method is already computed for Terminals.
  //  The 'colon' expressions are assumed to be not nested.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  static class IsVisitor extends Visitor
  {
    //-----------------------------------------------------------------
    //  Is.
    //-----------------------------------------------------------------
    public void visit(Expr.Is x)
    {
      int i = x.index;
      for (int j=i+1;j<E;j++)
      {
        if      (index[j] instanceof Expr.Is is)     check(x,is);    //is,is
        else if (index[j] instanceof Expr.IsNot isn) check(x,isn);   //is,isnot
        else if (index[j].isTerm)           checkTerm(x,index[j]);   //is,term
      }
    }

    //-----------------------------------------------------------------
    //  IsNot.
    //-----------------------------------------------------------------
    public void visit(Expr.IsNot x)
    {
      int i = x.index;
      for (int j=i+1;j<E;j++)
      {
        if      (index[j] instanceof Expr.Is is)     check(is,x);    //is,isnot
        else if (index[j] instanceof Expr.IsNot isn) check(x,isn);   //isnot,isnot
        else if (index[j].isTerm)           checkTerm(x,index[j]);   //isnot,term
      }
    }

    //=================================================================
    //
    //  Checks for disjointness
    //
    //=================================================================
    //-----------------------------------------------------------------
    //  Is - Is
    //  x = arg1:arg2  and y = ag1:arg2
    //  We consider x and y disjoint if their first or second
    //  arguments are disjoint.
    //  Otherwise, we consider x and y disjoint only if:
    // - their first arguments are identical
    // - their second argumants are string lists
    // - these string lists are disjoint.
    //-----------------------------------------------------------------
    private void check(Expr.Is x, Expr.Is y)
      {
        if (disjoint(x.arg1,y.arg1) || disjoint(x.arg2,y.arg2))
        { setDisjoint(x,y); return; }

        if (!x.arg1.asString.equals(y.arg1.asString)) return;
        Vector<String> slix = stringList(x.arg2);
        Vector<String> sliy = stringList(y.arg2);
        if (slix.isEmpty() || sliy.isEmpty()) return;
        for (String s: slix)
          if (sliy.contains(s)) return;
        for (String s: sliy)
          if (slix.contains(s)) return;
        setDisjoint(x,y);
      }

    //-----------------------------------------------------------------
    //  Is - IsNot
    //  x = arg1:arg2  and y = ag1!:arg2
    //  We consider x and y disjoint if their first argments are.
    //  Otherwise, we consider x and y disjoint only if:
    // - their first arguments are identical
    // - their second argumants are string lists
    // - the string list of x is subset of string list of y.
    //-----------------------------------------------------------------
    private void check(Expr.Is x, Expr.IsNot y)
      {
        if (disjoint(x.arg1,y.arg1) || disjoint(x.arg2,y.arg2))
        { setDisjoint(x,y); return; }

        if (!x.arg1.asString.equals(y.arg1.asString)) return;
        Vector<String> slix = stringList(x.arg2);
        Vector<String> sliy = stringList(y.arg2);
        if (slix.isEmpty() || sliy.isEmpty()) return;
        if (!sliy.containsAll(slix)) return;
        setDisjoint(x,y);
      }

    //-----------------------------------------------------------------
    //  IsNot - IsNot
    //  x = arg1!:arg2  and y = ag1!:arg2
    //  We consider x and y disjoint if their first argments are.
    //-----------------------------------------------------------------
    private void check(Expr.IsNot x, Expr.IsNot y)
      {
        if (disjoint(x.arg1,y.arg1) || disjoint(x.arg2,y.arg2))
          setDisjoint(x,y);
      }

    //-----------------------------------------------------------------
    //  Is - Terminal
    //  x = arg1:arg2  and T
    //  We consider x and T disjoint if its first and second argments are.
    //-----------------------------------------------------------------
    private void checkTerm(Expr.Is x, Expr T)
      {
        if (disjoint(x.arg1,T) || disjoint(x.arg2,T))
          setDisjoint(x,T);
	  }

    //-----------------------------------------------------------------
    //  IsNot - Terminal
    //  x = arg1:arg2  and T
    //  We consider x and T disjoint if its first argments is.
    //-----------------------------------------------------------------
    private void checkTerm(Expr.IsNot x, Expr T)
      {
        if (disjoint(x.arg1,T))
          setDisjoint(x,T);
	  }


  }
}