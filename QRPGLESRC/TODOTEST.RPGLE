**FREE
//***************************************************************************
// TODOTEST - RPGUnit test suite for TODOBL service program
//
// Every procedure whose name starts with 'test' is automatically discovered
// and executed by the RPGUnit runner:
//   RUCALLTST TSTPGM(TODO/TODOTEST)
//
// setUp is called before each test; tearDown is called after each test.
//
// Test IDs used (chosen to avoid conflicts with real application data):
//   77    - testGetNextId_WithRecords
//   9999  - testGetNextId_NoHigherRecord
//   8001  - testAddTodoRecord
//   8002  - testMarkDoneRecord
//
// Compile commands:
//   CRTPGM    MODULE(TODO/TODOTEST)  SRCFILE(TODO/QRPGLESRC)  SRCMBR(TODOTEST)
//   CRTSRVPGM SRVPGM(TODO/TODOTEST) MODULE(TODO/TODOTEST)
//             BNDDIR(TODO/TODOBND) BNDSRVPGM(RPGUNIT/RUCRTTST)
//***************************************************************************

/COPY RPGUNIT/QINCLUDE,TESTCASE

// ---------------------------------------------------------------------------
// Data Structure: todoRec_t  (copied verbatim from TODOBL)
// ---------------------------------------------------------------------------

DCL-DS todoRec_t        QUALIFIED TEMPLATE;
  tdId    PACKED(5:0);
  tdDesc  CHAR(50);
  tdDone  CHAR(1);
  tdDue   DATE(*ISO);
END-DS;

// ---------------------------------------------------------------------------
// Prototypes for TODOBL exported procedures (copied verbatim from TODOBL)
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

DCL-PR MarkDoneRecord      EXTPROC('MARKDONERECORD');
  i_Id      PACKED(5:0) CONST;
END-PR;

DCL-PR DeleteTodoRecord    EXTPROC('DELETETODORECORD');
  i_Id      PACKED(5:0) CONST;
END-PR;

DCL-PR GetTodoById         IND
                           EXTPROC('GETTODOBYID');
  i_Id      PACKED(5:0) CONST;
  o_Rec     LIKEDS(todoRec_t);
END-PR;

// ---------------------------------------------------------------------------
// setUp - called automatically by RPGUnit before each test procedure
// ---------------------------------------------------------------------------

DCL-PROC setUp             EXPORT;
  DCL-PI *N END-PI;

  OpenFiles();

END-PROC;

// ---------------------------------------------------------------------------
// tearDown - called automatically by RPGUnit after each test procedure
// ---------------------------------------------------------------------------

DCL-PROC tearDown          EXPORT;
  DCL-PI *N END-PI;

  CloseFiles();

END-PROC;

// ---------------------------------------------------------------------------
// testGetNextId_WithRecords
//   Insert a sentinel record at ID 77, assert GetNextId returns 78,
//   then delete the sentinel.
// ---------------------------------------------------------------------------

DCL-PROC testGetNextId_WithRecords EXPORT;
  DCL-PI *N END-PI;

  DCL-S l_Result PACKED(5:0);

  // Insert sentinel record at known ID 77
  AddTodoRecord(77: 'Watermark record': %date(*SYS));

  l_Result = GetNextId();
  iEqual(78: l_Result);

  // Clean up
  DeleteTodoRecord(77);

END-PROC;

// ---------------------------------------------------------------------------
// testGetNextId_NoHigherRecord
//   Insert a sentinel at the high ID 9999, assert GetNextId returns 10000,
//   then delete the sentinel.  Does NOT touch other records.
// ---------------------------------------------------------------------------

DCL-PROC testGetNextId_NoHigherRecord EXPORT;
  DCL-PI *N END-PI;

  DCL-S l_Result PACKED(5:0);

  // Insert sentinel record at high-watermark ID 9999
  AddTodoRecord(9999: 'High watermark sentinel': %date(*SYS));

  l_Result = GetNextId();
  iEqual(10000: l_Result);

  // Clean up
  DeleteTodoRecord(9999);

END-PROC;

// ---------------------------------------------------------------------------
// testValidateDescription_Blank
//   *BLANKS must be rejected (returns *OFF).
// ---------------------------------------------------------------------------

DCL-PROC testValidateDescription_Blank EXPORT;
  DCL-PI *N END-PI;

  DCL-S l_Desc CHAR(50) INZ(*BLANKS);

  assert(NOT ValidateDescription(l_Desc): 'Blank description should fail');

END-PROC;

// ---------------------------------------------------------------------------
// testValidateDescription_Spaces
//   Three spaces must be rejected (returns *OFF).
// ---------------------------------------------------------------------------

DCL-PROC testValidateDescription_Spaces EXPORT;
  DCL-PI *N END-PI;

  DCL-S l_Desc CHAR(50) INZ('   ');

  assert(NOT ValidateDescription(l_Desc): 'Spaces-only description should fail');

END-PROC;

// ---------------------------------------------------------------------------
// testValidateDescription_Valid
//   A real description must be accepted (returns *ON).
// ---------------------------------------------------------------------------

DCL-PROC testValidateDescription_Valid EXPORT;
  DCL-PI *N END-PI;

  DCL-S l_Desc CHAR(50) INZ('Buy milk');

  assert(ValidateDescription(l_Desc): 'Valid description should pass');

END-PROC;

// ---------------------------------------------------------------------------
// testAddTodoRecord
//   Insert a record at ID 8001, read it back, verify all fields, then delete.
// ---------------------------------------------------------------------------

DCL-PROC testAddTodoRecord EXPORT;
  DCL-PI *N END-PI;

  DCL-DS l_Rec LIKEDS(todoRec_t);
  DCL-S  l_Found IND;

  // Insert test record
  AddTodoRecord(8001: 'Test add record': %date(*SYS));

  // Read back by ID
  l_Found = GetTodoById(8001: l_Rec);

  assert(l_Found: 'Record 8001 should exist after AddTodoRecord');
  iEqual(8001: l_Rec.tdId);
  aEqual(%trimr(l_Rec.tdDesc): 'Test add record');
  aEqual('0': l_Rec.tdDone);

  // Clean up
  DeleteTodoRecord(8001);

END-PROC;

// ---------------------------------------------------------------------------
// testMarkDoneRecord
//   Insert a record at ID 8002 (TDDONE='0'), call MarkDoneRecord,
//   read it back and assert TDDONE='1', then delete.
// ---------------------------------------------------------------------------

DCL-PROC testMarkDoneRecord EXPORT;
  DCL-PI *N END-PI;

  DCL-DS l_Rec LIKEDS(todoRec_t);
  DCL-S  l_Found IND;

  // Insert test record — TDDONE defaults to '0' in AddTodoRecord
  AddTodoRecord(8002: 'Test mark done': %date(*SYS));

  // Mark it done
  MarkDoneRecord(8002);

  // Read back — GetTodoById chains TODOPF directly so it sees done records
  l_Found = GetTodoById(8002: l_Rec);

  assert(l_Found: 'Record 8002 should exist after MarkDoneRecord');
  aEqual('1': l_Rec.tdDone);

  // Clean up
  DeleteTodoRecord(8002);

END-PROC;
