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
//  Change log
//    Version 2.2
//      Created as part of total re-design of Explorer.
//    Version 2.3
//      Moved creation of ascent procedures to new class 'Ascents'.
//      Moved computation of first tail terminals to 'Tail'.
//      Removed 'AscentVisitor' and 'TailVisitor'.
//      Added 'Is' and 'IsNot' to remaining four Visitors.
//      Renamed 'Properties' to 'Relations'.
//      Used new class 'Terminals' to compute conflicts.
//      New Vector 'colons' and its size 'C'.
//      Replaced 'show' by 'showExprs'.
//      Modified 'showCounts'.
//
//=========================================================================

package mouse.explorer;

import mouse.peg.Expr;
import mouse.peg.PEG;
import mouse.peg.RecClass;
import java.util.Hashtable;
import java.util.Vector;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  Static class Dual
//
//-------------------------------------------------------------------------
//
//  The class represents the dual grammar, constructed from the grammar
//  represented by object mouse.peg.PEG.
//  It is a structure of Expr objects accessible via named expressions
//  listed in the Vector 'named'. The named expressions are those for
//  the non-recursive Rules, the entry expressions (with names of Rules
//  replaced by them), and the ascent expressions named '$xxx'.
//  Additional Vectors contain lists of other Expr's in the structure:
//  'subs' for subexpressions and 'terms' for terminals.
//  All Expr's are listed in array 'index': first all named, then all
//  subexpressions, then all terminals.
//  Each Expr object carries its position in the array in field 'index'.
//  Relations between Expressions needed by the Explorer in addition
//  to those in peg.Relations are collected in object explorer.Relations.
//  The LL1 violations are collected in object Conflicts.
//
//  The structure is built by method 'create'.
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

public class Dual
{
  //=====================================================================
  //
  //  Data
  //
  //=====================================================================
  public static Vector<Expr> named  = new Vector<Expr>();
  public static Vector<Expr> subs   = new Vector<Expr>();
  public static Vector<Expr> terms  = new Vector<Expr>();

  public static Vector<Expr> rules   = new Vector<Expr>();
  public static Vector<Expr> entries = new Vector<Expr>();
  public static Vector<Expr> ascents = new Vector<Expr>();
  public static Vector<Expr> colons  = new Vector<Expr>();


  public static Expr index[]; // Array of expressions
  public static int E = 0;    // Number of expressions
  public static int R = 0;    // Number of named
  public static int N = 0;    // Number of nonterminals
  public static int I = 0;    // Number of entry procedures
  public static int A = 0;    // Number of ascent procedures
  public static int T = 0;    // Number of terminals
  public static int C = 0;    // Number of 'colon' expressions

  static Hashtable<String,Expr> names = new Hashtable<String,Expr>();

  static CopyVisitor   copyVisitor   = new CopyVisitor();
  static CleanVisitor  cleanVisitor  = new CleanVisitor();
  static RefVisitor    refVisitor    = new RefVisitor();
  static ShowVisitor   showVisitor   = new ShowVisitor();

  //=====================================================================
  //
  //  Create dual grammar.
  //
  //---------------------------------------------------------------------
  //
  //  The dual gammar is a structure of Expr objects.
  //  It is created from the original grammar represented by PEG.
  //  Non-recursive expressions with their subexpressions are copied
  //  from PEG. Entry and ascent expressions are created.
  //
  //=====================================================================
  public static boolean create()
    {
      //---------------------------------------------------------------
      //  Make sure PEG exists.
      //---------------------------------------------------------------
      if (PEG.N==0) throw new Error("PEG not created");

      //---------------------------------------------------------------
      //  Copy non-recursive expressions and their subexpressions.
      //---------------------------------------------------------------
      for (Expr.Rule e: PEG.rules)
        if (e.recClass==null)
          e.accept(copyVisitor);

      //---------------------------------------------------------------
      //  Create entry and ascent expressions.
      //---------------------------------------------------------------
      Ascents.create();

      //---------------------------------------------------------------
      //  Collect 'rules', 'entries', and 'ascents' into 'named'.
      //---------------------------------------------------------------
      named.addAll(rules);
      named.addAll(entries);
      named.addAll(ascents);

      //---------------------------------------------------------------
      //  Append 'colons' to 'subs'.
      //---------------------------------------------------------------
      subs.addAll(colons);

      //---------------------------------------------------------------
      //  Eliminate single-argument Choices and Sequences.
      //---------------------------------------------------------------
      clean();

      //---------------------------------------------------------------
      //  Resolve references and give names to yet unnamed expressions.
      //  Until now, all references to named expressions are represented
      //  by Expr.Ref objects. They are replaced by references
      //  to named Expr objects.
      //  Unnamed subexpressions receive names consisting of containing
      //  expression name followed by dot and number.
      //---------------------------------------------------------------
      for (Expr e: named)
      {
        refVisitor.ruleName = e.name;
        refVisitor.number = 0;
        e.accept(refVisitor);
      }

      //---------------------------------------------------------------
      //  Build index of all expressions.
      //---------------------------------------------------------------
      buildIndex();

      //---------------------------------------------------------------
      //  Reconstruct source of all expressions.
      //---------------------------------------------------------------
      PEG.source(index,R);

      //---------------------------------------------------------------
      //  Compute attributes of all expressions.
      //---------------------------------------------------------------
      PEG.attributes(index,N);

      //---------------------------------------------------------------
      //  Compute relations.
      //---------------------------------------------------------------
      Relations.compute();
      Terminals.compute();

      //---------------------------------------------------------------
      //  Create tails.
      //---------------------------------------------------------------
      Tail.create();

      //---------------------------------------------------------------
      //  Find LL1 violations.
      //---------------------------------------------------------------
      Conflicts.find();

      // Trace();

      return true;
    }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Private procedures
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //=====================================================================
  //
  //  Copy Expression
  //
  //---------------------------------------------------------------------
  //
  //  Makes a duplicate of Expression 'e' from the PEG grammar,
  //  together with the tree of its subexpressions.
  //  Any Rules in the tree (including 'e' itself) are replaced by
  //  references (Expr.Refs) to be resolved later.
  //
  //=====================================================================
  public static Expr copyExpr(Expr e)
    {
      if (e.isNamed)
        return new Expr.Ref(e.name);
      else
      {
        e.accept(copyVisitor);
        return copyVisitor.result;
      }
    }

  //=====================================================================
  //
  //  Eliminate single-argument Choices and Sequences.
  //
  //=====================================================================
  private static void clean()
    {
      //---------------------------------------------------------------
      //  Clean unnamed subexpressions
      //---------------------------------------------------------------
      for (Expr e: named)
        e.accept(cleanVisitor);

      //---------------------------------------------------------------
      //  Clean named Choices and Sequences
      //---------------------------------------------------------------
      // Move all expressions from 'named' to 'copy'.
      Vector<Expr> copy = new Vector<Expr>();
      copy.addAll(named);
      named.removeAllElements();

      // Process expressions in 'copy' and build new 'named'.
      for (Expr e: copy)
      {
        if (e instanceof Expr.Choice ch)
          cleanNamed(e,ch.args);
        else if (e instanceof Expr.Sequence sq)
          cleanNamed(e,sq.args);
        else
          named.add(e);
      }
    }

  //-------------------------------------------------------------------
  //  If 'e' is a single-argument Choice or Sequence, add that argument
  //  to 'named' under the name of 'e'.
  //  Otherwise add 'e' to 'named' under its original name.
  //-------------------------------------------------------------------
  private static void cleanNamed(Expr e, Expr[] args)
     {
       if (args.length>1)
         named.add(e);
       else
       {
         Expr arg = args[0];
         if (arg instanceof Expr.Ref)
           named.add(e);
         else
         {
           arg.name = e.name;
           names.remove(e.name);
           names.put(arg.name,arg);
           subs.remove(arg);
           named.add(arg);
           arg.isNamed = true;
         }
       }
     }

  //=====================================================================
  //
  //  Build index.
  //
  //---------------------------------------------------------------------
  //
  //  Builds the array 'index' containing all expressions, first Roots,
  //  then inner expressions, then terminals.
  //  Sets 'index' field of each Expression to the Expression's index
  //  in the array.
  //
  //=====================================================================
  private static void buildIndex()
    {
      R = named.size();
      C = colons.size();
      T = terms.size();
      N = R + subs.size();
      E = N + terms.size();
      index = new Expr[E];

      int i = 0;

      for (Expr e: named)
      {
        e.index = i;
        index[i] = e;
        i++;
      }

      for (Expr e: subs)
      {
        e.index = i;
        index[i] = e;
        i++;
      }

      for (Expr e: terms)
      {
        e.index = i;
        index[i] = e;
        i++;
      }
    }

  //=====================================================================
  //
  //  Show
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  showCounts.
  //-------------------------------------------------------------------
  public static void showCounts()
    {
      System.out.println("  " + named.size() + " named");
      System.out.println("    " + rules.size() + " rules");
      System.out.println("    " + entries.size() + " entries");
      System.out.println("    " + ascents.size() + " ascents");
      System.out.println("  " + subs.size() + " unnamed");
      System.out.println("  " + terms.size() + " terminals");
    }

  //-------------------------------------------------------------------
  //  Show Expressions.
  //-------------------------------------------------------------------
  public static void showExprs(boolean all)
    {
      System.out.println("\nRules");
      for (Expr e: named)
        System.out.println("  " + e.toNamed() + "   // " + PEG.attrs(e));
      if (!all) return;
      System.out.println("\nInner");
      for (Expr e: subs)
        System.out.println("  " + e.toShort() + "   // " + PEG.attrs(e));
      System.out.println("\nTerminals");
      for (Expr e: terms)
        System.out.println("  " + e.toShort() + "   // " + PEG.attrs(e));
    }

  //=====================================================================
  //
  //  Trace procedures - for development
  //
  //=====================================================================
  private static void  Trace()
    {
      trace("named");
      for (Expr e: named)
        e.accept(showVisitor);
      trace("\nsubs");
      for (Expr e: subs)
        e.accept(showVisitor);
      trace("\nterms");
      for (Expr e: terms)
        e.accept(showVisitor);
    }

  private static void trace(String s)
    {System.out.println(s); }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  CopyVisitor
  //
  //----------------------------------------------------------------------
  //
  //  Makes a copy of visited expression.
  //  Subexpressions are either copied or replaced by Expr.Ref
  //  (this is done by 'copyExpr').
  //  Rule is copied as named Choice.
  //  Copies are entered in 'rules', 'subs', 'colons', and 'terms'.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  static class CopyVisitor extends mouse.peg.Visitor
  {
    Expr result;

    //-----------------------------------------------------------------
    //  Rule
    //-----------------------------------------------------------------
    public void visit(Expr.Rule expr)
      {
        Expr[] args = new Expr[expr.args.length];

        for (int i=0;i<expr.args.length;i++)
          args[i] = copyExpr(expr.args[i]);
        result = new Expr.Choice(args);

        result.name = expr.name;
        result.isNamed = true;
        rules.add(result);
        names.put(expr.name,result);
      }

    //-----------------------------------------------------------------
    //  Choice
    //-----------------------------------------------------------------
    public void visit(Expr.Choice expr)
      {
        Expr[] args = new Expr[expr.args.length];

        for (int i=0;i<expr.args.length;i++)
          args[i] = copyExpr(expr.args[i]);
        result = new Expr.Choice(args);

        result.name = expr.name;
        subs.add(result);
      }

    //-----------------------------------------------------------------
    //  Sequence
    //-----------------------------------------------------------------
    public void visit(Expr.Sequence expr)
      {
        Expr[] args = new Expr[expr.args.length];
        for (int i=0;i<expr.args.length;i++)
          args[i] = copyExpr(expr.args[i]);
        result = new Expr.Sequence(args);
        result.name = expr.name;
        subs.add(result);
      }

    //-----------------------------------------------------------------
    //  And
    //-----------------------------------------------------------------
    public void visit(Expr.And expr)
      {
        result = new Expr.And(copyExpr(expr.arg));
        result.name = expr.name;
        subs.add(result);
      }

    //-----------------------------------------------------------------
    //  Not
    //-----------------------------------------------------------------
    public void visit(Expr.Not expr)
      {
        result = new Expr.Not(copyExpr(expr.arg));
        result.name = expr.name;
        subs.add(result);
      }

    //-----------------------------------------------------------------
    //  Plus
    //-----------------------------------------------------------------
    public void visit(Expr.Plus expr)
      {
        result = new Expr.Plus(copyExpr(expr.arg));
        result.name = expr.name;
        subs.add(result);
      }

    //-----------------------------------------------------------------
    //  Star
    //-----------------------------------------------------------------
    public void visit(Expr.Star expr)
      {
        result = new Expr.Star(copyExpr(expr.arg));
        result.name = expr.name;
        subs.add(result);
      }

    //-----------------------------------------------------------------
    //  Query
    //-----------------------------------------------------------------
    public void visit(Expr.Query expr)
      {
        result = new Expr.Query(copyExpr(expr.arg));
        result.name = expr.name;
        subs.add(result);
      }

    //-----------------------------------------------------------------
    //  PlusPlus
    //-----------------------------------------------------------------
    public void visit(Expr.PlusPlus expr)
      {
        result = new Expr.PlusPlus(copyExpr(expr.arg1),copyExpr(expr.arg2));
        result.name = expr.name;
        subs.add(result);
      }

    //-----------------------------------------------------------------
    //  StarPlus
    //-----------------------------------------------------------------
    public void visit(Expr.StarPlus expr)
      {
        result = new Expr.StarPlus(copyExpr(expr.arg1),copyExpr(expr.arg2));
        result.name = expr.name;
        subs.add(result);
      }

    //-----------------------------------------------------------------
    //  Is
    //-----------------------------------------------------------------
    public void visit(Expr.Is expr)
      {
        result = new Expr.Is(copyExpr(expr.arg1),copyExpr(expr.arg2));
        result.name = expr.name;
        colons.add(result);
      }

    //-----------------------------------------------------------------
    //  IsNot
    //-----------------------------------------------------------------
    public void visit(Expr.IsNot expr)
      {
        result = new Expr.IsNot(copyExpr(expr.arg1),copyExpr(expr.arg2));
        result.name = expr.name;
        colons.add(result);
      }

    //-----------------------------------------------------------------
    //  StringLit
    //-----------------------------------------------------------------
    public void visit(Expr.StringLit expr)
      {
        result = new Expr.StringLit(expr.s);
        result.name = expr.name;
        terms.add(result);
      }

    //-----------------------------------------------------------------
    //  CharClass
    //-----------------------------------------------------------------
    public void visit(Expr.CharClass expr)
      {
        result = new Expr.CharClass(expr.s,expr.hat);
        result.name = expr.name;
        terms.add(result);
      }

    //-----------------------------------------------------------------
    //  Range
    //-----------------------------------------------------------------
    public void visit(Expr.Range expr)
      {
        result = new Expr.Range(expr.a,expr.z);
        result.name = expr.name;
        terms.add(result);
      }

    //-----------------------------------------------------------------
    //  Any
    //-----------------------------------------------------------------
    public void visit(Expr.Any expr)
      {
        result = new Expr.Any();
        result.name = expr.name;
        terms.add(result);
      }

    //-----------------------------------------------------------------
    //  End
    //-----------------------------------------------------------------
    public void visit(Expr.End expr)
      {
        result = new Expr.End();
        result.name = expr.name;
        terms.add(result);
      }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  CleanVisitor
  //
  //----------------------------------------------------------------------
  //
  //  Eliminate single-argument Choice or Sequence subexpressions
  //  of visited Expresion: subexpression expr = arg is replaced by arg.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  static class CleanVisitor extends mouse.peg.Visitor
  {
    //-----------------------------------------------------------------
    //  Rule: should not be present at this moment.
    //-----------------------------------------------------------------
    public void visit(Expr.Rule expr)
      { throw new Error("SNOC" + expr.name); }

    //-----------------------------------------------------------------
    //  Choice
    //-----------------------------------------------------------------
    public void visit(Expr.Choice expr)
      {
        for (int i=0;i<expr.args.length;i++)
        {
          expr.args[i].accept(cleanVisitor);
          expr.args[i] = eliminate(expr.args[i]);
        }
      }

    //-----------------------------------------------------------------
    //  Sequence
    //-----------------------------------------------------------------
    public void visit(Expr.Sequence expr)
      {
        for (int i=0;i<expr.args.length;i++)
        {
          expr.args[i].accept(cleanVisitor);
          expr.args[i] = eliminate(expr.args[i]);
        }
      }

    //-----------------------------------------------------------------
    //  And
    //-----------------------------------------------------------------
    public void visit(Expr.And expr)
      {
        expr.arg.accept(cleanVisitor);
        expr.arg = eliminate(expr.arg);
      }

    //-----------------------------------------------------------------
    //  Not
    //-----------------------------------------------------------------
    public void visit(Expr.Not expr)
      {
        expr.arg.accept(cleanVisitor);
        expr.arg = eliminate(expr.arg);
      }

    //-----------------------------------------------------------------
    //  Plus
    //-----------------------------------------------------------------
    public void visit(Expr.Plus expr)
      {
        expr.arg.accept(cleanVisitor);
        expr.arg = eliminate(expr.arg);
      }

    //-----------------------------------------------------------------
    //  Star
    //-----------------------------------------------------------------
    public void visit(Expr.Star expr)
      {
        expr.arg.accept(cleanVisitor);
        expr.arg = eliminate(expr.arg);
      }

    //-----------------------------------------------------------------
    //  Query
    //-----------------------------------------------------------------
    public void visit(Expr.Query expr)
      {
        expr.arg.accept(cleanVisitor);
        expr.arg = eliminate(expr.arg);
      }

    //-----------------------------------------------------------------
    //  PlusPlus
    //-----------------------------------------------------------------
    public void visit(Expr.PlusPlus expr)
      {
        expr.arg1.accept(cleanVisitor);
        expr.arg1 = eliminate(expr.arg1);
        expr.arg2.accept(cleanVisitor);
        expr.arg2 = eliminate(expr.arg2);
      }

    //-----------------------------------------------------------------
    //  StarPlus
    //-----------------------------------------------------------------
    public void visit(Expr.StarPlus expr)
      {
        expr.arg1.accept(cleanVisitor);
        expr.arg1 = eliminate(expr.arg1);
        expr.arg2.accept(cleanVisitor);
        expr.arg2 = eliminate(expr.arg2);
      }

    //-----------------------------------------------------------------
    //  Is
    //-----------------------------------------------------------------
    public void visit(Expr.Is expr)
      {
        expr.arg1.accept(cleanVisitor);
        expr.arg1 = eliminate(expr.arg1);
        expr.arg2.accept(cleanVisitor);
        expr.arg2 = eliminate(expr.arg2);
      }

    //-----------------------------------------------------------------
    //  IsNot
    //-----------------------------------------------------------------
    public void visit(Expr.IsNot expr)
      {
        expr.arg1.accept(cleanVisitor);
        expr.arg1 = eliminate(expr.arg1);
        expr.arg2.accept(cleanVisitor);
        expr.arg2 = eliminate(expr.arg2);
      }

    //-----------------------------------------------------------------
    //  If possible, eliminate 'e': if 'e' is a single-argument Choice
    //  or Sequence, return this argument. Otherwise return 'e'.
    //  Note that 'e' is not named: named arguments became Expr.Ref.
    //-----------------------------------------------------------------
    private Expr eliminate(Expr e)
      {
        if (e instanceof Expr.Choice)
        {
          if (e.isNamed) throw new Error("SNOC "+e.name+" is named");
          Expr.Choice expr = (Expr.Choice) e;
          if (expr.args.length>1)
            return e;
          subs.remove(e);
          return expr.args[0];
        }

        if (e instanceof Expr.Sequence expr)
        {
          if (expr.isNamed) throw new Error("SNOC "+expr.name+" is named");
          if (expr.args.length>1)
            return e;
          subs.remove(e);
          return expr.args[0];
        }

        return e;
      }
  }

  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  RefVisitor
  //
  //-----------------------------------------------------------------------
  //
  //  Resolve references and give names to yet unnamed expressions.
  //  Until now, all references to named expressions are represented
  //  by Expr.Ref objects. They are represented by references
  //  to named Expr objects.
  //  Unnamed subexpressions receive names consisting of containing
  //  expression name followed by dot and number.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  static class RefVisitor extends mouse.peg.Visitor
  {
    String ruleName;
    int number;

    //-----------------------------------------------------------------
    //  Rule: should not be present at this moment.
    //-----------------------------------------------------------------
    public void visit(Expr.Rule expr)
      { throw new Error("SNOC: visiting Rule " + expr.toShort()); }

    //-----------------------------------------------------------------
    //  Choice.
    //-----------------------------------------------------------------
    public void visit(Expr.Choice expr)
      {
        for (int i=0;i<expr.args.length;i++)
          expr.args[i] = resolve(expr.args[i]);
      }

    //-----------------------------------------------------------------
    //  Sequence.
    //-----------------------------------------------------------------
    public void visit(Expr.Sequence expr)
      {
        for (int i=0;i<expr.args.length;i++)
          expr.args[i] = resolve(expr.args[i]);
      }

    //-----------------------------------------------------------------
    //  And.
    //-----------------------------------------------------------------
    public void visit(Expr.And expr)
      { expr.arg = resolve(expr.arg); }

    //-----------------------------------------------------------------
    //  Not.
    //-----------------------------------------------------------------
    public void visit(Expr.Not expr)
      { expr.arg = resolve(expr.arg); }

    //-----------------------------------------------------------------
    //  Plus.
    //-----------------------------------------------------------------
    public void visit(Expr.Plus expr)
      { expr.arg = resolve(expr.arg); }

    //-----------------------------------------------------------------
    //  Star.
    //-----------------------------------------------------------------
    public void visit(Expr.Star expr)
      { expr.arg = resolve(expr.arg); }

    //-----------------------------------------------------------------
    //  Query.
    //-----------------------------------------------------------------
    public void visit(Expr.Query expr)
      { expr.arg = resolve(expr.arg); }

    //-----------------------------------------------------------------
    //  PlusPlus.
    //-----------------------------------------------------------------
    public void visit(Expr.PlusPlus expr)
      {
        expr.arg1 = resolve(expr.arg1);
        expr.arg2 = resolve(expr.arg2);
      }

    //-----------------------------------------------------------------
    //  StarPlus.
    //-----------------------------------------------------------------
    public void visit(Expr.StarPlus expr)
      {
        expr.arg1 = resolve(expr.arg1);
        expr.arg2 = resolve(expr.arg2);
      }

    //-----------------------------------------------------------------
    //  Is.
    //-----------------------------------------------------------------
    public void visit(Expr.Is expr)
      {
        expr.arg1 = resolve(expr.arg1);
        expr.arg2 = resolve(expr.arg2);
      }

    //-----------------------------------------------------------------
    //  IsNot.
    //-----------------------------------------------------------------
    public void visit(Expr.IsNot expr)
      {
        expr.arg1 = resolve(expr.arg1);
        expr.arg2 = resolve(expr.arg2);
      }

    //-----------------------------------------------------------------
    //  Private procedure
    //  If e is Expr.Ref, return the referenced expression.
    //  Otherwise, give name to unnamed e, descend from e,
    //  and return e.
    //-----------------------------------------------------------------
    private Expr resolve(Expr e)
      {
        if (e.isRef)
        {
          Expr.Ref ref = (Expr.Ref)e;
          return names.get(e.name);
        }
        else
        {
          if (e.name==null)
          {
            e.name = ruleName + "_" + number;
            number++;
          }
          e.accept(this);
          return e;
        }
      }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  ShowVisitor - temporary for tracing
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  static class ShowVisitor extends mouse.peg.Visitor
  {
    public void visit(Expr.Rule expr)
      {
        System.out.print(expr.name + " =>>" );
        for (Expr arg: expr.args)
          System.out.print(" " + showArg(arg));
        System.out.println();
      }

    public void visit(Expr.Choice expr)
      {
        System.out.print(expr.name + " =>" );
        for (Expr arg: expr.args)
          System.out.print(" " + showArg(arg));
        System.out.println();
      }

    public void visit(Expr.Sequence expr)
      {
        System.out.print(expr.name + " ->" );
        for (Expr arg: expr.args)
          System.out.print(" " + showArg(arg));
        System.out.println();
      }

    public void visit(Expr.And expr)
      { System.out.println(expr.name + " = &" + showArg(expr.arg)); }

    public void visit(Expr.Not expr)
      { System.out.println(expr.name + " = !" + showArg(expr.arg)); }

    public void visit(Expr.Plus expr)
      { System.out.println(expr.name + " = " + showArg(expr.arg) + "+"); }

    public void visit(Expr.Star expr)
      { System.out.println(expr.name + " = " + showArg(expr.arg) + "*"); }

    public void visit(Expr.Query expr)
      { System.out.println(expr.name + " = " + showArg(expr.arg) + "?"); }

    public void visit(Expr.PlusPlus expr)
      { System.out.println(expr.name + " = " + showArg(expr.arg1) + "++" + showArg(expr.arg2)); }

    public void visit(Expr.StarPlus expr)
      { System.out.println(expr.name + " = " + showArg(expr.arg1) + "++" + showArg(expr.arg2)); }

    public void visit(Expr.Is expr)
      { System.out.println(expr.name + " = " + showArg(expr.arg1) + ":" + showArg(expr.arg2)); }

    public void visit(Expr.IsNot expr)
      { System.out.println(expr.name + " = " + showArg(expr.arg1) + ":!" + showArg(expr.arg2)); }

    public void visit(Expr.Ref expr)
      { System.out.println("Ref "+ expr.name); }

    public void visit(Expr.StringLit expr)
      { term(expr); }

    public void visit(Expr.CharClass expr)
      { term(expr); }

    public void visit(Expr.Range expr)
      { term(expr); }

    public void visit(Expr.Any expr)
      { term(expr); }

    public void visit(Expr.End expr)
      { term(expr); }


    private String showArg(Expr e)
      {
        if (e.isRef) return "Ref " + e.name;
        return e.name;
      }

    private void term(Expr e)
      { System.out.println(e.name + " = " + e.asString); }
  }
}


























