# HoneyCloud Architecture

## Three Canary Surfaces
1. Canary IAM key — leaked via public GitHub Gist
2. Honey S3 bucket — realistic lure objects
3. EC2 IMDS mock — Flask SSRF honeypot on port 80

## Detection Pipeline
CloudTrail + EventBridge → Lambda enrichment (geo/reputation/ATT&CK) → SNS → Email

## ATT&CK Mapping
See lambda/enrichment/enrichers/attack_tagger.py for full eventName → technique ID mapping.
