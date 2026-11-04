#!/usr/bin/env bash
# .bob/hooks/ibmi-post-stop.sh
#
# Deploy+compile is now handled by GitHub Actions CI — this hook is a no-op.
# Previously it ran ibmi-deploy.sh + ibmi-compile.sh against MBPRICE1 at session end.
# That responsibility has moved to the two CI workflows:
#   push to any branch except main  →  deploy-dev.yml   →  MBPRICE1 (todo-dev)
#   push to main                    →  deploy-test.yml  →  MBPRICE2 (todo-test)

echo "Deploy+compile is now handled by GitHub Actions CI."
echo "Push your branch to trigger a build:"
echo "  feature branch → MBPRICE1 (todo-dev)"
echo "  main           → MBPRICE2 (todo-test)"
exit 0
