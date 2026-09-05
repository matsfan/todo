# TODOBL and TODOTEST are compiled to *MODULE here; QBNDSRC/Rules.mk turns each
# into a *SRVPGM (TOBi has no rule for building a *SRVPGM straight from a module -
# it always needs a binder-source dependency, see QBNDSRC/TODOBL.BND).
TODOBL.MODULE:   TODOBL.RPGLE
TODOTEST.MODULE: TODOTEST.RPGLE

TODOMAIN.PGM: TODOMAIN.RPGLE TODODSPPF.FILE TODOBND.BNDDIR
