//=========================================================================
//
//  Part of PEG parser generator Mouse.
//
//  Copyright (C) 2020 by Roman R. Redziejowski (www.romanredz.se).
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
//      Created.
//    Version 2.3
//      Renamed from 'Tail_Strand'.
//      Major redesign.
//
//=========================================================================

package mouse.explorer;

import mouse.peg.Expr;
import java.util.BitSet;
import java.util.Vector;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  Class TailStrand
//
//-------------------------------------------------------------------------
//
//  Represents strings that may follow expression 'e' called
//  from whithin expression 'E'. Written symbolically, it is
//
//          follow(e,E) Tail(E)
//
//  where 'follow(e,E)' is the sequence of expressions called by 'E'
//  after 'e', and 'Tail(E)' is the tail of 'E'. 'Tail(E)' is not
//  present if the last expression in 'follow(e,E)' has 'end' attribute.
//  In the object, 'follow(e,E)' is represented by Vector 'follow'
//  of Expressions, and 'Tail(E)' by 'tail'. It is Expression 'E'
//  if 'Tail(E)' is present, otherwise it is null.
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

public class TailStrand
{
  public Vector<Expr> follow;
  public Expr tail;

  BitSet firstTerms;    // First terminals
  boolean nullFollow;   // 'follow' is empty or nullable

  //=====================================================================
  //
  //  Constructors
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  With empty 'follow'.
  //-------------------------------------------------------------------
  public TailStrand(Expr E)
    {
      follow = new Vector<Expr>();
      tail = E;
      baseTerms();
    }

  //-------------------------------------------------------------------
  //  With one-expression 'follow'.
  //-------------------------------------------------------------------
  public TailStrand(Expr f, Expr E)
    {
      follow = new Vector<Expr>();
      follow.add(f);
      tail = E;
      baseTerms();
    }

  //-------------------------------------------------------------------
  //  With Vector 'follow'.
  //-------------------------------------------------------------------
  public TailStrand(Vector<Expr> f, Expr E)
    {
      follow = new Vector<Expr>();
      follow.addAll(f);
      tail = E;
      baseTerms();
    }

  //-------------------------------------------------------------------
  //  With two-Vector 'follow'.
  //-------------------------------------------------------------------
  public TailStrand(Vector<Expr> f1, Vector<Expr> f2, Expr E)
    {
      follow = new Vector<Expr>();
      follow.addAll(f1);
      follow.addAll(f2);
      tail = E;
      baseTerms();
    }

   //=====================================================================
  //
  //  Compute first terminals of 'follow'.
  //  If 'follow' is nullable or empty, additional first terminals
  //  will come from 'tail' in the iteration process.
  //
  //=====================================================================
  void baseTerms()
    {
       firstTerms = new BitSet();
       nullFollow = true;
       for (Expr e: follow)
       {
         firstTerms.or(e.firstTerms);
         if (!e.nul)
         {
           nullFollow = false;
           break;
	     }
       }
    }

  //=====================================================================
  //
  //  Compute first terminals including these of 'tail'.
  //  These latter may increase in the iteration process.
  //
  //=====================================================================
  void firstTerms()
    {
      if (nullFollow && tail!=null)
        firstTerms.or(tail.tail.firstTerms);
    }

  //=====================================================================
  //
  //  As String.
  //
  //=====================================================================
  public String asString()
    {
      StringBuffer sb = new StringBuffer("");
      for (Expr elem: follow)
      {
        if (elem.bind==0)
          sb.append("(" + elem.toShort() +  ") ");
        else
          sb.append(elem.toShort() + " ");
      }
      if (tail!=null)
        sb.append("Tail("+tail.name+")");
      return sb.toString();
    }
}


