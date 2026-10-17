//=========================================================================
//
//  Part of PEG parser generator Mouse.
//
//  Copyright (C) 2009, 2010, 2013, 2014, 2015, 2020
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
//    Version 1.1
//      Created.
//    Version 1.3
//      Added c.diag to arguments of begin in saved and savedInner.
//      In Cache(String) set diag to name instead of null.
//    Version 1.6
//      Allowed m=0 to enable performance comparisons.
//    Version 1.7
//      Changed initialization of 'cacheSize' to the default value 0.
//      The 'reuse' services rewritten to use new methods of 'Phrase'.
//    Version 2.0
//      Added comments.
//
//=========================================================================

package mouse.runtime;

import mouse.runtime.Source;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  ParserMemo
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

public class ParserMemo extends ParserBase
{
  //-------------------------------------------------------------------
  //  Cache size.
  //-------------------------------------------------------------------
  int cacheSize = 0;

  //-------------------------------------------------------------------
  //  Phrase to reuse.
  //-------------------------------------------------------------------
  Phrase reuse;

  //-------------------------------------------------------------------
  //  List of Cache objects for initialization.
  //-------------------------------------------------------------------
  protected Cache[] caches;

  //-------------------------------------------------------------------
  //  Constructor
  //-------------------------------------------------------------------
  protected ParserMemo()
    {}

  //-------------------------------------------------------------------
  //  Initialize
  //-------------------------------------------------------------------
  public void init(Source src)
    {
      super.init(src);
      for (Cache c: caches) // Reset Cache objects
        c.reset();
    }

  //-------------------------------------------------------------------
  //  Set cache size.
  //-------------------------------------------------------------------
  public void setMemo(int m)
    {
      if (m<0 | m>9) throw new Error("m=" + m + " is outside range 0-9");
      cacheSize = m;
    }

  //=====================================================================
  //
  //  Methods called from parsing procedures
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  If saved result found, use it, otherwise begin new procedure.
  //-------------------------------------------------------------------
  protected boolean saved(String name, String diag, Cache c)
    {
      reuse = c.find();
      if (reuse!=null)                 // If found Phrase to reuse..
        return true;                   // .. return

      begin(name,diag);                // Otherwise push new Phrase
      c.save(current);                 // .. and cache it
      return false;
    }

  protected boolean saved(String name, Cache c)
    { return saved(name,name,c); }

  //-------------------------------------------------------------------
  //  Reuse Rule
  //-------------------------------------------------------------------
  protected boolean reuse()
    {
      pos = reuse.end;                 // Update position
      current.end = pos;               // Update end of current
      current.hwmUpdFrom(reuse);       // Propagate error info
      if (!reuse.success)
         return false;
      current.rhs.add(reuse);          // Attach to rhs of current
        return true;
    }

  //-------------------------------------------------------------------
  //  Reuse Inner
  //-------------------------------------------------------------------
  protected boolean reuseInner()
    {
      pos = reuse.end;                 // Update position
      current.end = pos;               // Update end of current
      current.hwmUpdFrom(reuse);       // Propagate error info
      if (!reuse.success)
         return false;
      current.rhs.addAll(reuse.rhs);   // Add rhs to rhs of current
        return true;
    }

  //-------------------------------------------------------------------
  //  Reuse predicate
  //-------------------------------------------------------------------
  protected boolean reusePred()
    {
      pos = reuse.end;                 // Update position
      current.end = pos;               // Update end of current
      current.hwmUpdFrom(reuse);       // Propagate error info
      return (reuse.success);
    }


  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
  //
  //  Cache
  //
  //HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

  protected class Cache
  {
    Phrase[] cache = new Phrase[cacheSize];
    int last = 0;

    //-----------------------------------------------------------------
    //  Constructor
    //-----------------------------------------------------------------
    public Cache()
      {}

    //-----------------------------------------------------------------
    //  Save Phrase 'p'
    //-----------------------------------------------------------------
    void save(Phrase p)
      {
        if (cacheSize==0) return;
        last = (last+1)%cacheSize;
        cache[last] = p;
      }

    //-----------------------------------------------------------------
    //  Find Phrase
    //-----------------------------------------------------------------
    Phrase find()
      {
        if (cacheSize==0) return null;
        for (Phrase p: cache)
          if (p!=null && p.start==pos) return p;
        return null;
      }

    //-----------------------------------------------------------------
    //  Reset to empty
    //-----------------------------------------------------------------
    void reset()
      {
        cache = new Phrase[cacheSize];
        last = 0;
      }
  }
}



