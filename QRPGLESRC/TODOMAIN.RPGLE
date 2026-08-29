**FREE
//***************************************************************************
// TODOMAIN - Todo Application Main Program
//
// 5250 green-screen todo manager for IBM i
//
// Screens  : TODODSPPF (QDDSSRC)
// Data     : TODOPF    physical file  (QDDSSRC)
//            TODOLF    logical file   (QDDSSRC) - keyed by TDID ascending
//
// Compile command (compile all DDS files first):
//   CRTBNDRPG PGM(TODO/TODOMAIN) SRCFILE(TODO/QRPGLESRC) SRCMBR(TODOMAIN)
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

// Logical file - used for sequential reads (subfile load) and keyed access
DCL-F TODOLF    DISK    KEYED USROPN;

// Physical file - used for WRITE / UPDATE / DELETE
DCL-F TODOPF    DISK    KEYED USAGE(*UPDATE:*OUTPUT:*DELETE) USROPN;

// Display file - SFILE ties subfile record format to RRN counter
DCL-F TODODSPPF WORKSTN SFILE(TODOSFL:w_Rrn)
                        INFDS(w_Dspf_Infds);

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
DCL-S w_Found    IND         INZ(*OFF);       // Chain / READE found indicator
DCL-S w_Today    DATE        INZ(*SYS);       // Today's date for new todos

// ---------------------------------------------------------------------------
// Main Procedure
// ---------------------------------------------------------------------------

DCL-PROC Main;

  OPEN TODOLF;
  OPEN TODOPF;

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
  CLOSE TODOLF;
  CLOSE TODOPF;
  *INLR = *ON;
  RETURN;

END-PROC;

// ---------------------------------------------------------------------------
// LoadSubfile - Clear and reload the subfile with incomplete todos
// ---------------------------------------------------------------------------

DCL-PROC LoadSubfile;

  // Step 1: Clear the subfile
  *IN50 = *OFF;                               // SFLDSP   off = hide rows
  *IN51 = *OFF;                               // SFLDSPCTL off
  *IN52 = *ON;                                // SFLCLR   on = clear
  WRITE TODOCTL;
  *IN52 = *OFF;                               // Turn off SFLCLR immediately

  w_Rrn    = 0;
  w_MaxRrn = 0;

  // Step 2: Read all records from the logical file, skip completed todos
  SETLL *START TODOLF;

  DOU %EOF(TODOLF);
    READ TODOLF TODOR;
    IF %EOF(TODOLF);
      LEAVE;
    END-IF;

    // Skip todos that are already done
    IF TDDONE = '1';
      ITER;
    END-IF;

    // Write one subfile row
    w_Rrn  += 1;
    SFLOPT  = ' ';
    // Fields TDID, TDDESC, TDDONE, TDDUE are already populated by the READ
    WRITE TODOSFL;

  END-DO;

  w_MaxRrn = w_Rrn;

  // Step 3: Display the subfile (only if rows were written)
  IF w_MaxRrn > 0;
    *IN50 = *ON;                              // SFLDSP on
  END-IF;
  *IN51 = *ON;                                // SFLDSPCTL on
  *IN53 = *ON;                                // SFLEND - show "More..." / "Bottom"

END-PROC;

// ---------------------------------------------------------------------------
// GetNextId - Return the next available todo ID
// ---------------------------------------------------------------------------

DCL-PROC GetNextId;

  DCL-PI *N PACKED(5:0) END-PI;

  DCL-S l_Id PACKED(5:0) INZ(0);

  SETLL *END TODOLF;
  READPE TODOR TODOLF;                        // Read last record
  IF NOT %EOF(TODOLF);
    l_Id = TDID + 1;
  ELSE;
    l_Id = 1;                                 // First ever record
  END-IF;

  RETURN l_Id;

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
    IF %TRIMR(DETDESC) = *BLANKS;
      *IN60 = *ON;                            // Show error message
      ITER;
    END-IF;

    // Write new record
    w_NextId = GetNextId();
    TDID     = w_NextId;
    TDDESC   = DETDESC;
    TDDONE   = '0';
    TDDUE    = DETDUE;
    WRITE TODOR TODOPF;

    LEAVE;

  END-DO;

END-PROC;

// ---------------------------------------------------------------------------
// EditTodo - Load an existing record into the detail screen and update it
// ---------------------------------------------------------------------------

DCL-PROC EditTodo;

  CHAIN w_SelId TODOPF TODOR;
  w_Found = NOT %EOF(TODOPF);

  IF NOT w_Found;
    RETURN;
  END-IF;

  DETMODE  = 'Edit    ';
  DETID    = TDID;
  DETDESC  = TDDESC;
  DETDUE   = TDDUE;
  *IN60    = *OFF;

  DOU NOT *IN03 AND NOT *IN12;

    EXFMT TODODET;

    IF *IN03 OR *IN12;
      LEAVE;
    END-IF;

    // Validate description
    IF %TRIMR(DETDESC) = *BLANKS;
      *IN60 = *ON;
      ITER;
    END-IF;

    // Apply changes back to the record buffer and update
    TDDESC = DETDESC;
    TDDUE  = DETDUE;
    UPDATE TODOR TODOPF;

    LEAVE;

  END-DO;

END-PROC;

// ---------------------------------------------------------------------------
// MarkDone - Set TDDONE='1' on the selected record
// ---------------------------------------------------------------------------

DCL-PROC MarkDone;

  CHAIN w_SelId TODOPF TODOR;
  IF NOT %EOF(TODOPF);
    TDDONE = '1';
    UPDATE TODOR TODOPF;
  END-IF;

END-PROC;

// ---------------------------------------------------------------------------
// DeleteTodo - Show confirmation screen then delete on Enter
// ---------------------------------------------------------------------------

DCL-PROC DeleteTodo;

  CHAIN w_SelId TODOPF TODOR;
  w_Found = NOT %EOF(TODOPF);

  IF NOT w_Found;
    RETURN;
  END-IF;

  DELID   = TDID;
  DELDESC = TDDESC;
  DELDUE  = TDDUE;

  EXFMT TODODEL;

  IF NOT *IN12;                               // Enter = confirmed, not F12
    CHAIN w_SelId TODOPF TODOR;               // Re-position for DELETE
    IF NOT %EOF(TODOPF);
      DELETE TODOR TODOPF;
    END-IF;
  END-IF;

END-PROC;

// ---------------------------------------------------------------------------
// Program entry point
// ---------------------------------------------------------------------------
Main();
