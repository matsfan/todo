**FREE
//***************************************************************************
// TODOMAIN - Todo Application Main Program  (thin UI shell)
//
// 5250 green-screen todo manager for IBM i
//
// Screens  : TODODSPPF (QDDSSRC)
// Data     : delegated entirely to TODOBL service program
//
// Compile command (compile all DDS objects and TODOBL first):
//   CRTBNDRPG PGM(TODO/TODOMAIN) SRCFILE(TODO/QRPGLESRC) SRCMBR(TODOMAIN)
//             BNDDIR(TODO/TODOBND)
//
// Screen Flow:
//   TODOCTL (list) --F6---> TODODET (add)  --> TODOCTL
//                --Opt 2--> TODODET (edit) --> TODOCTL
//                --Opt 4--> TODODEL (del)  --> TODOCTL
//                --Opt 5--> mark done         --> TODOCTL
//                --F3 ----> *end
//
// Indicator Map:
//   *IN03  F3=Exit
//   *IN06  F6=Add new
//   *IN12  F12=Cancel
//   *IN50  SFLDSP   (show subfile rows)
//   *IN51  SFLDSPCTL(show subfile control)
//   *IN52  SFLCLR   (clear subfile)
//   *IN53  SFLEND   (bottom of list)
//   *IN60  Error message on TODODET
//***************************************************************************

// ---------------------------------------------------------------------------
// File Declarations
// ---------------------------------------------------------------------------

// Display file - SFILE ties subfile record format to RRN counter
DCL-F TODODSPPF WORKSTN SFILE(TODOSFL:w_Rrn)
                        INFDS(w_Dspf_Infds)
                        USROPN;

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

DCL-DS w_Dspf_Infds;                         // Display file feedback area
  w_Aid_Key   CHAR(1) POS(369);               // AID key byte (used if needed)
END-DS;

DCL-S w_Rrn      PACKED(4:0) INZ(0);         // Current subfile RRN
DCL-S w_MaxRrn   PACKED(4:0) INZ(0);         // Highest RRN written this load
DCL-S w_NextId   PACKED(5:0) INZ(0);         // Next available todo ID
DCL-S w_Mode     CHAR(3)     INZ('');         // 'ADD' or 'EDT'
DCL-S w_Option   CHAR(1)     INZ('');         // User option from subfile row
DCL-S w_SelId    PACKED(5:0) INZ(0);         // ID of selected todo
DCL-S w_Today    DATE        INZ(*SYS);       // Today's date for new todos

// ---------------------------------------------------------------------------
// Prototypes for TODOBL exported procedures
// ---------------------------------------------------------------------------

DCL-DS todoRec_t        QUALIFIED TEMPLATE;
  tdId    PACKED(5:0);
  tdDesc  CHAR(50);
  tdDone  CHAR(1);
  tdDue   DATE(*ISO);
END-DS;

DCL-PR OpenFiles           EXTPROC('OPENFILES');
END-PR;

DCL-PR CloseFiles          EXTPROC('CLOSEFILES');
END-PR;

DCL-PR GetNextId           PACKED(5:0)
                           EXTPROC('GETNEXTID');
END-PR;

DCL-PR ValidateDescription IND
                           EXTPROC('VALIDATEDESCRIPTION');
  i_Desc    CHAR(50) CONST;
END-PR;

DCL-PR AddTodoRecord       EXTPROC('ADDTODORECORD');
  i_Id      PACKED(5:0) CONST;
  i_Desc    CHAR(50)    CONST;
  i_Due     DATE(*ISO)  CONST;
END-PR;

DCL-PR EditTodoRecord      EXTPROC('EDITTODORECORD');
  i_Id      PACKED(5:0) CONST;
  i_Desc    CHAR(50)    CONST;
  i_Due     DATE(*ISO)  CONST;
END-PR;

DCL-PR MarkDoneRecord      EXTPROC('MARKDONERECORD');
  i_Id      PACKED(5:0) CONST;
END-PR;

DCL-PR DeleteTodoRecord    EXTPROC('DELETETODORECORD');
  i_Id      PACKED(5:0) CONST;
END-PR;

DCL-PR ReadFirstTodo       IND
                           EXTPROC('READFIRSTTODO');
  o_Rec     LIKEDS(todoRec_t);
END-PR;

DCL-PR ReadNextTodo        IND
                           EXTPROC('READNEXTTODO');
  o_Rec     LIKEDS(todoRec_t);
END-PR;

DCL-PR GetTodoById         IND
                           EXTPROC('GETTODOBYID');
  i_Id      PACKED(5:0) CONST;
  o_Rec     LIKEDS(todoRec_t);
END-PR;

// ---------------------------------------------------------------------------
// Main Procedure
// ---------------------------------------------------------------------------

DCL-PROC Main;

  OPEN TODODSPPF;
  OpenFiles();

  DOU *IN03;                                  // Loop until F3=Exit

    ExSr LoadSubfile;                         // Rebuild the subfile

    // Show list screen and wait for user input
    EXFMT TODOCTL;

    // ---- F3 Exit -----------------------------------------------------------
    IF *IN03;
      LEAVE;
    END-IF;

    // ---- F6 Add new todo ---------------------------------------------------
    IF *IN06;
      ExSr AddTodo;
      ITER;
    END-IF;

    // ---- Process subfile option column -------------------------------------
    w_Rrn = 1;
    DOU w_Rrn > w_MaxRrn;
      READC TODOSFL;                          // Read changed subfile records
      IF %EOF(TODODSPPF);
        LEAVE;
      END-IF;

      w_Option = SFLOPT;
      w_SelId  = TDID;

      SELECT;
        WHEN w_Option = '2';                  // Edit
          ExSr EditTodo;
        WHEN w_Option = '4';                  // Delete
          ExSr DeleteTodo;
        WHEN w_Option = '5';                  // Mark done
          ExSr MarkDone;
        OTHER;
          // Unknown option - ignore
      END-SL;

      SFLOPT = ' ';                           // Clear the option field
      w_Rrn += 1;
    END-DO;

  END-DO;

  // Clean up
  CloseFiles();
  CLOSE TODODSPPF;
  *INLR = *ON;
  RETURN;

END-PROC;

// ---------------------------------------------------------------------------
// LoadSubfile - Clear and reload the subfile with incomplete todos
// ---------------------------------------------------------------------------

DCL-PROC LoadSubfile;

  DCL-DS l_Rec LIKEDS(todoRec_t);

  // Step 1: Clear the subfile
  *IN50 = *OFF;                               // SFLDSP   off = hide rows
  *IN51 = *OFF;                               // SFLDSPCTL off
  *IN52 = *ON;                                // SFLCLR   on = clear
  WRITE TODOCTL;
  *IN52 = *OFF;                               // Turn off SFLCLR immediately

  w_Rrn    = 0;
  w_MaxRrn = 0;

  // Step 2: Read all non-done records via TODOBL
  IF ReadFirstTodo(l_Rec);
    DOW *ON;
      w_Rrn  += 1;
      SFLOPT  = ' ';
      TDID    = l_Rec.tdId;
      TDDESC  = l_Rec.tdDesc;
      TDDONE  = l_Rec.tdDone;
      TDDUE   = l_Rec.tdDue;
      WRITE TODOSFL;

      IF NOT ReadNextTodo(l_Rec);
        LEAVE;
      END-IF;
    END-DO;
  END-IF;

  w_MaxRrn = w_Rrn;

  // Step 3: Display the subfile (only if rows were written)
  IF w_MaxRrn > 0;
    *IN50 = *ON;                              // SFLDSP on
  END-IF;
  *IN51 = *ON;                                // SFLDSPCTL on
  *IN53 = *ON;                                // SFLEND - show "More..." / "Bottom"

END-PROC;

// ---------------------------------------------------------------------------
// AddTodo - Show blank detail screen and write a new record
// ---------------------------------------------------------------------------

DCL-PROC AddTodo;

  DETMODE  = 'Add     ';
  DETID    = 0;
  DETDESC  = *BLANKS;
  DETDUE   = w_Today;
  *IN60    = *OFF;

  DOU NOT *IN03 AND NOT *IN12;                // Loop until Enter or Cancel

    EXFMT TODODET;

    IF *IN03 OR *IN12;
      LEAVE;
    END-IF;

    // Validate description
    IF NOT ValidateDescription(DETDESC);
      *IN60 = *ON;                            // Show error message
      ITER;
    END-IF;

    // Write new record
    w_NextId = GetNextId();
    AddTodoRecord(w_NextId: DETDESC: DETDUE);

    LEAVE;

  END-DO;

END-PROC;

// ---------------------------------------------------------------------------
// EditTodo - Load an existing record into the detail screen and update it
// ---------------------------------------------------------------------------

DCL-PROC EditTodo;

  DCL-DS l_Rec LIKEDS(todoRec_t);

  IF NOT GetTodoById(w_SelId: l_Rec);
    RETURN;
  END-IF;

  DETMODE  = 'Edit    ';
  DETID    = l_Rec.tdId;
  DETDESC  = l_Rec.tdDesc;
  DETDUE   = l_Rec.tdDue;
  *IN60    = *OFF;

  DOU NOT *IN03 AND NOT *IN12;

    EXFMT TODODET;

    IF *IN03 OR *IN12;
      LEAVE;
    END-IF;

    // Validate description
    IF NOT ValidateDescription(DETDESC);
      *IN60 = *ON;
      ITER;
    END-IF;

    // Apply changes
    EditTodoRecord(w_SelId: DETDESC: DETDUE);

    LEAVE;

  END-DO;

END-PROC;

// ---------------------------------------------------------------------------
// MarkDone - Set TDDONE='1' on the selected record
// ---------------------------------------------------------------------------

DCL-PROC MarkDone;

  MarkDoneRecord(w_SelId);

END-PROC;

// ---------------------------------------------------------------------------
// DeleteTodo - Show confirmation screen then delete on Enter
// ---------------------------------------------------------------------------

DCL-PROC DeleteTodo;

  DCL-DS l_Rec LIKEDS(todoRec_t);

  IF NOT GetTodoById(w_SelId: l_Rec);
    RETURN;
  END-IF;

  DELID   = l_Rec.tdId;
  DELDESC = l_Rec.tdDesc;
  DELDUE  = l_Rec.tdDue;

  EXFMT TODODEL;

  IF NOT *IN12;                               // Enter = confirmed, not F12
    DeleteTodoRecord(w_SelId);
  END-IF;

END-PROC;

// ---------------------------------------------------------------------------
// Program entry point
// ---------------------------------------------------------------------------
Main();
