# HoneyCloud

A cloud-native deception and detection framework built on AWS. HoneyCloud deploys
canary resources that no legitimate user has any reason to touch — every alert is a
real detection with zero false positives by design.

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Terraform | ≥ 1.6 | [terraform.io](https://developer.hashicorp.com/terraform/install) |
| AWS CLI | v2 | [aws.amazon.com/cli](https://aws.amazon.com/cli/) |
| Python | 3.10+ | `sudo apt install python3` |
| pip | any | `sudo apt install python3-pip` |
| zip | any | `sudo apt install zip` |

You need an AWS account with an IAM user that has admin permissions.
---
            
## Deployment

### 1. Clone the repository

```bash
git clone https://github.com/<your-username>/honeycloud.git
cd honeycloud
```

### 2. Configure AWS CLI

```bash
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Default region: us-east-1
# Default output format: json

# Verify
aws sts get-caller-identity
```

### 3. Get API keys

**AbuseIPDB** (required for reputation enrichment):
- Sign up at [abuseipdb.com](https://www.abuseipdb.com)
- Go to Account → API → Create Key
- Free tier: 1000 checks/day

### 4. Create your `terraform.tfvars`

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
nano terraform/terraform.tfvars
```

Fill in your values:

```hcl
aws_region                = "us-east-1"
aws_profile               = "default"
abuseipdb_api_key         = "your-abuseipdb-key-here"
slack_webhook_url         = "none"
alert_email               = "your-email@example.com"
honey_bucket_name         = "platform-prod-configs-a3f9"
canary_key_rotation_count = 1
```

> `honey_bucket_name` must be globally unique across all AWS accounts. If the
> default name is taken, change the suffix (e.g. `platform-prod-configs-b7e2`).

### 5. Initialise Terraform

```bash
cd terraform
terraform init
```

Expected: `Terraform has been successfully initialized!`

### 6. Build the Lambda package

The Lambda function requires a zip file to be built before Terraform can deploy it.

```bash
cd ..
bash lambda/build.sh
```

Expected: `Built: ~1.2M .../lambda/enrichment.zip`

### 7. Deploy all modules

Deploy each module in order. Verify each gate before moving to the next.

```bash
cd terraform

# Layer 1 — canary resources (can be applied in any order between these three)
terraform apply -target=module.canary_iam
terraform apply -target=module.cloudtrail
terraform apply -target=module.honey_s3

# Layer 2 — notification (must exist before Lambda)
terraform apply -target=module.sns_slack
```

At this point check your email for **"AWS Notification - Subscription Confirmation"**
from AWS. **Click the confirmation link before continuing.** If the subscription is
not confirmed, no alerts will be delivered.

```bash
# Layer 3 — enrichment Lambda
terraform apply -target=module.lambda_enrichment

# Layer 4 — detection rules
terraform apply -target=module.eventbridge

# Layer 5 — SSRF honeypot
terraform apply -target=module.ssrf_honeypot
```

### 8. Final apply (resolve any state gaps)

```bash
terraform plan
# If "No changes" — you're done.
# If changes are shown — apply them:
terraform apply
```

### 9. Verify the deployment

```bash
# Check all 3 EventBridge rules are enabled
aws events list-rules \
  --query "Rules[?contains(Name,'honeycloud')].[Name,State]" \
  --output table

# Get the canary access key (needed for the Gist)
terraform output canary_access_key
terraform output -raw canary_secret_key

# Get the EC2 SSRF honeypot IP
terraform output ssrf_honeypot_ip

# Verify canary user has zero permissions
CANARY_USER=$(aws iam list-users --path-prefix "/service/" \
  --query "Users[?contains(UserName,'svc-deploy-pipeline')].UserName" \
  --output text)

aws iam list-attached-user-policies --user-name ${CANARY_USER}
aws iam list-user-policies --user-name ${CANARY_USER}
aws iam list-groups-for-user --user-name ${CANARY_USER}
# All three must return empty lists
```

### 10. Test the pipeline

Fire a synthetic test event to confirm the full pipeline fires end-to-end:

```bash
cd ..
bash scripts/test_pipeline.sh
```

Expected within 30 seconds: Lambda invocation in CloudWatch logs.
Expected within 2 minutes: enriched alert email received.

Test the SSRF honeypot:

```bash
EC2_IP=$(cd terraform && terraform output -raw ssrf_honeypot_ip)

curl http://${EC2_IP}/latest/meta-data/instance-id
# Expected: i-0a1b2c3d4e5f67890

curl http://${EC2_IP}/latest/meta-data/iam/security-credentials/
# Expected: eks-node-bootstrap-role
```

### 11. Deploy the canary key (optional)

Once the pipeline is confirmed working, leak the canary key to a public GitHub Gist
disguised as a CI/CD credential. Secret scanner bots and credential harvesters pick
it up within hours to days.

Create a **public** Gist at [gist.github.com](https://gist.github.com) with filename
`.env.production`:

```bash
# Platform team CI/CD deployment credentials
# Rotate quarterly per security policy — DO NOT COMMIT
export AWS_ACCESS_KEY_ID=AKIA<your-canary-access-key>
export AWS_SECRET_ACCESS_KEY=<your-canary-secret-key>
export AWS_DEFAULT_REGION=us-east-1
export ECR_REPOSITORY=platform/app
export DEPLOY_ENV=production
```

The canary user has zero permissions — any attacker who uses the key gets
`AccessDenied`. You get the alert.

---

## Canary Rotation

When a real attacker uses the key, rotate immediately:

```bash
bash scripts/rotate_canary.sh
```

The script increments `canary_key_rotation_count` in `terraform.tfvars`, forcing
Terraform to recreate the IAM user and access key atomically. Target: under 5 minutes
from detection to new key live.

After rotation, update the GitHub Gist with the new key values from:

```bash
cd terraform
terraform output canary_access_key
terraform output -raw canary_secret_key
```

---

## Teardown

### Before destroying

**1. Delete the GitHub Gist** — remove the canary key before destroying the pipeline
behind it. A live key with a dead pipeline is worse than nothing.

**2. Save CloudTrail logs** (if you had real attacker hits you want to keep):

```bash
mkdir -p ~/honeycloud/saved_logs/
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 sync \
  s3://ct-logs-${ACCOUNT_ID}-us-east-1/ \
  ~/honeycloud/saved_logs/
```

**3. Stop the EC2 instance** :

```bash
aws ec2 stop-instances \
  --instance-ids $(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=internal-build-agent-01" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)
```

### Destroy all AWS resources

```bash
cd terraform

# Preview what will be destroyed
terraform plan -destroy

# Destroy — type yes when prompted
terraform destroy
```

Expected: `Destroy complete! Resources: ~35 destroyed.`

If destroy fails partway through (e.g. S3 bucket race with CloudTrail), re-run
`terraform destroy` — it is idempotent.

### Verify everything is gone

```bash
# IAM
aws iam list-users --path-prefix "/service/" \
  --query "Users[?contains(UserName,'svc-deploy-pipeline')]"
aws iam get-role --role-name honeycloud-enrichment-lambda-role 2>&1
aws iam get-role --role-name honeycloud-ssrf-honeypot-role 2>&1
aws iam get-role --role-name cloudtrail-to-cloudwatch-logs 2>&1

# S3
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3api list-buckets --query "Buckets[?Name=='ct-logs-${ACCOUNT_ID}-us-east-1']"
aws s3api list-buckets --query "Buckets[?Name=='platform-prod-configs-a3f9']"

# CloudTrail
aws cloudtrail describe-trails --query "trailList[?Name=='honeycloud-trail']"

# EventBridge
aws events list-rules --query "Rules[?contains(Name,'honeycloud')]"

# Lambda
aws lambda get-function --function-name honeycloud-alert-enrichment 2>&1

# EC2
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=internal-build-agent-01" \
  --query "Reservations[].Instances[?State.Name!='terminated']"

# SNS
aws sns list-topics --query "Topics[?contains(TopicArn,'honeycloud')]"

# CloudWatch Log Groups
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/lambda/honeycloud" \
  --query "logGroups[*].logGroupName"
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/cloudtrail/honeycloud" \
  --query "logGroups[*].logGroupName"
```

All should return empty lists or NoSuchEntity errors.

If CloudWatch log groups persist after destroy:

```bash
aws logs delete-log-group \
  --log-group-name "/aws/lambda/honeycloud-alert-enrichment"
aws logs delete-log-group \
  --log-group-name "/aws/cloudtrail/honeycloud"
```

### Local cleanup

```bash
cd ~/honeycloud
rm -f lambda/enrichment.zip
rm -rf lambda/enrichment/package/
rm -f terraform/terraform.tfstate
rm -f terraform/terraform.tfstate.backup
rm -f terraform/terraform.tfvars
```

---

## How It Works

HoneyCloud plants three canary surfaces across an AWS account. When any surface is
touched, a fully automated enrichment pipeline fires within seconds:

```
Trigger (IAM / S3 / SSRF)
    │
    ▼
CloudTrail + EventBridge
    │
    ▼
Lambda Enrichment
    ├── Geolocation   (ip-api.com — country, city, ASN, ISP, VPN/proxy detection)
    ├── Reputation    (AbuseIPDB — abuse confidence score, report history)
    ├── Fingerprint   (User-Agent → tool identification)
    └── ATT&CK Tag    (eventName → MITRE technique ID + tactic)
    │
    ▼
SNS → Email Alert
```

---

## Three Canary Surfaces

### 1. Canary IAM Key — Credential Theft Detection

An IAM user named to look like a CI/CD service account
(`svc-deploy-pipeline-<hex>`) with one access key and **zero permissions**.
The key is leaked to a public GitHub Gist disguised as a production deployment
credential.

When an attacker uses the key — even `sts:GetCallerIdentity` to validate it —
CloudTrail logs the attempt and EventBridge fires the enrichment pipeline.
The attacker gets `AccessDenied`. You get a full alert.

**ATT&CK:** T1526, T1087.004, T1078.004

### 2. Honey S3 Bucket — Data Exfiltration Detection

A bucket named `platform-prod-configs-a3f9` containing realistic lure objects:

```
configs/database.yml              ← PostgreSQL production config
deploy/github-actions-deploy.env  ← CI/CD deployment variables
terraform/prod.tfvars             ← Infrastructure variables
```

Any read or write on this bucket triggers Rule 2 via CloudTrail S3 data events.
GetObject is detected even though it is not a write event.

**ATT&CK:** T1530

### 3. EC2 IMDS Mock — SSRF Attack Detection

A `t3.micro` EC2 instance (`internal-build-agent-01`) running Flask on port 80
that simulates the AWS Instance Metadata Service. Returns realistic fake responses
including a role name and structurally valid (but inert) credentials.

Every IMDS request fires a custom EventBridge event immediately — no CloudTrail lag.

**ATT&CK:** T1552.001

---

## Alert Format

```
============================================================
HONEYCLOUD CANARY TRIGGERED [CLOUDTRAIL]
============================================================
Time         : 2026-05-25T10:32:11Z
Event        : GetCallerIdentity (sts.amazonaws.com)
Principal    : arn:aws:iam::188496450054:user/service/svc-deploy-pipeline-5328ba58
Region       : us-east-1

-- Attacker --
Source IP    : 203.x.x.x
Tool         : AWS CLI
User-Agent   : aws-cli/2.15.0 Python/3.11.0 Linux/6.1.0

-- Geolocation --
Country      : India (IN)
City         : Bhubaneswar
ASN          : AS9829 National Internet Backbone
ISP          : BSNL
VPN/Proxy    : false | Hosting: false

-- Reputation --
AbuseIPDB    : 0/100
Reports      : 0
Last Seen    : N/A

-- ATT&CK --
Technique    : T1526 - Cloud Service Discovery
Tactic       : Discovery
Reference    : https://attack.mitre.org/techniques/T1526/

-- Request --
Error        : AccessDenied User is not authorized to perform sts:GetCallerIdentity
============================================================
```

---

## Repository Structure

```
honeycloud/
│
├── terraform/
│   ├── main.tf                       # Root module — wires all modules together
│   ├── providers.tf                  # AWS + random provider config
│   ├── variables.tf                  # Input variable declarations
│   ├── outputs.tf                    # Canary key, bucket name, EC2 IP
│   ├── terraform.tfvars.example      # Safe example values — commit this
│   ├── terraform.tfvars              # Real values — GITIGNORED, never commit
│   │
│   └── modules/
│       ├── canary_iam/               # IAM user + access key (zero permissions)
│       ├── cloudtrail/               # Multi-region trail + S3 data events
│       ├── honey_s3/                 # Honey bucket + lure objects
│       ├── sns_slack/                # SNS topic + email subscription
│       ├── lambda_enrichment/        # Lambda IAM role + function
│       ├── eventbridge/              # Three detection rules + permissions
│       └── ssrf_honeypot/
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           ├── imds_mock.py          # Flask IMDS simulation
│           └── user_data.sh.tpl     # EC2 bootstrap script template
│
├── lambda/
│   ├── build.sh                      # Builds enrichment.zip for Lambda deploy
│   └── enrichment/
│       ├── handler.py                # Lambda handler — event normalisation
│       ├── requirements.txt          # requests==2.31.0
│       └── enrichers/
│           ├── __init__.py
│           ├── geoip.py              # ip-api.com geolocation + proxy detection
│           ├── abuseipdb.py          # AbuseIPDB reputation check
│           └── attack_tagger.py      # eventName → ATT&CK technique mapping
│
├── scripts/
│   ├── rotate_canary.sh              # Rotate triggered canary key in <5 minutes
│   └── test_pipeline.sh             # Fire synthetic test event end-to-end
│
├── docs/
│   ├── architecture.md              # Full architecture and design decisions
│   └── ttp_observations.md          # Log of real attacker hits
│
├── .gitignore
└── README.md
```

---

## ATT&CK Coverage

| Event | Technique | Name | Tactic |
|---|---|---|---|
| GetCallerIdentity | T1526 | Cloud Service Discovery | Discovery |
| ListBuckets | T1619 | Cloud Storage Object Discovery | Discovery |
| ListUsers / ListRoles | T1087.004 | Cloud Account Discovery | Discovery |
| GetObject | T1530 | Data from Cloud Storage | Collection |
| GetSecretValue | T1555 | Credentials from Password Stores | Credential Access |
| IMDSHoneypotAccess | T1552.001 | Unsecured Credentials: IMDS | Credential Access |
| CreateAccessKey | T1098.001 | Additional Cloud Credentials | Persistence |
| DeleteTrail / StopLogging | T1562.008 | Disable Cloud Logs | Defense Evasion |

---

## Tech Stack

| Layer | Technology |
|---|---|
| IaC | Terraform ≥ 1.6, AWS provider ~5.0 |
| Detection | AWS CloudTrail, Amazon EventBridge |
| Enrichment | AWS Lambda (Python 3.11) |
| Geo/ASN | ip-api.com (free, no key required) |
| Reputation | AbuseIPDB v2 API |
| ATT&CK | MITRE ATT&CK for Cloud |
| Notification | Amazon SNS → email |
| Honeypot | EC2 t3.micro + Flask |

