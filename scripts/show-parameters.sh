#!/bin/sh

set -eu

MESSAGE="${1:-No message supplied}"
EXECUTION_MODE="${2:-standard}"

echo "========================================"
echo "Argo Workflow Git Script"
echo "========================================"
echo "Message argument:     ${MESSAGE}"
echo "Execution mode:       ${EXECUTION_MODE}"
echo "Environment:          ${DEPLOY_ENVIRONMENT:-not-set}"
echo "Application:          ${APPLICATION_NAME:-not-set}"
echo "Log level:            ${LOG_LEVEL:-not-set}"
echo "Workflow name:        ${WORKFLOW_NAME:-not-set}"
echo "Pod name:             ${POD_NAME:-not-set}"
echo "Git revision:         ${GIT_REVISION:-not-set}"
echo "Current directory:    $(pwd)"
echo "Current date:         $(date)"
echo "========================================"