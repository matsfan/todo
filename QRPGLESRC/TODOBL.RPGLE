**FREE
//***************************************************************************
// TODOBL - Todo Business Logic Service Program
//
// Owns all file I/O and business logic for the Todo application.
// Compiled as a *SRVPGM; bound to by TODOMAIN and TODOTEST.
//
// Data     : TODOPF    physical file  (QDDSSRC) - opened for UPDATE/OUTPUT/DELETE
//            TODOLF    logical file   (QDDSSRC) - opened read-only
//
// Compile commands (compile DDS objects first, then):
//   CRTPGM  MODULE(TODO/TODOBL)  SRCFILE(TODO/QRPGLESRC)  SRCMBR(TODOBL)
//   CRTSRVPGM SRVPGM(TODO/TODOBL) MODULE(TODO/TODOBL)
//     (or one step: CRTSRVPGM SRVPGM(TODO/TODOBL) SRCFILE(TODO/QRPGLESRC)
//                              SRCMBR(TODOBL) MODULE(*SRVPGM))
//
// Exported procedures:
//   OpenFiles            - open TODOLF and TODOPF
//   CloseFiles           - close TODOLF and TODOPF
//   GetNextId            - return next available todo ID (5P 0)
//   ValidateDescription  - *ON if desc is non-blank, *OFF if blank/spaces
//   AddTodoRecord        - write a new record to TODOPF
//   EditTodoRecord       - update TDDESC / TDDUE on an existing TODOPF record
//   MarkDoneRecord       - set TDDONE='1' on a TODOPF record
//   DeleteTodoRecord     - delete a TODOPF record by ID
//   ReadFirstTodo        - SETLL *START on TODOLF, return first non-done record
//   ReadNextTodo         - return next non-done record from TODOLF
//***************************************************************************

// ---------------------------------------------------------------------------
// File Declarations
// ---------------------------------------------------------------------------

// Logical file - used for sequential reads and GetNextId positioning
DCL-F TODOLF    DISK    KEYED USROPN;

// Physical file - used for WRITE / UPDATE / DELETE
DCL-F TODOPF    DISK    KEYED USAGE(*UPDATE:*OUTPUT:*DELETE) USROPN;

// ---------------------------------------------------------------------------
// Data Structure: todoRec_t
//   Passed by reference to ReadFirstTodo / ReadNextTodo so the caller can
//   populate the subfile without touching TODOLF directly.
// ---------------------------------------------------------------------------

DCL-DS todoRec_t        QUALIFIED TEMPLATE;
  tdId    PACKED(5:0);
  tdDesc  CHAR(50);
  tdDone  CHAR(1);
  tdDue   DATE(*ISO);
END-DS;

// ---------------------------------------------------------------------------
// Prototypes
// ---------------------------------------------------------------------------

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
// Working storage
// ---------------------------------------------------------------------------

DCL-S w_Found    IND         INZ(*OFF);

// ---------------------------------------------------------------------------
// OpenFiles - Open TODOLF and TODOPF
// ---------------------------------------------------------------------------

DCL-PROC OpenFiles          EXPORT;

  DCL-PI *N END-PI;

  OPEN TODOLF;
  OPEN TODOPF;

END-PROC;

// ---------------------------------------------------------------------------
// CloseFiles - Close TODOLF and TODOPF
// ---------------------------------------------------------------------------

DCL-PROC CloseFiles         EXPORT;

  DCL-PI *N END-PI;

  CLOSE TODOLF;
  CLOSE TODOPF;

END-PROC;

// ---------------------------------------------------------------------------
// GetNextId - Return the next available todo ID
//   Uses SETLL *END + READPE on TODOLF to find the highest existing ID.
//   Returns 1 when the file is empty.
// ---------------------------------------------------------------------------

DCL-PROC GetNextId          EXPORT;

  DCL-PI *N PACKED(5:0) END-PI;

  DCL-S l_Id PACKED(5:0) INZ(0);

  SETLL *END TODOLF;
  READPE TODOR TODOLF;                          // Read last record
  IF NOT %EOF(TODOLF);
    l_Id = TDID + 1;
  ELSE;
    l_Id = 1;                                   // First ever record
  END-IF;

  RETURN l_Id;

END-PROC;

// ---------------------------------------------------------------------------
// ValidateDescription - Return *ON if description is non-blank
// ---------------------------------------------------------------------------

DCL-PROC ValidateDescription EXPORT;

  DCL-PI *N IND;
    i_Desc    CHAR(50) CONST;
  END-PI;

  RETURN (%TRIMR(i_Desc) <> *BLANKS);

END-PROC;

// ---------------------------------------------------------------------------
// AddTodoRecord - Write a new record to TODOPF
// ---------------------------------------------------------------------------

DCL-PROC AddTodoRecord      EXPORT;

  DCL-PI *N;
    i_Id      PACKED(5:0) CONST;
    i_Desc    CHAR(50)    CONST;
    i_Due     DATE(*ISO)  CONST;
  END-PI;

  TDID   = i_Id;
  TDDESC = i_Desc;
  TDDONE = '0';
  TDDUE  = i_Due;
  WRITE TODOR TODOPF;

END-PROC;

// ---------------------------------------------------------------------------
// EditTodoRecord - Update TDDESC and TDDUE on an existing record
// ---------------------------------------------------------------------------

DCL-PROC EditTodoRecord     EXPORT;

  DCL-PI *N;
    i_Id      PACKED(5:0) CONST;
    i_Desc    CHAR(50)    CONST;
    i_Due     DATE(*ISO)  CONST;
  END-PI;

  CHAIN i_Id TODOPF TODOR;
  w_Found = NOT %EOF(TODOPF);

  IF w_Found;
    TDDESC = i_Desc;
    TDDUE  = i_Due;
    UPDATE TODOR TODOPF;
  END-IF;

END-PROC;

// ---------------------------------------------------------------------------
// MarkDoneRecord - Set TDDONE='1' on the record with the given ID
// ---------------------------------------------------------------------------

DCL-PROC MarkDoneRecord     EXPORT;

  DCL-PI *N;
    i_Id      PACKED(5:0) CONST;
  END-PI;

  CHAIN i_Id TODOPF TODOR;
  IF NOT %EOF(TODOPF);
    TDDONE = '1';
    UPDATE TODOR TODOPF;
  END-IF;

END-PROC;

// ---------------------------------------------------------------------------
// DeleteTodoRecord - Delete the record with the given ID from TODOPF
//   The caller (TODOMAIN) presents the confirmation screen before calling
//   this procedure, so a single CHAIN + DELETE is correct here.
// ---------------------------------------------------------------------------

DCL-PROC DeleteTodoRecord   EXPORT;

  DCL-PI *N;
    i_Id      PACKED(5:0) CONST;
  END-PI;

  CHAIN i_Id TODOPF TODOR;
  IF NOT %EOF(TODOPF);
    DELETE TODOR TODOPF;
  END-IF;

END-PROC;

// ---------------------------------------------------------------------------
// ReadFirstTodo - Position TODOLF to *START and return the first non-done record
//   Returns *ON if a non-done record was found; *OFF if the file is empty
//   or all records are done.
// ---------------------------------------------------------------------------

DCL-PROC ReadFirstTodo      EXPORT;

  DCL-PI *N IND;
    o_Rec     LIKEDS(todoRec_t);
  END-PI;

  SETLL *START TODOLF;
  RETURN ReadNextTodo(o_Rec);

END-PROC;

// ---------------------------------------------------------------------------
// ReadNextTodo - Read the next non-done record from TODOLF
//   Returns *ON if found, *OFF at end-of-file.
// ---------------------------------------------------------------------------

DCL-PROC ReadNextTodo       EXPORT;

  DCL-PI *N IND;
    o_Rec     LIKEDS(todoRec_t);
  END-PI;

  DOU %EOF(TODOLF);
    READ TODOLF TODOR;
    IF %EOF(TODOLF);
      RETURN *OFF;
    END-IF;

    IF TDDONE <> '1';
      o_Rec.tdId   = TDID;
      o_Rec.tdDesc = TDDESC;
      o_Rec.tdDone = TDDONE;
      o_Rec.tdDue  = TDDUE;
      RETURN *ON;
    END-IF;

  END-DO;

  RETURN *OFF;

END-PROC;

// ---------------------------------------------------------------------------
// GetTodoById - Chain to TODOPF by ID and return the record in o_Rec
//   Returns *ON if the record was found, *OFF if not.
// ---------------------------------------------------------------------------

DCL-PROC GetTodoById        EXPORT;

  DCL-PI *N IND;
    i_Id      PACKED(5:0) CONST;
    o_Rec     LIKEDS(todoRec_t);
  END-PI;

  CHAIN i_Id TODOPF TODOR;
  w_Found = NOT %EOF(TODOPF);

  IF w_Found;
    o_Rec.tdId   = TDID;
    o_Rec.tdDesc = TDDESC;
    o_Rec.tdDone = TDDONE;
    o_Rec.tdDue  = TDDUE;
  END-IF;

  RETURN w_Found;

END-PROC;
