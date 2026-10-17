//=========================================================================
//
//  Part of PEG parser generator Mouse.
//
//  Copyright (C) 2009, 2010, 2020, 2021
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
//    Version 1.2
//      Removed printing of iteration count.
//      Specified invocation in comment to the class.
//    Version 1.3
//      Use new version of PEG class.
//    Version 1.6.1
//      Class TestPEG made public.
//    Version 2.0
//      Added option -L.
//      Changed meaning of -C (no display). Always show counts.
//    Version 2.2
//      Added options 'd' and 'r'.
//    Version 2.3
//      Use 'PEG.showExprs' and 'Dual.showExprs' instead of 'PEG.show'.
//
//=========================================================================

package mouse;

import mouse.runtime.SourceFile;
import mouse.utility.CommandArgs;
import mouse.peg.PEG;
import mouse.explorer.Dual;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  TestPEG
//
//-------------------------------------------------------------------------
//
//  Check the grammar without generating parser.
//
//  Invocation
//
//    java mouse.TestPEG <arguments>
//
//  The <arguments> are specified as options according to POSIX syntax:
//
//    -G <filename>
//       Identifies the file containing the grammar. Mandatory.
//       The <filename> need not be a complete path, just enough to identify
//       the file in current environment. Should include file extension,if any.
//
//    -D Display the grammar. Optional.
//
//    -R Display only the rules. Optional.
//
//    -d Display the dual grammar. Optional.
//
//    -r Display only the rules of dual grammar. Optional.
//
//    -C Compact the grammar before displaying. Optional.
//
//    -L Display left-recursion classes. Optional.
//
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

public class TestPEG
{
  //=====================================================================
  //
  //  Invocation
  //
  //=====================================================================
  public static void main(String argv[])
    {
      //---------------------------------------------------------------
      //  Parse arguments.
      //---------------------------------------------------------------
      CommandArgs cmd = new CommandArgs
             (argv,      // arguments to parse
              "CDdLRr",  // options without argument
              "G",       // options with argument
               0,0);     // no positional arguments
      if (cmd.nErrors()>0) return;

      String gramName = cmd.optArg('G');
      if (gramName==null)
      {
        System.err.println("Specify -G grammar file.");
        return;
      }

      SourceFile src = new SourceFile(gramName);
      if (!src.created()) return;

      //---------------------------------------------------------------
      //  Create PEG object from source file.
      //---------------------------------------------------------------
      boolean parsed = PEG.parse(src);
      if (!parsed) return;

      //---------------------------------------------------------------
      //  Compact if requested.
      //---------------------------------------------------------------
      if (cmd.opt('C')) PEG.compact();

      //---------------------------------------------------------------
      //  Display as requested.
      //---------------------------------------------------------------
      System.out.println("");
      PEG.showCounts();

      if (cmd.opt('R') || cmd.opt('D'))
        PEG.showExprs(cmd.opt('D'));

      if (cmd.opt('L'))
        PEG.showRecClasses();

      //---------------------------------------------------------------
      //  If requested, create dual grammar and display.
      //---------------------------------------------------------------
      if (cmd.opt('d') || cmd.opt('r'))
      {
        Dual.create();
        System.out.println("\nDual Grammar\n");
        Dual.showCounts();
        Dual.showExprs(cmd.opt('d'));
      }
    }
}

