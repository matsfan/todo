# RPGUnit's test-discovery scans exported names for a "test" prefix, so
# QBNDSRC/TODOTEST.BND's EXPORT SYMBOL case must match TODOTEST.RPGLE's
# procedure names exactly (setUp, testGetNextId_WithRecords, ...) - unlike
# TODOBL.BND, whose symbols are the pre-existing uppercase EXTPROC names
# that TODOMAIN.RPGLE and TODOTEST.RPGLE already prototype against.

TODOBND.BNDDIR: TODOBND.BNDDIR TODOBL.SRVPGM

TODOBL.SRVPGM: TODOBL.BND TODOBL.MODULE

# TODOTEST.RPGLE calls TODOBL's exported procedures directly, so it needs
# TODOBND the same way TODOMAIN does, in addition to RPGUnit's own runner
# service program - see AGENTS.md's CRTSRVPGM for TODOTEST, which binds both
# BNDDIR(*CURLIB/TODOBND) and BNDSRVPGM(RPGUNIT/RUCRTTST).
#
# NEEDS LIVE VERIFICATION on pub400: the "| /QSYS.LIB/..." order-only
# prerequisite is how a service program in another library (RPGUNIT/RUCRTTST)
# is meant to reach TOBi's externalsrvpgms detection (it strips
# /QSYS.LIB/<lib>.LIB/<obj>.SRVPGM down to the object name) - confirmed by
# reading TOBi's own build rules, but not yet exercised against a real
# RPGUNIT install.
TODOTEST.SRVPGM: TODOTEST.BND TODOTEST.MODULE TODOBND.BNDDIR | /QSYS.LIB/RPGUNIT.LIB/RUCRTTST.SRVPGM
