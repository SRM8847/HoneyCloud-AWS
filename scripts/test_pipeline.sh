#!/usr/bin/env bash
set -euo pipefail

REGION="us-east-1"
REPO_ROOT="$(git rev-parse --show-toplevel)"
CANARY_ARN=$(cd "${REPO_ROOT}/terraform" && terraform output -raw canary_user_arn)

TMP=$(mktemp /tmp/honeycloud_test_XXXXXX.json)
trap "rm -f ${TMP}" EXIT

HC_CANARY_ARN="${CANARY_ARN}" \
python3 - << 'PYEOF' > "${TMP}"
import json, os, datetime

canary_arn = os.environ["HC_CANARY_ARN"]
event_time = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

detail = {
    "eventVersion": "1.08",
    "userIdentity": {
        "type"     : "IAMUser",
        "arn"      : canary_arn,
        "accountId": canary_arn.split(":")[4],
    },
    "eventTime"        : event_time,
    "eventSource"      : "sts.amazonaws.com",
    "eventName"        : "GetCallerIdentity",
    "awsRegion"        : "us-east-1",
    "sourceIPAddress"  : "203.0.113.42",
    "userAgent"        : "aws-cli/2.x Python/3.11",
    "requestParameters": None,
    "responseElements" : None,
    "errorCode"        : "AccessDenied",
    "errorMessage"     : "User is not authorized to perform sts:GetCallerIdentity",
}

entries = [{
    "Source"    : "aws.sts",
    "DetailType": "AWS API Call via CloudTrail",
    "Detail"    : json.dumps(detail),
}]
print(json.dumps(entries))
PYEOF

aws events put-events --entries "file://${TMP}" --region "${REGION}"

echo ""
echo "Check:"
echo "  1. CloudWatch: /aws/lambda/honeycloud-alert-enrichment (within 30s)"
echo "  2. Email: soumyarmohanty23@gmail.com (within 2 min)"
echo "  3. Expected: IP=203.0.113.42, ATT&CK=T1526"
