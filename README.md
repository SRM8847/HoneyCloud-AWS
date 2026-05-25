# HoneyCloud

AWS deception framework. Detects credential theft, cloud recon, and SSRF attacks
using canary IAM keys, a honey S3 bucket, and an EC2 IMDS mock.

## Three Canary Surfaces
- **Canary IAM key** — leaked to a public GitHub Gist as a CI/CD credential
- **Honey S3 bucket** (`platform-prod-configs-a3f9`) — realistic lure objects inside
- **EC2 IMDS mock** (`internal-build-agent-01`) — Flask app on port 80

## Pipeline
1. CloudTrail / EventBridge routes the event to `honeycloud-alert-enrichment` Lambda
2. Lambda enriches: ip-api.com + AbuseIPDB + ATT&CK tagging
3. Alert delivered via SNS → email

## Canary Rotation
```bash
bash scripts/rotate_canary.sh
```

## Teardown
```bash
cd terraform && terraform destroy
```
