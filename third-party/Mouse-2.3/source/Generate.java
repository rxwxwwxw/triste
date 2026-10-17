//=========================================================================
//
//  Part of PEG parser generator Mouse.
//
//  Copyright (C) 2009, 2010, 2011, 2012, 2014, 2015, 2020, 2021
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
//    Version 2.0
//      Total redesign. Some highlights:
//      Added generation of procedures for left-recursion.
//      The class is made static.
//      Names of subexpressions and terminals are assigned by PEG.
//      RefVisitor is replaced by convenience flags of Expr.
//      Methods isTerm, isPred are replaced by convenience flags of Expr.
//    Version 2.1
//      Generate new parsing procedures for left-recursion.
//      If Semantics not supplied, do not generate instantiation
//      and initialization of default class.
//    Version 2.2
//      Added Expr.End in 'ref'.
//      Added Expr.End to Visitors.
//      New code for 'generateSkel'.
//    Version 2.3
//      New code for 'colon' operators in Visitors.
//      Use 'FuncVV' istead of 'SemAction'.
//
//=========================================================================

package mouse;

import mouse.peg.PEG;
import mouse.peg.Expr;
import mouse.peg.Action;
import mouse.peg.RecClass;
import mouse.runtime.SourceFile;
import mouse.utility.CommandArgs;
import mouse.utility.Convert;
import mouse.utility.LineWriter;
import java.io.File;
import java.lang.StringBuilder;
import java.util.Date;
import java.util.Hashtable;
import java.util.TimeZone;
import java.util.Vector;
import java.text.SimpleDateFormat;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  Generate
//
//-------------------------------------------------------------------------
//
//  Generate parser from Parsing Expression Grammar.
//  Optionally, generate skeleton for the corresponding semantics class.
//
//  Invocation
//
//    java mouse.Generate <arguments>
//
//  The <arguments> are specified as options according to POSIX syntax:
//
//    -G <filename>
//       Identifies the file containing the grammar. Mandatory.
//       The <filename> need not be a complete path, just enough to identify
//       the file in current environment. Should include file extension,if any.
//
//    -D <directory>
//       Identifies target directory to receive the generated file(s).
//       Optional. If omitted, files are generated in current work directory.
//       The <directory> need not be a complete path, just enough to identify
//       the directory in current environment. The directory must exist.
//
//    -P <parser>
//       Specifies name of the parser to be generated. Mandatory.
//       Must be an unqualified class name.
//       The tool generates a file named "<parser>.java" in target directory.
//       The file contains definition of Java class <parser>.
//       If target directory already contains a file "<parser<.java",
//       the file is replaced without a warning,
//
//    -S <semantics>
//       Indicates that semantic actions are methods in the Java class <semantics>.
//       Mandatory if the grammar specifies semantic actions.
//       Must be an unqualified class name.
//
//    -p <package>
//       Generate parser as member of package <package>.
//       The semantics class, if specified, is assumed to belong to the same package.
//       Optional. If not specified, both classes belong to unnamed package.
//       The specified package need not correspond to the target directory.
//
//    -r <runtime-package>
//       Generate parser using runtime suport from package <runtime-package>.
//       If not specified, use "mouse.runtime".
//
//    -s Generate skeleton of semantics class. Optional.
//       The skeleton is generated as file "<semantics>.java" in target directory,
//       where <semantics> is the name specified by -S  option.
//       The option is ignored if -S is not specified.
//       If target directory already contains a file "<semantics>.java",
//       the tool is not executed.
//
//    -M Generate memoizing version of the parser.
//
//    -T Generate instrumented ('test') version of the parser.
//
//       (Options -M and -T are mutually exclusive.)
//
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

public class Generate
{
  //=====================================================================
  //
  //  Data
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Input
  //-------------------------------------------------------------------
  static String gramName;   // Grammar file name
  static String gramPath;   // Full path to grammar file
  static String parsName;   // Parser name
  static String semName;    // Semantics name
  static String dirName;    // Output directory
  static String packName;   // Package name
  static String runName;    // Runtime package name
  static boolean memo;      // Generate memo version?
  static boolean test;      // Generate test version?
  static boolean skel;      // Generate semantics skeleton?

  //-------------------------------------------------------------------
  //  Output writer.
  //-------------------------------------------------------------------
  static LineWriter out;

  //-------------------------------------------------------------------
  //  Date stamp.
  //-------------------------------------------------------------------
  static String date;

  //-------------------------------------------------------------------
  //  List of caches to be generated for Memo or Test version.
  //-------------------------------------------------------------------
  static Vector<String>cacheNames  = new Vector<String>();

  //-------------------------------------------------------------------
  //  Cache name to be generated as parameter in calls to service
  //  methods generated for test version (used for tracing).
  //  Set to empty string when generating other versions.
  //-------------------------------------------------------------------
  static String cache = "";

  //-------------------------------------------------------------------
  //  Visitors.
  //-------------------------------------------------------------------
  static ProcVisitor procVisitor = new ProcVisitor();
  static InliVisitor inliVisitor = new InliVisitor();
  static TermVisitor termVisitor = new TermVisitor();
  static RecVisitor  recVisitor  = new RecVisitor();

  //-------------------------------------------------------------------
  //  Counts of generated procedures.
  //-------------------------------------------------------------------
  static int ruleProcs  = 0;
  static int innerProcs = 0;
  static int recProcs   = 0;

  //=====================================================================
  //
  //  Invocation.
  //
  //=====================================================================
  public static void main(String argv[])
    {
      boolean errors = false;

      //---------------------------------------------------------------
      //  Parse arguments.
      //---------------------------------------------------------------
      CommandArgs cmd = new CommandArgs
             (argv,         // arguments to parse
              "MTs",        // options without argument
              "GPSDpr",     // options with argument
               0,0);        // no positional arguments
      if (cmd.nErrors()>0) return;

      //---------------------------------------------------------------
      //  Get options.
      //---------------------------------------------------------------
      gramName = cmd.optArg('G');
      parsName = cmd.optArg('P');
      semName  = cmd.optArg('S');
      dirName  = cmd.optArg('D');
      packName = cmd.optArg('p');
      runName  = cmd.optArg('r');
      test = cmd.opt('T');
      memo = cmd.opt('M');
      skel = cmd.opt('s');

      if (gramName==null)
      {
        System.err.println("Specify -G grammar name.");
        errors = true;
      }

      if (parsName==null)
      {
        System.err.println("Specify -P parser class name.");
        errors = true;
      }

      if (runName==null)
        runName = "mouse.runtime";

      if (semName==null)
      {
        if (skel)
        {
          skel = false;
          System.err.println("Option -s ignored because -S not specified.");
        }
      }

      if (dirName==null)
        dirName = "";
      else
        dirName = dirName + File.separator;

      if (skel)
      {
        File f = new File(dirName + semName + ".java");
        if (f.exists())
        {
          System.err.println("File '" + dirName + semName + ".java' already exists.");
          System.err.println("Remove the file or the -s option.");
          errors = true;
        }
        f = null;
      }

      if (memo & test)
      {
        System.err.println("Options -M and -T are mutually exclusive.");
        errors = true;
      }

      if (errors) return;

      //---------------------------------------------------------------
      //  Parse the grammar and eliminate duplicate expressions.
      //---------------------------------------------------------------
      SourceFile src = new SourceFile(gramName);
      if (!src.created()) return;
      boolean parsed = PEG.parse(src);
      if (!parsed) return;
      PEG.compact();

      //---------------------------------------------------------------
      //  Get full path to grammar file, ready to include in comment.
      //---------------------------------------------------------------
      gramPath = Convert.toComment(src.file().getAbsolutePath());

      //---------------------------------------------------------------
      //  Get date stamp.
      //---------------------------------------------------------------
      SimpleDateFormat df = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
      df.setTimeZone(TimeZone.getTimeZone("GMT"));
      date = df.format(new Date());

      //---------------------------------------------------------------
      //  Set up output.
      //---------------------------------------------------------------
      out = new LineWriter(dirName + parsName + ".java");

      //===================================================================
      //
      //  Generate parser.
      //
      //===================================================================
      //---------------------------------------------------------------
      //  Generate header.
      //---------------------------------------------------------------
      generateHeader();

      //---------------------------------------------------------------
      //  Generate procedures for non-recursive Rules
      //  and their sub-expressions.
      //---------------------------------------------------------------
      out.BOX("Parsing procedures");

      for (Expr.Rule expr: PEG.rules)
        if (expr.recClass==null) generateRule(expr);

      //---------------------------------------------------------------
      //  Generate procedures for left-recursion
      //  and their sub-expressions.
      //---------------------------------------------------------------
      for (RecClass rc: PEG.recClasses)
      {
        out.BOX("Parsing procedures for recursion class " + rc.name);

        generateCommonEntry(rc);

        for (Expr entry: rc.entries)
          generateEntry(entry);

        for (Expr seed: rc.seeds)
          generateSeed(seed,rc);

        for (Expr expr: rc.members)
          expr.accept(recVisitor);
      }

      //---------------------------------------------------------------
      //  Generate Cache objects for Memo or Test version.
      //---------------------------------------------------------------
      if (memo | test)
      {
        out.BOX("Caches");
        generateCaches();
      }

      //---------------------------------------------------------------
      //  Terminate the parser, close output and print statistics.
      //---------------------------------------------------------------
      out.undent();
      out.line("}");
      out.close();

      System.out.println("Parsing procedures:");
      System.out.println(ruleProcs + " rules");
      System.out.println(innerProcs + " inner");
      System.out.println(PEG.terms.size() + " terminals");
      if (!PEG.recClasses.isEmpty())
        System.out.println(recProcs + " procedures for "
            + PEG.recClasses.size() + " left-recursion class(es)");

      //---------------------------------------------------------------
      //  If requested, generate semantics skeleton.
      //---------------------------------------------------------------
      if (skel) generateSkel();
    }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Generator methods.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //=====================================================================
  //
  //  Generate header.
  //
  //=====================================================================
  static void generateHeader()
    {
      String    basePars = runName + ".ParserBase";
      if (memo) basePars = runName + ".ParserMemo";
      if (test) basePars = runName + ".ParserTest";

      out.BOX("This file was generated by Mouse 2.3 at " +
               date + " GMT\nfrom grammar '" + gramPath + "'.");
      out.line("");

      if ( packName!=null)
      {
        out.line("package " + packName + ";");
        out.line("");
      }

      out.line("import " + runName + ".Source;");
      out.line("import " + runName + ".FuncVV;");
      out.line("");
      out.line("public class " + parsName + " extends " + basePars);
      out.line("{");
      if (semName!=null)
      {
        out.line("  " + semName + " sem;");
        out.line("");
      }
      out.indent();

      out.BOX("Initialization");

      out.box("Constructor");
      out.line("public " + parsName + "()");
      out.line("  {");

      if (semName!=null)
      {
        out.line("    sem = new " + semName + "();");
        out.line("    sem.rule = this;");
      }
      else
        out.line("    sem = null;");
      out.line("    super.sem = sem;");
      if (memo | test)
        out.line("    caches = cacheList;");
      out.line("  }");
      out.line("");

      out.box("Run the parser");
      out.line("public boolean parse(Source src)");
      out.line("  {");
      out.line("    super.init(src);");
      if (semName!=null)
        out.line("    sem.init();");
      out.line("    boolean result = " + PEG.rules.elementAt(0).name + "();");
      out.line("    closeParser(result);");
      out.line("    return result;");
      out.line("  }");
      out.line("");

      if (semName!=null)
      {
        out.box("Get semantics");
        out.line("public " + semName+ " semantics()");
        out.line("  { return sem; }");
        out.line("");
      }
    }

  //=====================================================================
  //
  //  Generate procedure for non-recursive Rule 'rule'.
  //
  //=====================================================================
  static void generateRule(Expr.Rule rule)
    {
      out.Box(Convert.toComment(rule.asString));
      out.line("boolean " + rule.name + "()");
      openBracket();

      cache = test? rule.name : "";
      String diag = rule.diagName!=null? ",\"" + Convert.toStringLit(rule.diagName) + "\"" : "";

      if (memo | test)
        out.line("if (saved(\"" + rule.name + "\"" + diag + "," + rule.name + ")) return reuse();");
      else
        out.line("begin(\"" + rule.name + "\"" + diag + ");");

      //-------------------------------------------------------------
      //  Special case: single expression on right-hand side
      //  and no 'onFail' action.
      //-------------------------------------------------------------
      if ( rule.args.length==1 && rule.onFail[0]==null)
      {
        Expr e = rule.args[0];
        Action act = rule.onSucc[0];
        inline(e,"reject(" + cache + ")");
        if (act==null)
          out.line("return accept(" + cache + ");");
        else if (act.and)
        {
          out.line("if (sem." + act.name + "()) return accept(" + cache + ");");
          out.line("return reject(" + cache + ");");
        }
        else
        {
          out.line("sem." + act.name + "();");
          out.line("return accept(" + cache + ");");
        }
      }

      //-------------------------------------------------------------
      //  General case.
      //-------------------------------------------------------------
      else
      {
        for (int i=0;i<rule.args.length;i++)
        {
          Action succ = rule.onSucc[i];
          Action fail = rule.onFail[i];

          if (succ==null)
            out.line("if (" + ref(rule.args[i]) + ") return accept(" + cache + ");");
          else if (succ.and)
          {
            out.line("if (" + ref(rule.args[i]) + ")");
            out.line("{ if (sem." + succ.name + "()) return accept(" + cache + "); }");
          }
          else
          {
            out.line("if (" + ref(rule.args[i]) + ")");
            out.line("{ sem." + succ.name + "(); return accept(" + cache + "); }");
          }

          if (fail!=null)
            out.line("sem." + fail.name + "();");

        }
        out.line("return reject(" + cache + ");");
      }

      closeBracket();
      out.line("");

      if (test && rule.diagName!=null) generateCache(rule.name,rule.diagName);
      else if (memo|test) generateCache(rule.name);
      generateSubs();
      ruleProcs++;
   }

  //=====================================================================
  //
  //  Generate procedure for non-recursive subexpression 'expr'.
  //
  //=====================================================================
  static void generateSub(Expr expr)
    {
      String name = expr.name;

      out.box(name + " = " + Convert.toComment(expr.asString));
      out.line("boolean " + name + "()");
      openBracket();

      cache = test? name : "";
      String diag = expr.isPred? ",\"" + diagPred(expr) + "\"" : "";

      if (memo | test)
        out.line("if (saved(\"" + expr.name + "\"" + diag + "," + expr.name + ")) "
                  + (expr.isPred? "return reusePred();" : "return reuseInner();"));
      else
        out.line("begin(\"" + expr.name + "\"" + diag + ");");

      expr.accept(procVisitor);
      closeBracket();
      out.line("");

      if (memo|test) generateCache(expr.name);
      innerProcs++;
    }

  //=====================================================================
  //
  //  Generate procedure 'entry' to start recursive ascent
  //
  //=====================================================================
  static void generateEntry(Expr entry)
    {
      RecClass rc = entry.recClass;
      Expr.Rule rule = (Expr.Rule) entry;

      out.Box("Enter " + entry.name + " in recursion class " + rc.name);
      out.line("boolean " + entry.name + "()");
      openBracket();

      cache = test? entry.name : "";
      String diag = rule.diagName!=null? ",\"" + Convert.toStringLit(rule.diagName) + "\"" : "";

      if (memo | test)
        out.line("if (saved(\"" + entry.name + "\"" + diag + "," + entry.name + ")) return reuse();");
      else
        out.line("begin(\"" + entry.name + "\"" + diag + ");");

      out.line("if ($$"+rc.name+"()) return accept();");
      out.line("return reject("+cache+");");
      closeBracket();
      out.line("");

      if (memo|test) generateCache(entry.name);
      generateSubs();
      recProcs++;
    }

  //=====================================================================
  //
  //  Generate common procedure $$C to start recursive ascent
  //
  //=====================================================================
  static void generateCommonEntry(RecClass rc)
    {
      out.Box("Common entry to recursion class " + rc.name);
      out.line("boolean $$" + rc.name + "()");
      openBracket();
      out.line("beginAsc();");
      out.line("boolean ok =");

      for (int i=0; i<rc.seeds.size(); i++)
        out.line("  "+rc.name+"$"+rc.seeds.elementAt(i).name+"()"+(i==rc.seeds.size()-1? ";" : " ||"));

      out.line("endAsc();");
      out.line("return ok;");
      closeBracket();
      out.line("");
    }

  //=====================================================================
  //
  //  Generate procedure for seed 'seed'.
  //
  //=====================================================================
  static void generateSeed(Expr seed, RecClass rc)
    {
      String name = seed.name;
      String procName = rc.name+"$"+name;

      cache = test? procName : "";
      String cCache = test? ("," + procName) : "";

      out.Box("Ascent from seed " + comment(seed) + " via " + commentClimb(seed,rc) +".");
      out.line("boolean " + procName + "()");
      openBracket();
      out.line("begin(\"" + procName + "\",\"" + procName + "\"" + cCache + ");");
      out.line("if (!" + ref(seed) + ") return reject(" + cache + ");");
      generateClimb(seed,rc,cache);
      out.line("return reject("+cache+");");
      closeBracket();
      out.line("");

      if (test) generateCache(procName);
      generateSubs();
      recProcs++;
    }

  //=====================================================================
  //
  //  Generate ascent procedure for Rule.
  //
  //=====================================================================
  static void generateRuleAscent(Expr.Rule expr)
    {
      String procName = "$" + expr.name;
      RecClass rc = expr.recClass;

      out.Box("Ascent from " + comment(expr) + " via " + commentClimb(expr,rc) + ".");
      out.line("boolean " + procName + "(FuncVV act)");
      openBracket();

      cache = test? procName : "";
      String cCache = test? ("," + procName) : "";

      out.line("begin(\"" + procName + "\",\"" + expr.name + "\"" + cCache + ");");
      out.line("setAction(act);");
      generateClimb(expr,rc,cache);
      out.line("return reject("+cache+");");
      closeBracket();
      out.line("");

      if (test) generateCache(procName);
      generateSubs();
      recProcs++;
    }

  //=====================================================================
  //
  //  Generate ascent procedure for Choice subexpression.
  //
  //=====================================================================
  static void generateChoiceAscent(Expr.Choice expr)
    {
      String procName = "$" + expr.name;
      RecClass rc = expr.recClass;

      out.Box("Ascent from " + expr.name + " = " + comment(expr) + " via " + commentClimb(expr,rc) + ".");
      out.line("boolean " + procName + "()");
      openBracket();

      cache = test? procName : "";
      String cCache = test? ("," + procName) : "";

      out.line("begin(\"" + procName + "\",\"" + expr.name + "\"" + cCache + ");");
      generateClimb(expr,rc,cache);
      out.line("return rejectInner("+cache+");");
      closeBracket();
      out.line("");

      if (test) generateCache(procName);
      generateSubs();
      recProcs++;
   }

  //=====================================================================
  //
  //  Generate ascent procedure for Sequence subexpression.
  //
  //=====================================================================
  static void generateSequenceAscent(Expr.Sequence expr)
    {
      String procName = "$" + expr.name;
      RecClass rc = expr.recClass;

      out.Box("Ascent from " + expr.name + " = " + comment(expr) + " via " + commentClimb(expr,rc) + ".");
      out.line("boolean " + procName + "()");
      openBracket();

      cache = test? procName : "";
      String cCache = test? ("," + procName) : "";

      out.line("begin(\"" + procName + "\",\"" + expr.name + "\"" + cCache + ");");
       for (int i=1;i<expr.args.length;i++)
        out.line("if (!"+ref(expr.args[i])+") return rejectInner("+cache+");");
      generateClimb(expr,rc,cache);
      out.line("return rejectInner("+cache+");");
      closeBracket();
      out.line("");

      if (test) generateCache(procName);
      generateSubs();
      recProcs++;
    }

  //=====================================================================
  //
  //  Generate Caches - for memo or test version
  //
  //=====================================================================
  static void generateCaches()
    {
      //---------------------------------------------------------------
      //  If test version:
      //  create Cache objects for terminals.
      //---------------------------------------------------------------
      if (test)
      {
        out.box("Caches for terminals");
        out.line("");

        for (Expr expr: PEG.terms)
        {
          out.line("Cache " + expr.name + " = new Cache(\""
                    + Convert.toStringLit(expr.asString) + "\");") ;
          cacheNames.add(expr.name);
        }
      }

      //---------------------------------------------------------------
      //  Create cache array.
      //---------------------------------------------------------------
      out.line("");
      out.box("List of Cache objects");
      out.line("");

      out.line("Cache[] cacheList =");
      out.line("{");
      out.indent();
      StringBuilder sb = new StringBuilder();
      for (String name: cacheNames)
      {
        if (sb.length()+name.length()>65)
        {
          out.line(sb.toString());
          sb = new StringBuilder();
        }

        sb.append(name + ",");
      }
      sb.deleteCharAt(sb.length()-1);
      out.line(sb.toString());

      out.undent();
      out.line("};");
    }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Auxiliary methods
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //=====================================================================
  //
  //  Generate procedures for non-recursive subexpressions.
  //
  //-------------------------------------------------------------------
  //  Names of subexpressions that will have procedures are added
  //  to 'subs' by method 'ref' that creates their invocations.
  //  Note that not all subexpressions need procedures, as they may be
  //  handled inline. The procedures are generated by a call to
  //  'generateSubs', usually after procedure to parent expression.
  //  Note that procedures thus generated may add to 'subs'.
  //  The entries for generated procedures are not removed from 'subs',
  //  as that creates problem of 'concurrent modification' in Java.
  //  Instead, the count of created procedures is kept in 'done'.
  //=====================================================================
  static Vector<Expr> subs = new Vector<Expr>();
  static int done = 0;

  static void generateSubs()
    {
      int toDo = subs.size();
      while (done<toDo)
      {
        for (int i=done;i<toDo;i++)
        {
          Expr expr = subs.elementAt(i);
          generateSub(expr);
        }
        done = toDo;
        toDo = subs.size(); // We probably added subexprs of subexprs!
      }
   }

  //=====================================================================
  //  Generate invocation of 'expr'.
  //  Returns the string to be generated as invocation of 'expr'.
  //  Enters in 'subs' the subexpressions that need procedures.
  //=====================================================================
  private static String ref(Expr expr)
    {
      if (expr instanceof Expr.End) return "aheadNot()";
      if (expr.isTerm) return "next" + termCall(expr);
      if (expr.isSub && expr.recClass==null && !subs.contains(expr))
        subs.add(expr);
      return expr.name + "()";
    }

  //=====================================================================
  //  Generate cache.
  //=====================================================================
  private static void generateCache(String name)
    {
      cacheNames.add(name);
      if (memo)
        out.line("Cache " + name + " = new Cache();") ;
      if (test)
        out.line("Cache " + name + " = new Cache(\"" + name + "\");") ;
      out.line("");
      }

  private static void generateCache(String name, String title)
    {
      cacheNames.add(name);
      out.line("Cache " + name + " = new Cache(\"" + title + "\");") ;
      out.line("");
    }

  //=====================================================================
  //  Common for left-recursion procedures.
  //=====================================================================
  //---------------------------------------------------------------
  //  Generate code to try ascent procedures for all expressions
  //  in recursion class 'rc' that have 'expr' as first.
  //---------------------------------------------------------------
  private static void generateClimb(Expr expr, RecClass rc, String cache)
    {
      for (Expr prev: rc.haveAsFirst(expr))
      {
        if (prev.isRule)
        {
          Expr.Rule rule = (Expr.Rule)prev;
          int i = alt(rule,expr);
          String act;
          if (rule.onSucc[i]==null) act = "empty$$";
          else act = "()->sem." + rule.onSucc[i].name + "()";

          out.line("if ($" + prev.name + "("+act+")) return accept("+cache+");");
        }
        else
          out.line("if ($" + prev.name + "()) return accept("+cache+");");
      }
      if (rc.entries.contains(expr))
        out.line("if (endGrow()) return accept("+cache+");");
    }

  //---------------------------------------------------------------
  //  Return list of names of expressions in recursion class 'rc'
  //  that have 'expr' as first.
  //---------------------------------------------------------------
  private static String commentClimb(Expr expr, RecClass rc)
    {
      StringBuilder sb = new StringBuilder();
      String or = "";
      for (Expr prev: rc.haveAsFirst(expr))
        {
          sb.append(or + prev.name);
          or = " or ";
        }
      return sb.toString();
    }

  //---------------------------------------------------------------
  //  Find which alternative in 'rule' is 'expr'.
  //---------------------------------------------------------------
  private static int alt(Expr.Rule rule, Expr expr)
    {
      for (int i=0;i<rule.args.length;i++)
        if (rule.args[i]==expr) return i;
      throw new Error("invalid alternative");
    }

  //=====================================================================
  //  Comments and diagnostic texts.
  //=====================================================================
  //---------------------------------------------------------------
  //  Expr as comment
  //---------------------------------------------------------------
  private static String comment(Expr e)
    {
      if (e.isRule) return e.name;
      else return Convert.toComment(e.asString);
    }

  //-------------------------------------------------------------------
  //  Get diagnostic string for a Predicate
  //-------------------------------------------------------------------
  static String diagPred(Expr expr)
  {
    if (expr instanceof Expr.And and)
    {
      Expr arg = and.arg;
      if (arg.isRule)
      {
        Expr.Rule rule = (Expr.Rule)arg;
        return diagName(rule);
      }
      else
        return Convert.toStringLit(arg.asString);
    }

    else if (expr instanceof Expr.Not not)
    {
      Expr arg = not.arg;
      if (arg.isRule)
      {
        Expr.Rule rule = (Expr.Rule)arg;
        return "not " + diagName(rule);
      }
      else if (arg instanceof Expr.Any)
        return "end of text";
      else
        return "not " + Convert.toStringLit(arg.asString);
    }

    else throw new Error("SNOC");
  }

  //-------------------------------------------------------------------
  //  Get diagnostic name of a Rule - used only in 'diagPred' above.
  //-------------------------------------------------------------------
  static String diagName(Expr.Rule rule)
    {
      if (rule.diagName==null) return rule.name;
      else return Convert.toStringLit(rule.diagName);
    }

  //=====================================================================
  //  Writer shortcuts.
  //=====================================================================
  //---------------------------------------------------------------
  //  Write { surrounded by indents.
  //---------------------------------------------------------------
  private static void openBracket()
    {
      out.indent();
      out.line("{");
      out.indent();
    }

  //---------------------------------------------------------------
  //  Write } surrounded by undents.
  //---------------------------------------------------------------
  private static void closeBracket()
    {
      out.undent();
      out.line("}");
      out.undent();
    }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Generate semantics skeleton
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //-------------------------------------------------------------------
  //  All actions specifed in the grammar are listed in 'actions'.
  //  The comment for each action is in 'comments'.
  //  It can consist of several lines, one line for each use of the action.
  //  Each line has the form 'failed? rule = rhs' where text 'failed'
  //  appears only for action 'onFail', 'rule' is name of Rule containing
  //  the action, and 'rhs' is the alternative to which the action is attached.
  //-------------------------------------------------------------------
  static Vector<Action> actions  = new Vector<Action>();
  static Hashtable<String,String> comments = new Hashtable<String,String>();

  static void generateSkel()
    {
      //---------------------------------------------------------------
      //  Collect semantic actions.
      //---------------------------------------------------------------
      for (Expr.Rule rule: PEG.rules)
      {
        for (int i=0;i<rule.args.length;i++)
        {
          if (rule.onSucc[i]!=null)
            saveAction(rule.onSucc[i],rule,rule.args[i],"");
          if (rule.onFail[i]!=null)
            saveAction(rule.onFail[i],rule,rule.args[i],"failed ");
        }
      }

      //---------------------------------------------------------------
      //  Set up output.
      //---------------------------------------------------------------
      out = new LineWriter(dirName + semName + ".java");

      //---------------------------------------------------------------
      //  Create header.
      //---------------------------------------------------------------
      out.BOX("This skeleton was generated by Mouse 2.3 at " + date + " GMT\n" +
               "from grammar '" + gramPath + "'.");
      out.line("");

      if ( packName!=null)
      {
        out.line("package " + packName + ";");
        out.line("");
      }

      out.line("class " + semName + " extends " + runName + ".SemanticsBase");
      out.line("{");

      out.indent();

      //---------------------------------------------------------------
      //  Create semantic procedures.
      //---------------------------------------------------------------
      for (Action act: actions)
      {
        out.box(comments.get(act.name));
        out.line((act.and? "boolean " : "void ") + act.name + "()");
        out.line("  {" + (act.and? " return true; ":"") + "}");
        out.line("");
      }

      //---------------------------------------------------------------
      //  Terminate the class and close output.
      //---------------------------------------------------------------
      out.undent();
      out.line("}");
      out.close();

      System.out.println(actions.size() + " semantic procedures");
    }

  //-------------------------------------------------------------------
  //  Save action 'act' for alternative 'rhs' of 'rule',
  //  with comment prefixed by 'prefix'.
  //-------------------------------------------------------------------
  private static void saveAction
    (Action act, Expr.Rule rule, Expr rhs, String prefix)
    {
      // Create comment for this occurrence
      String comment = prefix + rule.name + " = ";
      if (rhs.isRule) comment += rhs.name;
      else comment += Convert.toComment(rhs.asString);

      // If there is no entry for this action, create it
      String found = comments.get(act.name);
      if (found==null)
      {
        actions.add(act);
        comments.put(act.name,comment);
      }

      // Otherwise add line to existing comment
      else
        comments.put(act.name,found + "\n" + comment);
    }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  ProcVisitor - visitor to generate body of parsing procedure
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  static class ProcVisitor extends mouse.peg.Visitor
  {
    public void visit(Expr.Rule expr)
      {throw new Error("SNOC" + expr.name); }

    public void visit(Expr.Choice expr)
      {
        for (Expr e: expr.args)
          out.line("if (" + ref(e) + ") return acceptInner(" + cache + ");");
        out.line("return rejectInner(" + cache + ");");
      }

    public void visit(Expr.Sequence expr)
      {
        for (Expr e: expr.args)
          inline(e,"rejectInner(" + cache + ")");
        out.line("return acceptInner(" + cache + ");");
      }

    public void visit(Expr.And expr)
      {
        out.line("if (!" + ref(expr.arg) + ") return rejectPred(" + cache + ");");
        out.line("return acceptPred(" + cache + ");");
      }

    public void visit(Expr.Not expr)
      {
        out.line("if (" + ref(expr.arg) + ") return rejectPred(" + cache + ");");
        out.line("return acceptPred(" + cache + ");");
      }

    public void visit(Expr.Plus expr)
      {
        out.line("if (!" + ref(expr.arg) + ") return rejectInner(" + cache + ");");
        out.line("while (" + ref(expr.arg) + ");");
        out.line("return acceptInner(" + cache + ");");
      }

    public void visit(Expr.Star expr)
      {
        out.line("while (" + ref(expr.arg) + ");");
        out.line("return acceptInner(" + cache + ");");
      }

    public void visit(Expr.Query expr)
      {
        out.line(ref(expr.arg) + ";");
        out.line("return acceptInner(" + cache + ");");
      }

    public void visit(Expr.PlusPlus expr)
      {
        out.line("if (" + ref(expr.arg2) + ") return rejectInner(" + cache + ");");
        out.line("do if (!" + ref(expr.arg1) + ") return rejectInner(" + cache + ");");
        out.line("  while (!" + ref(expr.arg2) + ");");
        out.line("return acceptInner(" + cache + ");");
      }

    public void visit(Expr.StarPlus expr)
      {
        out.line("while (!" + ref(expr.arg2) + ")");
        out.line("  if (!" + ref(expr.arg1) + ") return rejectInner(" + cache + ");");
        out.line("return acceptInner(" + cache + ");");
      }

    public void visit(Expr.Is expr)
      {
        out.line("if (!is(false,()->" + ref(expr.arg1) + ",()->" + ref(expr.arg2) + ")) return rejectInner(" + cache + ");");
        out.line("return acceptInner(" + cache + ");");
      }

    public void visit(Expr.IsNot expr)
      {
        out.line("if (!is(true,()->" + ref(expr.arg1) + ",()->" + ref(expr.arg2) + ")) return rejectInner(" + cache + ");");
        out.line("return acceptInner(" + cache + ");");
      }

    public void visit(Expr.Ref expr)
      { throw new Error("Should not occur"); }

    public void visit(Expr.StringLit expr)
      { doTerm(expr); }

    public void visit(Expr.CharClass expr)
      { doTerm(expr); }

    public void visit(Expr.Range expr)
      { doTerm(expr); }

    public void visit(Expr.Any expr)
      { doTerm(expr); }

    public void visit(Expr.End expr)
      { doTerm(expr); }

    private void doTerm(Expr expr)
      {
        out.line("if (!" + ref(expr)+ ") return rejectInner(" + cache + ");");
        out.line("return acceptInner(" + cache + ");");
      }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  InliVisitor - visitor to generate inline procedure
  //
  //  (Inline procedure falls through on success
  //   or returns reject() on failure.)
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  static void inline(Expr expr, String rej)
    {
      reject = rej;
      expr.accept(inliVisitor);
    }

  static String reject;

  static class InliVisitor extends mouse.peg.Visitor
  {
    public void visit(Expr.Rule expr)
      {
        if (!expr.fal)
          out.line(expr.name + "();");
        else
          out.line("if (!" + expr.name + "()) return " + reject + ";");
      }

    public void visit(Expr.Choice expr)
      {
        Expr arg = expr.args[0];
        out.line("if (!" + ref(arg));
        for (int i=1;i<expr.args.length;i++)
        {
          arg = expr.args[i];
          out.line(" && !" + ref(arg));
        }
        out.line("   ) return " + reject + ";");
      }

    public void visit(Expr.Sequence expr)
      {
        for (Expr arg: expr.args)
          arg.accept(inliVisitor);
      }

    public void visit(Expr.And expr)
      {
        Expr arg = expr.arg;
        if (arg.isTerm)
          out.line("if (!ahead" + termCall(arg) + ") return " + reject + ";");
        else
          out.line("if (!" + ref(expr) + ") return " + reject + ";");
      }

    public void visit(Expr.Not expr)
      {
        Expr arg = expr.arg;
        if (arg.isTerm)
          out.line("if (!aheadNot" + termCall(arg) + ") return " + reject + ";");
        else
          out.line("if (!" + ref(expr) + ") return " + reject + ";");
      }

    public void visit(Expr.Plus expr)
      {
        out.line("if (!" + ref(expr.arg) + ") return " + reject + ";");
        out.line("while (" + ref(expr.arg) + ");");
      }

    public void visit(Expr.Star expr)
      { out.line("while (" + ref(expr.arg) + ");"); }

    public void visit(Expr.Query expr)
      { out.line(ref(expr.arg) + ";"); }

    public void visit(Expr.PlusPlus expr)
      {
        out.line("if (" + ref(expr.arg2) + ") return " + reject + ";");
        out.line("do if (!" + ref(expr.arg1) + ") return " + reject + ";");
        out.line("  while (!" + ref(expr.arg2) + ");");
      }

    public void visit(Expr.StarPlus expr)
      {
        out.line("while (!" + ref(expr.arg2) + ")");
        out.line("  if (!" + ref(expr.arg1) + ") return " + reject + ";");
      }

    public void visit(Expr.Is expr)
      {
        out.line("if (!is(true,()->" + ref(expr.arg1) + ",()->" + ref(expr.arg2) + ")) return " + reject + ";");
      }

    public void visit(Expr.IsNot expr)
      {
        out.line("if (!is(false,()->" + ref(expr.arg1) + ",()->" + ref(expr.arg2) + ")) return " + reject + ";");
      }

    public void visit(Expr.Ref expr)
      { throw new Error("Should not occur"); }

    public void visit(Expr.StringLit expr)
      { doTerm(expr); }

    public void visit(Expr.CharClass expr)
      { doTerm(expr); }

    public void visit(Expr.Range expr)
      { doTerm(expr); }

    public void visit(Expr.Any expr)
      { doTerm(expr); }

    public void visit(Expr.End expr)
      { doTerm(expr); }

    private void doTerm(Expr expr)
      { out.line("if (!" + ref(expr)+ ") return " + reject + ";"); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  TermVisitor
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //-------------------------------------------------------------------
  //  This procedure returns kernel of a call to terminal processing.
  //-------------------------------------------------------------------
  static String termCall(Expr expr)
    {
      termVisitor.cache = test? (expr.name) : "";
      termVisitor.ccache = test? ("," + expr.name) : "";
      expr.accept(termVisitor);
      return termVisitor.result;
    }

  static class TermVisitor extends mouse.peg.Visitor
  {
    //-----------------------------------------------------------------
    //  Result from Visitor
    //-----------------------------------------------------------------
    String result;

    //-----------------------------------------------------------------
    //  Input to Visitor: references to cache
    //-----------------------------------------------------------------
    String cache;
    String ccache;

    public void visit(Expr.StringLit expr)
      {
        String cLit = Convert.toCharLit(expr.s.charAt(0));
        String sLit = Convert.toStringLit(expr.s);
        if (expr.s.length()==1)
          result = "('" + cLit + "'" + ccache + ")";
        else
          result = "(\"" + sLit + "\"" + ccache + ")";
      }

    public void visit(Expr.CharClass expr)
      {
        String cLit = Convert.toCharLit(expr.s.charAt(0));
        String sLit = Convert.toStringLit(expr.s);
        if (expr.s.length()==1)
        {
          if (expr.hat)
            result = "Not(\'" + cLit + "\'" + ccache + ")";
          else
           result = "(\'" + cLit + "\'" + ccache + ")";
        }
        else
        {
          if (expr.hat)
            result = "NotIn(\"" + sLit + "\"" + ccache + ")";
          else
            result = "In(\"" + sLit + "\"" + ccache + ")";
        }
      }

    public void visit(Expr.Range expr)
      {
        String aLit = Convert.toCharLit(expr.a);
        String zLit = Convert.toCharLit(expr.z);
        result = "In('"+ aLit + "','" + zLit + "'" + ccache + ")";
      }

    public void visit(Expr.Any expr)
      { result = "(" + cache + ")"; }

    public void visit(Expr.End expr)
      { throw new Error("should not be called for " + expr.name); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  RecVisitor - visitor to generate left-recursive procedure
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  static class RecVisitor extends mouse.peg.Visitor
  {
    public void visit(Expr.Rule expr)
      { generateRuleAscent(expr); }

    public void visit(Expr.Choice expr)
      { generateChoiceAscent(expr); }

    public void visit(Expr.Sequence expr)
      { generateSequenceAscent(expr); }

    // Left recursion not supported
    public void visit(Expr.And expr) { snoc(); }
    public void visit(Expr.Not expr) { snoc(); }
    public void visit(Expr.Plus expr) { snoc(); }
    public void visit(Expr.Star expr) { snoc(); }
    public void visit(Expr.Query expr) { snoc(); }
    public void visit(Expr.PlusPlus expr) { snoc(); }
    public void visit(Expr.StarPlus expr) { snoc(); }
    public void visit(Expr.Is expr) { snoc(); }
    public void visit(Expr.IsNot expr) { snoc(); }

    // Removed from grammar at this stage
    public void visit(Expr.Ref expr) { snoc(); }

    // Terminals can not be recursive
    public void visit(Expr.StringLit expr) { snoc(); }
    public void visit(Expr.CharClass expr) { snoc(); }
    public void visit(Expr.Range expr) { snoc(); }
    public void visit(Expr.Any expr) { snoc(); }
    public void visit(Expr.End expr) { snoc(); }

    private void snoc()
      { throw new Error("Should not occur"); }
  }
}