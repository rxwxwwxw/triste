//=========================================================================
//
//  Part of PEG parser generator Mouse.
//
//  Copyright (C) 2009, 2010, 2011, 2012, 2020, 2021
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
//  Version 1.2
//    License changed by the author to Apache v.2.
//  Version 1.3
//    Made into repository for parsed PEG and related methods.
//    Corrected reconstruction of DiagName.
//  Version 1.4
//    Completed all Visitors with 'StarPlus' and 'PlusPlus'.
//  Version 1.5.1
//    (Steve Owens) Removed unused import.
//    Removed unused varable 'nul1' in 'visit(Expr.StarPlus)'.
//  Version 2.0
//    Total redesign:
//    The class is made static.
//    Lists of Expr's changed to Vectors.
//    RefVisitor resolves references and removes Expr.Ref objects.
//    ListVisitor gives names to subexpressions and terminals.
//    Terminals get names '_Txxx' where 'xxx' is the serial number.
//    Compact removes unused Expr's from their lists.
//    Relations between Expresions are held in static class Relations.
//    Left-recursion classes are represented by RecClass objects.
//    Changed computation of expression attributes.
//    Modified exit conventions: PEG exits immediately
//    and returns 'false' if the source could not be parsed.
//    Otherwise it returns 'true' with error count in 'errors'.
//    On that exit, the representation of the grammar exists,
//    and can be shown for diagnostic purposes, but can be used
//    to generate parser only if 'errors' is 0.
//  Version 2.1
//    Moved here 'index' and its constrution from 'Relations'.
//    Exit and return 'false' if there are unresolved references.
//    Updated computation and presentation of expression attributes.
//  Version 2.2
//    Changes to work with the new Explorer:
//    'source', 'atributes' and 'show' adapted for calling from Dual.
//    Updated computation and presentation of attributes.
//    'Expr.End' added to Visitors.
//    Terminals get names 'rule_number'.
//    Numbers 'N' and 'E' redefined.
//  Version 2.3
//    'Is' and 'IsNot' included in five visitors.
//    'Rule()' used to construct dummy Rule in RefVisitor.
//    Moved 'firstTailTerms' to Tail.
//    Method 'show' replaced by 'showExprs'.
//    Modified method 'showCounts'.
//
//=========================================================================

package mouse.peg;

import java.util.Hashtable;
import java.util.HashSet;
import java.util.Vector;
import mouse.utility.Convert;
import mouse.runtime.Source;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  Static class PEG
//
//-------------------------------------------------------------------------
//
//  The class represents parsed grammar.
//  The parsed grammar is a structure of Expr objects in the form of
//  trees with terminals and Expressions marked 'isNamed' as leaves.
//  The trees are rooted in Expr.Rule objects listed in the Vector 'rules'.
//  Additional Vectors contain lists of other Expr's in the structure:
//  'subs' for subexpressions, 'terms' for terminals.
//  All Expr's are listed in array 'index': first all Rules, then all
//  subexpressions, then all terminals.
//  Each Expr object carries its position in the array in field 'index'.
//  Different relations between Expressions are collected in class Relations.
//  Left-recursion classes of the grammar are represented by RecClass
//  objects listed in the Vector 'recClasses'.
//
//  Method 'parse' builds this structure from a file containing PEG.
//  It uses for this purpose the Parser and Semantics from this package.
//  The Parser is constructed using Mouse from grammar.peg.
//
//  Method 'compact' eliminates duplicate subexpressions from the
//  parsed grammar. After this operation, the parsed grammar is no longer
//  a set of trees, but an acyclic graph, as different Expr nodes may
//  point to the same subexpressions. The 'rules' Vctor is not changed
//  (duplicate rules are not eliminated), but the other Vectors are updated.
//  Laft-recursive expressions are not eliminated.
//
//  The 'show' methods print out on System.out the grammar reconstructed
//  from its parsed form.
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

public class PEG
{
  //=====================================================================
  //
  //  Data
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Rules, subexpressions, terminals, references.
  //-------------------------------------------------------------------
  public static Vector<Expr.Rule> rules = new Vector<Expr.Rule>();
  public static Vector<Expr>      subs  = new Vector<Expr>();
  public static Vector<Expr>      terms = new Vector<Expr>();

  public static Expr index[]; // Array of expressions
  public static int E;        // Number of expressions
  public static int R;        // Number of rules
  public static int N;        // Number of nonterminals

  //-------------------------------------------------------------------
  //  Left-recursion classes
  //-------------------------------------------------------------------
  public static Vector<RecClass> recClasses = new Vector<RecClass>();

  //-------------------------------------------------------------------
  //  Counters.
  //-------------------------------------------------------------------
  public static int errors;     // Errors
  public static int iterAt;     // Iterations for attributes

  //=======================================================================
  //
  //  Parse PEG grammar suplied as 'src'.
  //
  //=====================================================================
  public static boolean parse(Source src)
    {
      //---------------------------------------------------------------
      //  Parse the grammar
      //---------------------------------------------------------------
      Parser parser = new Parser();
      parser.parse(src);

      Semantics sem = parser.semantics();
      rules = sem.rules;
      errors = sem.errcount;

      //  Quit if parsing failed.
      if (errors>0) return false;

      //---------------------------------------------------------------
      //  Resolve references and remove Expr.Ref objects.
      //  After removal of Expr.Ref objects, the parse trees have
      //  terminals and references to Rules as leafs. These latter
      //  must be checked for in visitors that descend the trees.
      //---------------------------------------------------------------
      resolve();

      //  Quit if unresolved reference(s) found.
      if (errors>0) return false;

      //---------------------------------------------------------------
      //  Make linear lists of expressions contained in the parse tree:
      //  inner expressions ('subs') and terminals ('terms').
      //  Assign names to subexpressions and termnials.
      //---------------------------------------------------------------
      ListVisitor listVisitor = new ListVisitor();
      for (Expr.Rule r: rules)
         r.accept(listVisitor);

      //---------------------------------------------------------------
      //  Build index of all expressions.
      //---------------------------------------------------------------
      buildIndex();

      //---------------------------------------------------------------
      //  Reconstruct source string for all Expression.
      //---------------------------------------------------------------
      source(index,R);

      //---------------------------------------------------------------
      //  Compute attributes for all Expressions.
      //---------------------------------------------------------------
      attributes(index,N);

      //---------------------------------------------------------------
      //  Compute relations.
      //---------------------------------------------------------------
      Relations.compute();

      //---------------------------------------------------------------
      //  Find left-recursion classes.
      //---------------------------------------------------------------
      findRecClasses();

      //---------------------------------------------------------------
      //  Diagnose.
      //---------------------------------------------------------------
      Diagnose.apply();
      return true;
    }

  //=====================================================================
  //
  //  Compact
  //
  //---------------------------------------------------------------------
  //
  //  Eliminate duplicate expressions from parse tree.
  //  Expressions involved in left-recursion, including terminals,
  //  are not eliminated.
  //  The result is no longer a tree.
  //
  //=====================================================================
  public static void compact()
    {
      CompactVisitor compactVisitor = new CompactVisitor();
      for (Expr e: rules)
        if (e.recClass==null) e.accept(compactVisitor);
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
      System.out.println("  " + rules.size() + " rules");
      System.out.println("  " + subs.size() + " unnamed");
      System.out.println("  " + terms.size() + " terminals");
      showRecCounts();
    }

  //-------------------------------------------------------------------
  //  Show Expressions.
  //-------------------------------------------------------------------
  public static void showExprs(boolean all)
    {
      System.out.println("\nRules");
      for (Expr.Rule e: rules)
        System.out.println("  " + e.toNamed() + "   // " + attrs(e));
      if (!all) return;
      System.out.println("\nInner");
      for (Expr e: subs)
        System.out.println("  " + e.toShort() + "   // " + attrs(e));
      System.out.println("\nTerminals");
      for (Expr e: terms)
        System.out.println("  " + e.toShort() + "   // " + attrs(e));
    }

  //-------------------------------------------------------------------
  //  showRecClasses.
  //-------------------------------------------------------------------
  public static void showRecClasses()
    {
      for (RecClass rc: recClasses)
        rc.show();
    }

  //-------------------------------------------------------------------
  //  showRecCounts.
  //-------------------------------------------------------------------
  public static void showRecCounts()
    {
      if (recClasses.size()==0) return;
      int nRecs = 0;
      for (RecClass rc: recClasses)
        nRecs += rc.members.size();
      System.out.println("  " + nRecs + " left-recursive expressions in "
               + recClasses.size() + " class"
               + (recClasses.size()==1?"":"es"));
    }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Private methods.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //=====================================================================
  //
  //  Resolve references and remove Expr.Ref objects.
  //
  //=====================================================================
  private static void resolve()
    {
      RefVisitor refVisitor = new RefVisitor();

      //---------------------------------------------------------------
      //  Build table of Rule names, checking for duplicates.
      //---------------------------------------------------------------
      for (Expr.Rule r: rules)
      {
        Expr.Rule prev = refVisitor.names.put(r.name,r);
        if (prev!=null)
        {
          System.out.println("Error: duplicate name '" + r.name + "'.");
          errors++;
        }
      }

      //---------------------------------------------------------------
      //  Replace Expr.Ref objects by direct references to Rules.
      //---------------------------------------------------------------
      for (Expr e: rules)
        e.accept(refVisitor);

      //---------------------------------------------------------------
      //  Detect unused rules.
      //  Top rule is assumed referenced.
      //---------------------------------------------------------------
      refVisitor.referenced.add(rules.elementAt(0).name);
      for (Expr.Rule r: rules)
      {
        if (!refVisitor.referenced.contains(r.name))
          System.out.println("Info: Rule '" + r.name + "' is not used.");
      }
    }

  //=====================================================================
  //
  //  Build index.
  //
  //---------------------------------------------------------------------
  //
  //  Build the array 'index' containing all expressions, first Rules,
  //  then inner expressions, then terminals.
  //  Set 'index' field of each Expression to the Expression's index
  //  in the array.
  //
  //=====================================================================
  private static void buildIndex()
    {
      R = rules.size();
      N = R + subs.size();
      E = N + terms.size();
      index = new Expr[E];

      int i = 0;

      for (Expr e: rules)
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
  //  Reconstruct source.
  //
  //---------------------------------------------------------------------
  //
  //  Reconstruct, in a standard form, the source string of each
  //  expression and assign it to 'asString' field of Expr object.
  //
  //=====================================================================
  public static void source(Expr[] index, int R)
    {
      SourceVisitor sourceVisitor = new SourceVisitor();
      for (int i=0;i<R;i++)
        index[i].accept(sourceVisitor);
      sourceVisitor = null;
    }

  //=====================================================================
  //
  //  Compute attributes for all expressions.
  //
  //---------------------------------------------------------------------
  //
  //  The meaning of attributes is:
  //    def - defines a terminal string.
  //    nul - can generate null string.
  //    adv - can generate non-null string.
  //    end - end-of-input in each generated string.
  //    fal - may fail.
  //  The attributes are computed by iteration to a fixpoint.
  //  The atttributes for terminals are preset by their constructors.
  //  For other expressions they are preset to 'false'.
  //  The iteration step is performed by AttrVisitor.
  //  The computation is monotone, meaning that a value is never
  //  changed from 'true' to 'false'.
  //  The procedure has 'index' as parameter because it is also used
  //  for dual grammar.
  //
  //=====================================================================
  public static void attributes(Expr[] index, int N)
    {
      //---------------------------------------------------------------
      //  The iteration step increases 'trueAttrs'.
      //  The iteration stops when it does not.
      //---------------------------------------------------------------
      int trueAttrs; // Number of true attributes after last step
      int a = 0;     // Number of true attributes before last step
      iterAt = 0;    // Number of steps

      AttrVisitor attrVisitor = new AttrVisitor();

      while(true)
      {
        //-------------------------------------------------------------
        //  Iteration step
        //-------------------------------------------------------------
        for (int i=0;i<N;i++)
          index[i].accept(attrVisitor);

        //-------------------------------------------------------------
        //  Count true attributes (non-terminals only)
        //-------------------------------------------------------------
        trueAttrs = 0;
        for (int i=0;i<N;i++)
        {
          Expr e = index[i];
          trueAttrs += (e.def? 1:0) + (e.nul? 1:0) + (e.adv? 1:0) +
                       (e.end? 1:0) + (e.fal? 1:0);
        }

        //-------------------------------------------------------------
        //  Break if fixpoint reached
        //-------------------------------------------------------------
        if (trueAttrs==a) break;

        //-------------------------------------------------------------
        //  To next step
        //-------------------------------------------------------------
        a = trueAttrs;
        iterAt++;
      }
    }

  //=====================================================================
  //
  //  Find left-recursion classes.
  //
  //=====================================================================
  private static void findRecClasses()
    {
      //---------------------------------------------------------------
      //  Recursion class must contain at least one Rule
      //  so it is enough to create recursion classes for Rules.
      //---------------------------------------------------------------
      for (Expr.Rule rule: PEG.rules)
      {
        int r = rule.index;
        if (!Relations.First.at(r,r)) continue;  // Not left-recursive
        if (rule.recClass!=null) continue;       // Class already exists
        recClasses.add(new RecClass(rule));      // Create class
      }
    }

  //=====================================================================
  //
  //  Format attributes for 'showRules' and 'showAll'.
  //
  //=====================================================================
  public static String attrs(Expr e)
    { return " " + (e.def? ((e.nul?"0":"") + (e.adv?"1":"")
                 + (e.end?"e":"") + (e.fal?"f":"")):"v")
                 + (e.recClass==null?"":" rec class "+e.recClass.name); }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  RefVisitor - resolves references and removes Expr.Ref objects.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  static class RefVisitor extends mouse.peg.Visitor
  {
    //------------------------------------------------------------------
    // Local data
    //------------------------------------------------------------------
    // Mapping from names to Rules
    Hashtable<String,Expr.Rule> names = new Hashtable<String,Expr.Rule>();

    // Referenced names.
    HashSet<String> referenced = new HashSet<String>();

    // Dummy rule - replaces undefined to stop multiple messages.
    Expr.Rule dummy = new Expr.Rule();

    //------------------------------------------------------------------
    //  Visitor procedures
    //------------------------------------------------------------------
    public void visit(Expr.Rule expr)
      { doCompound(expr, expr.args); }

    public void visit(Expr.Choice expr)
      { doCompound(expr, expr.args); }

    public void visit(Expr.Sequence expr)
      { doCompound(expr, expr.args); }

    public void visit(Expr.And expr)
      { expr.arg = getRule(expr.arg); }

    public void visit(Expr.Not expr)
      { expr.arg = getRule(expr.arg); }

    public void visit(Expr.Plus expr)
      { expr.arg = getRule(expr.arg); }

    public void visit(Expr.Star expr)
      { expr.arg = getRule(expr.arg); }

    public void visit(Expr.Query expr)
      { expr.arg = getRule(expr.arg); }

    public void visit(Expr.PlusPlus expr)
      {
        expr.arg1 = getRule(expr.arg1);
        expr.arg2 = getRule(expr.arg2);
      }

    public void visit(Expr.StarPlus expr)
      {
        expr.arg1 = getRule(expr.arg1);
        expr.arg2 = getRule(expr.arg2);
      }

    public void visit(Expr.Is expr)
      {
        expr.arg1 = getRule(expr.arg1);
        expr.arg2 = getRule(expr.arg2);
      }

    public void visit(Expr.IsNot expr)
      {
        expr.arg1 = getRule(expr.arg1);
        expr.arg2 = getRule(expr.arg2);
      }

    //------------------------------------------------------------------
    //  Common for expressions with argument array
    //------------------------------------------------------------------
    private void doCompound(Expr expr, Expr[] args)
      {
        for (int i=0;i<args.length;i++)
          args[i] = getRule(args[i]);
      }

    //------------------------------------------------------------------
    //  If 'expr' is Expr.Ref, return Rule referenced by it.
    //  Otherwise return 'expr'.
    //------------------------------------------------------------------
    private Expr getRule(Expr expr)
      {
        if (!expr.isRef)
        {
          expr.accept(this);
          return expr;
        }
        else
        {
          Expr rule = names.get(expr.name);
          if (rule==null)
          {
            System.out.println("Error: undefined name '" + expr.name + "'.");
            names.put(expr.name,dummy);
            errors++;
          }
          else
          {
            referenced.add(expr.name);
            rule.isNamed = true;
          }
          return rule;
        }
      }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  ListVisitor - makes lists of expressions and gives names to unnamed.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //-------------------------------------------------------------------
  //  Each visit names the visited expression (other than Rule),
  //  adds it to its proper list, and then proceeeds to visit
  //  all subexpressions, if any.
  //-------------------------------------------------------------------

  static class ListVisitor extends mouse.peg.Visitor
  {
    String ruleName;
    int number;

    public void visit(Expr.Rule expr)
      {
        ruleName = expr.name;
        number = 0;
        for (Expr arg: expr.args)
          descendFrom(arg);
      }

    public void visit(Expr.Choice expr)
      { doCompound(expr, expr.args); }

    public void visit(Expr.Sequence expr)
      { doCompound(expr, expr.args); }

    public void visit(Expr.And expr)
      { doUnary(expr, expr.arg); }

    public void visit(Expr.Not expr)
      { doUnary(expr, expr.arg); }

    public void visit(Expr.Plus expr)
      { doUnary(expr, expr.arg); }

    public void visit(Expr.Star expr)
      { doUnary(expr, expr.arg); }

    public void visit(Expr.Query expr)
      { doUnary(expr, expr.arg); }

    public void visit(Expr.PlusPlus expr)
      { doBinary(expr, expr.arg1,expr.arg2); }

    public void visit(Expr.StarPlus expr)
      { doBinary(expr, expr.arg1,expr.arg2); }

    public void visit(Expr.Is expr)
      { doBinary(expr, expr.arg1,expr.arg2); }

    public void visit(Expr.IsNot expr)
      { doBinary(expr, expr.arg1,expr.arg2); }

    public void visit(Expr.StringLit expr)
      { doTerm(expr); }

    public void visit(Expr.Range expr)
      { doTerm(expr); }

    public void visit(Expr.CharClass expr)
      { doTerm(expr); }

    public void visit(Expr.Any expr)
      { doTerm(expr); }

    public void visit(Expr.End expr)
      { doTerm(expr); }


    private void doCompound(Expr expr, Expr[] args)
      {
        doSub(expr);
        for (Expr arg: args)
          descendFrom(arg);
      }

    private void doBinary(Expr expr, Expr arg1, Expr arg2)
      {
        doSub(expr);
        descendFrom(arg1);
        descendFrom(arg2);
      }

    private void doUnary(Expr expr, Expr arg)
      {
        doSub(expr);
        descendFrom(arg);
      }

    private void doTerm(Expr expr)
      {
        terms.add(expr);
        expr.name = ruleName + "_" + number;
        number++;
      }

    private void doSub(Expr expr)
      {
        subs.add(expr);
        expr.name = ruleName + "_" + number;
        number++;
      }

    private void descendFrom(Expr arg)
      { if (!arg.isNamed) arg.accept(this); } // Don't descend to Rule
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  SourceVisitor - reconstructs source strings of expressions
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //-------------------------------------------------------------------
  //  Each visit starts with visiting the subexpressions to construct
  //  their source strings. These strings are then used as building
  //  blocks to produce the final result. Procedure 'enclose'
  //  encloses the subexpression in parentheses if needed, depending
  //  on the binding strength of subexpression and containing expression.
  //-------------------------------------------------------------------

  public static class SourceVisitor extends mouse.peg.Visitor
  {
    public void visit(Expr.Rule r)
      {
        StringBuilder sb = new StringBuilder(r.name + " = ");

        String sep = "";
        for (int i=0;i<r.args.length;i++)
        {
          sb.append(sep);
          sb.append(enclose(r.args[i],0));
          if (r.onSucc[i]!=null)
          sb.append(" " + r.onSucc[i].asString());
          if (r.onFail[i]!=null)
            sb.append(" ~" + r.onFail[i].asString());
          sep = " / ";
        }

        if (r.diagName!=null)
          sb.append(" <" + r.diagName + ">");

        sb.append(" ;");
        r.asString = sb.toString();
      }

    public void visit(Expr.Choice expr)
      {
        StringBuilder sb = new StringBuilder();
        String sep = "";
        for (Expr arg: expr.args)
        {
          sb.append(sep);
          sb.append(enclose(arg,0));
          sep = " / ";
        }
        expr.asString = sb.toString();
      }

    public void visit(Expr.Sequence expr)
      {
        StringBuilder sb = new StringBuilder();
        String sep = "";
        for (Expr arg: expr.args)
        {
          sb.append(sep);
          sb.append(enclose(arg,1));
          sep = " ";
        }
        expr.asString = sb.toString();;
      }

    public void visit(Expr.And expr)
      { expr.asString = "&" + enclose(expr.arg,2); }

    public void visit(Expr.Not expr)
      { expr.asString = "!" + enclose(expr.arg,2); }

    public void visit(Expr.Plus expr)
      { expr.asString = enclose(expr.arg,3) + "+"; }

    public void visit(Expr.Star expr)
      { expr.asString = enclose(expr.arg,3) + "*"; }

    public void visit(Expr.Query expr)
      { expr.asString = enclose(expr.arg,3) + "?"; }

    public void visit(Expr.PlusPlus expr)
      { expr.asString = enclose(expr.arg1,3) + "++ " + enclose(expr.arg2,3); }

    public void visit(Expr.StarPlus expr)
      { expr.asString = enclose(expr.arg1,3) + "*+ " + enclose(expr.arg2,3); }

    public void visit(Expr.Is expr)
      { expr.asString = enclose(expr.arg1,3) + ":" + enclose(expr.arg2,3); }

    public void visit(Expr.IsNot expr)
      { expr.asString = enclose(expr.arg1,3) + ":!" + enclose(expr.arg2,3); }

    //-----------------------------------------------------------------
    //  Reconstruct source of 'e', enclosing it in parentheses
    //  if binding strength of 'e' does not exceed 'mybind'.
    //-----------------------------------------------------------------
    private String enclose(Expr e, int mybind)
      {
        if (e.isNamed)
          return e.name;

        e.accept(this);
        boolean nest = e.bind<=mybind;
        return (nest?"(":"") + e.asString + (nest?")":"");
      }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  AttrVisitor - Compute attributes.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //-------------------------------------------------------------------
  //  Each visit computes attributes from those of subexpressions.
  //  Attributes for terminals are preset by their constructors.
  //  The computaton is monotone starting with 'false', which means
  //  'true' is never changed to 'false'.
  //-------------------------------------------------------------------

  static class AttrVisitor extends mouse.peg.Visitor
  {
    public void visit(Expr.Rule expr)
      {
        boolean exGen = false;
        boolean exNul = false;
        boolean exAdv = false;
        boolean alEnd = true;
        boolean alFal = true;

        for (int i=0; i<expr.args.length; i++)
        {
          Expr e = expr.args[i];
          exGen |= e.def;
          exNul |= e.nul;
          exAdv |= e.adv;
          alEnd &= e.end;
          alFal &= (e.fal | (expr.onSucc[i]!=null && expr.onSucc[i].and));
        }

        expr.def |= exGen;
        expr.nul |= exNul;
        expr.adv |= exAdv;
        expr.end |= alEnd;
        expr.fal |= alFal;
      }

    public void visit(Expr.Choice expr)
      {
        boolean exGen = false;
        boolean exNul = false;
        boolean exAdv = false;
        boolean alEnd = true;
        boolean alFal = true;

        for (Expr arg: expr.args)
        {
          exGen |= arg.def;
          exNul |= arg.nul;
          exAdv |= arg.adv;
          alEnd &= arg.end;
          alFal &= arg.fal;
        }

        expr.def |= exGen;
        expr.nul |= exNul;
        expr.adv |= exAdv;
        expr.end |= alEnd;
        expr.fal |= alFal;
      }

    public void visit(Expr.Sequence expr)
      {
        boolean alGen = true;
        boolean alNul = true;
        boolean exAdv = false;
        boolean exEnd = false;
        boolean exFal = false;

        for (Expr arg: expr.args)
        {
          alGen &= arg.def;
          alNul &= arg.nul;
          exAdv |= arg.adv;
          exEnd |= arg.end;
          exFal |= arg.fal;
        }

        expr.def |= alGen;
        expr.nul |= alNul;
        expr.adv |= exAdv;
        expr.end |= exEnd;
        expr.fal |= exFal;
      }

    public void visit(Expr.And expr)
      {
        Expr arg = expr.arg;
        expr.def |= arg.def;
        expr.nul = true;
        expr.fal = true;
      }

    public void visit(Expr.Not expr)
      {
        Expr arg = expr.arg;
        expr.def |= arg.def;
        expr.nul = true;
        expr.fal = true;
      }

    public void visit(Expr.Plus expr)
      {
        Expr arg = expr.arg;
        expr.def |= arg.def;
        expr.nul |= arg.nul;
        expr.adv |= arg.adv;
        expr.end |= arg.end;
        expr.fal |= arg.fal;
      }

    public void visit(Expr.Star expr)
      {
        Expr arg = expr.arg;
        expr.def = true;
        expr.nul = true;
        expr.adv |= arg.adv;
      }

    public void visit(Expr.Query expr)
      {
        Expr arg = expr.arg;
        expr.def = true;
        expr.nul = true;
        expr.adv |= arg.adv;
      }

    public void visit(Expr.PlusPlus expr)
      {
        Expr a = expr.arg1;
        Expr b = expr.arg2;
        expr.def |= (a.def & b.def);
        expr.nul |= (a.nul & b.nul);
        expr.adv |= (a.adv | b.adv);
        expr.end |= (a.end | b.end);
        expr.fal |= (a.fal | b.fal);
      }

    public void visit(Expr.StarPlus expr)
      {
        Expr a = expr.arg1;
        Expr b = expr.arg2;
        expr.def |= b.def;
        expr.nul |= b.nul;
        expr.adv |= (a.adv | b.adv);
        expr.end |= b.end;
        expr.fal |= b.fal;
      }

    public void visit(Expr.Is expr)
      {
        Expr a = expr.arg1;
        Expr b = expr.arg2;
        expr.def |= (a.def & b.def);
        expr.nul |= (a.nul & b.nul);
        expr.adv |= (a.adv & b.adv);
        expr.end |= (a.end & b.end);
        expr.fal |= (a.fal | b.fal);
      }

    public void visit(Expr.IsNot expr)
      {
        Expr a = expr.arg1;
        Expr b = expr.arg2;
        expr.def |= (a.def & b.def);
        expr.nul |= a.nul;
        expr.adv |= a.adv;
        expr.end |= a.end;
        expr.fal |= a.fal;
      }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  CompactVisitor - eliminates duplicate expresions
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //-------------------------------------------------------------------
  //  Each visit examines subexpressions of a visited expression.
  //  If it finds the subexpression identical to a previously
  //  encountered, replaces the subexpression by the latter.
  //  Otherwise, it proceeds to visit the subexpression.
  //  Expressions are considered identical if they have the same
  //  reconstructed source.
  //-------------------------------------------------------------------

  static class CompactVisitor extends mouse.peg.Visitor
  {
    //-----------------------------------------------------------------
    //  Hash table to detect identical expressions.
    //  The table maps sources to expressions.
    //-----------------------------------------------------------------
    Hashtable<String,Expr> sources = new Hashtable<String,Expr>();

    public void visit(Expr.Rule expr)
      { doCompound(expr, expr.args); }

    public void visit(Expr.Choice expr)
      { doCompound(expr, expr.args); }

    public void visit(Expr.Sequence expr)
      { doCompound(expr, expr.args); }

    public void visit(Expr.And expr)
      { expr.arg = alias(expr.arg); }

    public void visit(Expr.Not expr)
      { expr.arg = alias(expr.arg); }

    public void visit(Expr.Plus expr)
      { expr.arg = alias(expr.arg); }

    public void visit(Expr.Star expr)
      { expr.arg = alias(expr.arg); }

    public void visit(Expr.Query expr)
      { expr.arg = alias(expr.arg); }

    public void visit(Expr.PlusPlus expr)
      {
        expr.arg1 = alias(expr.arg1);
        expr.arg2 = alias(expr.arg2);
      }

    public void visit(Expr.StarPlus expr)
      {
        expr.arg1 = alias(expr.arg1);
        expr.arg2 = alias(expr.arg2);
      }

    public void visit(Expr.Is expr)
      {
        expr.arg1 = alias(expr.arg1);
        expr.arg2 = alias(expr.arg2);
      }

    public void visit(Expr.IsNot expr)
      {
        expr.arg1 = alias(expr.arg1);
        expr.arg2 = alias(expr.arg2);
      }


    private void doCompound(Expr expr, Expr[] args)
      {
        for (int i=0;i<args.length;i++)
          args[i] = alias(args[i]);
      }

    //-----------------------------------------------------------------
    //  If the 'sources' table already contains an expression with
    //  the same source as 'expr', return that expression
    //  and remove 'expr' from its list.
    //  Otherwise add 'expr' to 'sources', visit 'expr', and return 'expr'.
    //-----------------------------------------------------------------
    private Expr alias(Expr expr)
      {
        // Do not compact left-recursive expressions
        if (expr.recClass!=null)
          return expr;

        String source = expr.asString;
        Expr found = sources.get(source);
        if (found!=null)
        {
          boolean ok = true;
          while(ok) ok = subs.remove(expr);
          ok = true;
          while(ok) ok = terms.remove(expr);
          return found;
        }
        else
        {
          sources.put(source,expr);
          if (!expr.isNamed)
            expr.accept(this);
          return expr;
        }
      }
  }
}

