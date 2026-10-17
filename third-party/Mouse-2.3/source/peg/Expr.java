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
//    'source' renamed to 'asString' and modified to contain
//    reconstructed source in 'true' form.
//  Version 1.3
//    Attributes made public (for access from Generate).
//    Removed 'position' (unused).
//  Version 1.4
//    Added 'hat' field to 'CharClass'.
//    Added subclasses 'PlusPlus' and 'StarPlus'.
//  Version 1.5.1
//    (Steve Owens) Removed unused import.
//  Version 2.0
//    Renamed component expressions to 'arg's.
//    Added 'recClass', 'isRule', 'isSub', 'isRef', 'isTerm', 'isPred'.
//    Changed attributes.
//    Changed 'bind' and 'asString' from method to field.
//    Added method 'toPrint'.
//  Version 2.1
//    Changed attributes again, to 'WF', 'nul', 'fal'.
//  Version 2.2 - changes used by updated Explorer
//    Added class Expr.End.
//    Revised attributes.
//    New flag 'isNamed'.
//    New fields 'firstTerms', firstTailTerms','Tail'.
//    New methods 'toPrint', 'toShort', 'to Named'.
//  Version 2.3
//    New subclasses 'Is' and 'IsNot'.
//    Removed 'firstTailTerms'. They belong to Tail.
//    Removed 'final' modifier from parameters to subclass creators.
//    New constructor for Rule - creates dummy Rule for PEG's RefVisitor.

//
//=========================================================================

package mouse.peg;

import mouse.explorer.Tail;
import mouse.utility.Convert;
import java.util.BitSet;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  Class Expr
//
//  Objects of class Expr represent parsing expressions.
//  Expr is an abstract class, with concrete subclasses representing
//  different kinds of expressions:
//
//  - Expr.Rule - name = expression
//  - Expr.Choice - two or more expressions separated by '/'.
//  - Expr.Sequence - sequence of two or more expressions.
//  - Expr.And - expression preceded by '&'.
//  - Expr.Not - expression preceded by '!'.
//  - Expr.Plus - expression followed by '+'.
//  - Expr.Star - expression followed by '*'.
//  - Expr.Query - expression followed by '?'.
//  - Expr.PlusPlus - two expressions separated by by '++'.
//  - Expr.StarPlus - two expressions separated by by '*+'.
//  - Expr.Is - two expressions separated by by ':'.
//  - Expr.IsNot - two expressions separated by by ':!'.
//  - Expr.Ref - reference to another expression.
//  - Expr.StringLit - string literal.
//  - Expr.CharClass - character class.
//  - Expr.Range - character from range.
//  - Expr.Any - any character.
//  - Expr.End - expression '!_', meaning end of input.
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

public abstract class Expr
{
  //=====================================================================
  //
  //  Common data.
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Name.
  //-------------------------------------------------------------------
  public String name;

  //-------------------------------------------------------------------
  //  Index in vectors and matrices.
  //-------------------------------------------------------------------
  public int index;

  //-------------------------------------------------------------------
  //  Recursion class if the expression is left-recursive.
  //  Otherwise null.
  //-------------------------------------------------------------------
  public RecClass recClass = null;

  //-------------------------------------------------------------------
  //  Reconstructed source text in 'true' form:
  //  with all literals converted to charaters they represent.
  //  (Literals in the actual source may contain escapes.)
  //-------------------------------------------------------------------
  public String asString;

  //-------------------------------------------------------------------
  //  Attributes: defaults.
  //-------------------------------------------------------------------
  public boolean def = false; // Defines a terminal string
  public boolean nul = false; // Can generate null string
  public boolean adv = false; // Can generate non-null string
  public boolean end = false; // end-of-input in every generated string
  public boolean fal = false; // Parsing procedure may fail

  //-------------------------------------------------------------------
  //  Convenience flags: defaults.
  //-------------------------------------------------------------------
  public boolean isRule = false;
  public boolean isSub  = false;
  public boolean isTerm = false;
  public boolean isRef  = false;
  public boolean isPred = false;
  public boolean isNamed = false;

  //-------------------------------------------------------------------
  //  For use in Explorer.
  //-------------------------------------------------------------------
  public BitSet firstTerms = new BitSet();  // First terminals
  public Tail tail;                         // The Tail

  //-------------------------------------------------------------------
  //  Binding strength.
  //-------------------------------------------------------------------
  public int bind = 4;        // Default for terminals and Rule name

  //=====================================================================
  //
  //  Common methods.
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Accept visitor.
  //-------------------------------------------------------------------
  public abstract void accept(Visitor v);

  //-------------------------------------------------------------------
  //  Printable representations of Expr:
  //  toPrint - fully reconstructed source;
  //  toShort - name if present, otherwise reconstructed source;
  //  toNamed - 'name = ' follwed by reconstructed source.
  //-------------------------------------------------------------------
  public String toPrint()
    { return Convert.toPrint(asString); }

  public String toShort()
    {
      if (isNamed) return name;
      else return Convert.toPrint(asString);
    }

  public String toNamed()
    {
      if (isRule) return Convert.toPrint(asString);
      else return name + " = " + Convert.toPrint(asString);
    }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Rule
  //
  //  Represents rule of the form name = right-hand-side.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class Rule extends Expr
  {
    //-----------------------------------------------------------------
    //  Data.
    //  An absent action is represented by null (NOT empty String).
    //-----------------------------------------------------------------
    public Expr[] args;       // Expressions on the right-hand side.
    public Action[] onSucc;   // Actions for components of Expr.
    public Action[] onFail;
    public String diagName;   // Diagnostic name (null if none).

    //-----------------------------------------------------------------
    //  Create the object with specified components.
    //-----------------------------------------------------------------
    public Rule
      ( String name, String diagName,
        Expr[] args, Action[] onSucc, Action[] onFail)
      {
        this.name     = name;
        this.diagName = diagName;
        this.args     = args;
        this.onSucc   = onSucc;
        this.onFail   = onFail;
        isRule = true;
        isNamed = true;
      }

    //-----------------------------------------------------------------
    //  Create dummy object - used in PEG's RefVisitor.
    //-----------------------------------------------------------------
    public Rule()
      {}

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Expr.Choice
  //
  //  Represents expression 'arg-1 / arg-2 / ... / arg-n' where n>1.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class Choice extends Expr
  {
    //-----------------------------------------------------------------
    //  Data
    //-----------------------------------------------------------------
    public Expr[] args;    // The args

    //-----------------------------------------------------------------
    //  Create object with specified args.
    //-----------------------------------------------------------------
    public Choice(Expr[] args)
      {
        this.args = args;
        isSub = true;
        if (args.length>1) bind  = 0;
      }

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Expr.Sequence
  //
  //  Represents expression "arg-1 arg-2  ... arg-n" where n>1.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class Sequence extends Expr
  {
    //-----------------------------------------------------------------
    //  Data
    //-----------------------------------------------------------------
    public Expr[] args;  // The 'args'

    //-----------------------------------------------------------------
    //  Create object with specified 'args'.
    //-----------------------------------------------------------------
    public Sequence(Expr[] args)
      {
        this.args = args;
        isSub = true;
        bind  = 1;
      }

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Expr.And
  //
  //  Represents expression '&arg'.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class And extends Expr
  {
    //-----------------------------------------------------------------
    //  Data
    //-----------------------------------------------------------------
    public Expr arg;

    //-----------------------------------------------------------------
    //  Create object with specified 'arg'.
    //-----------------------------------------------------------------
    public And(Expr arg)
      {
        this.arg = arg;
        isSub  = true;
        isPred = true;
        bind   = 2;
      }

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Expr.Not
  //
  //  Represents expression '!arg'.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class Not extends Expr
  {
    //-----------------------------------------------------------------
    //  Data
    //-----------------------------------------------------------------
    public Expr arg;

    //-----------------------------------------------------------------
    //  Create object with specified 'arg'.
    //-----------------------------------------------------------------
    public Not(Expr arg)
      {
        this.arg = arg;
        isSub  = true;
        isPred = true;
        bind   = 2;
      }

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Expr.Plus
  //
  //  Represents expression 'arg+'.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class Plus extends Expr
  {
    //-----------------------------------------------------------------
    //  Data
    //-----------------------------------------------------------------
    public Expr arg;

    //-----------------------------------------------------------------
    //  Create object with specified 'arg'.
    //-----------------------------------------------------------------
    public Plus(Expr arg)
      {
        this.arg = arg;
        isSub = true;
        bind  = 3;
      }

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Expr.Star
  //
  //  Represents expression 'arg*'.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class Star extends Expr
  {
    //-----------------------------------------------------------------
    //  Data
    //-----------------------------------------------------------------
    public Expr arg;

    //-----------------------------------------------------------------
    //  Create object with specified 'arg'.
    //-----------------------------------------------------------------
    public Star(Expr arg)
      {
        this.arg = arg;
        isSub = true;
        bind  = 3;
      }

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Expr.Query
  //
  //  Represents expression 'arg?'.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class Query extends Expr
  {
    //-----------------------------------------------------------------
    //  Data
    //-----------------------------------------------------------------
    public Expr arg;

    //-----------------------------------------------------------------
    //  Create object with specified 'arg'.
    //-----------------------------------------------------------------
    public Query(Expr arg)
      {
        this.arg = arg;
        isSub = true;
        bind  = 3;
      }

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Expr.PlusPlus
  //
  //  Represents expression 'arg1++arg2'.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class PlusPlus extends Expr
  {
    //-----------------------------------------------------------------
    //  Data
    //-----------------------------------------------------------------
    public Expr arg1;
    public Expr arg2;

    //-----------------------------------------------------------------
    //  Create object with specified 'arg1' and 'arg2'.
    //-----------------------------------------------------------------
    public PlusPlus(Expr arg1, Expr arg2)
      {
        this.arg1 = arg1;
        this.arg2 = arg2;
        isSub = true;
        bind  = 3;
      }

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Expr.StarPlus
  //
  //  Represents expression 'arg1*+arg2'.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class StarPlus extends Expr
  {
    //-----------------------------------------------------------------
    //  Data
    //-----------------------------------------------------------------
    public Expr arg1;
    public Expr arg2;

    //-----------------------------------------------------------------
    //  Create object with specified 'arg1' and 'arg2'.
    //-----------------------------------------------------------------
    public StarPlus(Expr arg1, Expr arg2)
      {
        this.arg1 = arg1;
        this.arg2 = arg2;
        isSub = true;
        bind  = 3;
      }

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Expr.Is
  //
  //  Represents expression 'arg1:arg2'.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class Is extends Expr
  {
    //-----------------------------------------------------------------
    //  Data
    //-----------------------------------------------------------------
    public Expr arg1;
    public Expr arg2;

    //-----------------------------------------------------------------
    //  Create object with specified 'arg1' and 'arg2'.
    //-----------------------------------------------------------------
    public Is(Expr arg1, Expr arg2)
      {
        this.arg1 = arg1;
        this.arg2 = arg2;
        isSub = true;
        bind  = 3;
      }

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Expr.IsNot
  //
  //  Represents expression 'arg1:!arg2'.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class IsNot extends Expr
  {
    //-----------------------------------------------------------------
    //  Data
    //-----------------------------------------------------------------
    public Expr arg1;
    public Expr arg2;

    //-----------------------------------------------------------------
    //  Create object with specified 'arg1' and 'arg2'.
    //-----------------------------------------------------------------
    public IsNot(Expr arg1, Expr arg2)
      {
        this.arg1 = arg1;
        this.arg2 = arg2;
        isSub = true;
        bind  = 3;
      }

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Expr.Ref
  //
  //  Represents reference to the Rule identified by 'name'.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class Ref extends Expr
  {
    //public Rule rule;

    //-----------------------------------------------------------------
    //  Create the object with specified name.
    //-----------------------------------------------------------------
    public Ref(String name)
      {
        this.name = name;
        asString = name;
        isRef = true;
        isNamed = true;
      }

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Expr.StringLit
  //
  //  Represents string literal.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class StringLit extends Expr
  {
    //-----------------------------------------------------------------
    //  Data
    //-----------------------------------------------------------------
    public String s; // The string in true form.

    //-----------------------------------------------------------------
    //  Create the object with specified string.
    //-----------------------------------------------------------------
    public StringLit(String s)
      {
        this.s = s;
        def = true;
        fal = true;
        adv = true;
        isTerm = true;
        asString = "\"" + s + "\"";
      }

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Expr.Range
  //
  //  Represents range [a-z].
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class Range extends Expr
  {
    //-----------------------------------------------------------------
    //  Data
    //-----------------------------------------------------------------
    public char a;      // Range limits in true form.
    public char z;

    //-----------------------------------------------------------------
    //  Create the object with limits a-z.
    //-----------------------------------------------------------------
    public Range(char a, char z)
      {
        this.a = a;
        this.z = z;
        def = true;
        fal = true;
        adv = true;
        isTerm = true;
        asString = "[" + a + "-" + z + "]";
      }

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Expr.CharClass
  //
  //  Represents character class [s] or ^[s].
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class CharClass extends Expr
  {
    //-----------------------------------------------------------------
    //  Data
    //-----------------------------------------------------------------
    public String s; // The string in true form.
    public boolean hat;    // '^' present?

    //-----------------------------------------------------------------
    //  Create object with specified string and 'not'.
    //-----------------------------------------------------------------
    public CharClass(String s, boolean hat)
      {
        this.s = s;
        this.hat = hat;
        def = true;
        fal = true;
        adv = true;
        isTerm = true;
        asString = (hat?"^[":"[") + s + "]";
      }

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Expr.Any
  //
  //  Represents 'any character'.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class Any extends Expr
  {
    //-----------------------------------------------------------------
    //  Create.
    //-----------------------------------------------------------------
    public Any()
      {
        def = true;
        fal = true;
        adv = true;
        isTerm = true;
        asString = "_";
      }

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Class Expr.End
  //
  //  Represents end of input.
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  public static class End extends Expr
  {
    //-----------------------------------------------------------------
    //  Create.
    //-----------------------------------------------------------------
    public End()
      {
        def = true;
        fal = true;
        adv = true;
        end = true;
        isTerm = true;
        asString = "!_";
      }

    //-----------------------------------------------------------------
    //  Accept visitor.
    //-----------------------------------------------------------------
    public void accept(Visitor v)
      { v.visit(this); }
  }
}


