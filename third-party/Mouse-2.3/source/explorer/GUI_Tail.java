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
//      Created.
//    Version 1.9.1
//      Make the window slightly smaller than Conflicts window.
//    Version 1.9.2
//      Show in the title bar the expression that contains the conflict.
//    Version 2.2
//      Use 'toNamed' from PEG.Expr.
//    Version 2.3
//      Redesigned, showing Tail in a different way.
//      Moved 'initialize' from constructor to 'display'.
//      Construct Paragraph_Explorer from Line_Items.
//      Removed serial version UID.
//
//=========================================================================

package mouse.explorer;

import mouse.peg.Expr;

//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
//
//  class GUI_Tail
//
//-------------------------------------------------------------------------
//
//  The main Explorer window.
//
//  It has one pragaph, showing the expanded tail.
//
//  This window is a singleton. The static method 'display' either creates
//  a new window or displays the existing one.
//
//HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

public class GUI_Tail extends GUI
{
  //=====================================================================
  //
  //  Data
  //
  //=====================================================================
  //-------------------------------------------------------------------
  // Existing instance of this window.
  //-------------------------------------------------------------------
  private static GUI_Tail instance = null;

  //-------------------------------------------------------------------
  // Expression whose Tail is being explored.
  //-------------------------------------------------------------------
  Expr theExpr;

  //-------------------------------------------------------------------
  //  Copy of paragraph, kept to preserve its type.
  //  (Elements of 'paragraphs' in GUI are of class Paragraph.)
  //-------------------------------------------------------------------
  Paragraph_Explorer para = null;

  //=====================================================================
  //
  //  Constructor
  //
  //=====================================================================
  private GUI_Tail()
    {
      super(1,70,50);
      addKey("Expand");
    }

  //-------------------------------------------------------------------
  //  Display instance for expression 'e'.
  //-------------------------------------------------------------------
  static void display(Expr e)
    {
      if (instance==null)
        instance = new GUI_Tail();
      instance.initialize(e);
      GUI.display(instance);
    }

  //-------------------------------------------------------------------
  //  Initialize for expression 'expr'.
  //-------------------------------------------------------------------
  private void initialize(Expr expr)
    {
      theExpr = expr;
      para = new Paragraph_Explorer(new Line_Items().addTail(expr));
      para.expand(0,0);
      paragraphs[0] = para;
      write();
      setTitle("Tail(" + theExpr.name + ")");
    }

  //=====================================================================
  //
  //  Actions
  //
  //=====================================================================
  //-------------------------------------------------------------------
  //  Mouse action.
  //-------------------------------------------------------------------
  void mouseAction(boolean clicked)
    {
      if (clicked) keyPressed("Expand");
    }

  //-------------------------------------------------------------------
  //  Key 'command' pressed.
  //-------------------------------------------------------------------
  void keyPressed(String command)
    {
      switch(command)
      {
        //-------------------------------------------------------------
        //  Expand
        //-------------------------------------------------------------
        case "Expand":
        {
          if (selected==null) return;
          para.expand(selected.item,selected.line);
          write();
          return;
        }
        default: ;
      }
    }

  //-------------------------------------------------------------------
  //  Window closed.
  //-------------------------------------------------------------------
  void windowClosed()
    { instance = null; }
}