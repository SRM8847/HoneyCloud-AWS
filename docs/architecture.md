\# HoneyCloud — Architecture



\## Overview



HoneyCloud is a deception-based threat detection system built entirely on native

AWS services. It deploys three canary surfaces, each wired to the same enrichment

pipeline via EventBridge. No legitimate user has any reason to interact with these

resources — every trigger is a real detection.



\---



\## Dependency Chain



Resources are deployed in a strict order. Each layer depends on the one above it

being fully operational before it is created.



```

┌─────────────────────────────────────────────────────┐

│  Layer 1 — Canary Resources (deployed in parallel)  │

│                                                     │

│   canary\_iam        cloudtrail        honey\_s3      │

│   (IAM user +       (trail + S3       (bucket +     │

│    access key)       data events)      lure files)  │

└──────────────────────────┬──────────────────────────┘

&#x20;                          │

&#x20;                          ▼

┌─────────────────────────────────────────────────────┐

│  Layer 2 — Notification                             │

│                                                     │

│                    sns\_slack                        │

│             (SNS topic + email sub)                 │

└──────────────────────────┬──────────────────────────┘

&#x20;                          │ topic\_arn

&#x20;                          ▼

┌─────────────────────────────────────────────────────┐

│  Layer 3 — Enrichment                               │

│                                                     │

│               lambda\_enrichment                     │

│         (Python 3.11 function + IAM role)           │

└──────────────────────────┬──────────────────────────┘

&#x20;                          │ function\_arn + function\_name

&#x20;                          ▼

┌─────────────────────────────────────────────────────┐

│  Layer 4 — Detection Rules                          │

│                                                     │

│                  eventbridge                        │

│         (3 rules + Lambda permissions)              │

└──────────────────────────┬──────────────────────────┘

&#x20;                          │ rules active

&#x20;                          ▼

┌─────────────────────────────────────────────────────┐

│  Layer 5 — SSRF Honeypot                            │

│                                                     │

│                 ssrf\_honeypot                       │

│         (EC2 t3.micro + Flask IMDS mock)            │

└─────────────────────────────────────────────────────┘

```



\---



\## Detection Pipeline — Full Event Flow



\### Path A: Canary IAM Key Used



```

Attacker uses stolen key anywhere

&#x20;       │

&#x20;       ▼

AWS API call hits any service

&#x20; (sts, iam, s3, ec2, lambda...)

&#x20;       │

&#x20;       ▼

CloudTrail logs the event

&#x20; ├── eventName: GetCallerIdentity / ListUsers / etc.

&#x20; ├── sourceIPAddress: attacker's IP

&#x20; ├── userAgent: tool fingerprint

&#x20; └── userIdentity.arn: canary user ARN

&#x20;       │

&#x20;       ▼ (delivery lag: 5–15 min)

EventBridge Rule 1

&#x20; Matches: userIdentity.arn = canary user ARN

&#x20;       │

&#x20;       ▼

Lambda enrichment handler

&#x20;       │

&#x20;       ▼

Email alert

```



\### Path B: Honey S3 Bucket Accessed



```

Attacker reads a lure object (GetObject)

or lists the bucket (ListObjects)

&#x20;       │

&#x20;       ▼

CloudTrail S3 data event logged

&#x20; (requires event\_selector with

&#x20;  type=AWS::S3::Object in the trail)

&#x20;       │

&#x20;       ▼ (delivery lag: 5–15 min)

EventBridge Rule 2

&#x20; Matches: source=aws.s3

&#x20;          requestParameters.bucketName = honey bucket

&#x20;       │

&#x20;       ▼

Lambda enrichment handler

&#x20;       │

&#x20;       ▼

Email alert

```



> \*\*Why CloudTrail for reads:\*\* S3 EventBridge bucket notifications only cover

> write and delete events — GetObject is not a write. Detecting reads requires

> CloudTrail S3 data event logging with a rule matching

> `detail-type: AWS API Call via CloudTrail`. This is why the trail has

> `event\_selector.data\_resource.type = AWS::S3::Object` configured globally.



\### Path C: SSRF Honeypot Accessed



```

Attacker hits http://<ec2-ip>/latest/meta-data/...

&#x20; (via SSRF vulnerability or direct probe)

&#x20;       │

&#x20;       ▼

Flask returns fake metadata response

&#x20;       │

&#x20;       ▼ (immediate — no CloudTrail lag)

EC2 calls events:PutEvents

&#x20; Source:     honeycloud.ssrf

&#x20; DetailType: IMDSHoneypotAccess

&#x20; Detail:     sourceIPAddress, userAgent, requestedPath

&#x20;       │

&#x20;       ▼

EventBridge Rule 3

&#x20; Matches: source=honeycloud.ssrf

&#x20;       │

&#x20;       ▼

Lambda enrichment handler

&#x20;       │

&#x20;       ▼

Email alert

```



\---



\## Module Breakdown



\### `canary\_iam`



| Resource | Name | Purpose |

|---|---|---|

| `aws\_iam\_user` | `svc-deploy-pipeline-<hex>` | The canary identity |

| `aws\_iam\_access\_key` | (attached to above) | The leaked credential |

| `random\_id` | suffix | Hex suffix — regenerated on rotation |



The user name is designed to look like a real CI/CD service account to an attacker

scanning stolen credentials. The path `/service/` separates it from human users in

IAM queries.



\*\*Zero permissions:\*\* No `aws\_iam\_user\_policy`, no `aws\_iam\_user\_policy\_attachment`,

no group membership. Every API call made with this key returns `AccessDenied`.

CloudTrail logs the attempt regardless of the response code.



\*\*Rotation mechanism:\*\* `rotation\_count` is a keeper on `random\_id`. Incrementing

it forces a new suffix, new user name, new access key. The old user and key are

destroyed atomically by Terraform.



\---



\### `cloudtrail`



| Resource | Name | Purpose |

|---|---|---|

| `aws\_cloudtrail` | `honeycloud-trail` | The trail |

| `aws\_s3\_bucket` | `ct-logs-<account>-us-east-1` | Log storage |

| `aws\_cloudwatch\_log\_group` | `/aws/cloudtrail/honeycloud` | Real-time log stream |

| `aws\_iam\_role` | `cloudtrail-to-cloudwatch-logs` | Delivery permissions |



Trail is multi-region (`is\_multi\_region\_trail = true`) — catches canary key usage

from any region, not just us-east-1. Global service events enabled — captures

IAM and STS calls which are global services.



S3 data events are logged for all buckets (`values = \["arn:aws:s3"]`). This is

intentional — in a canary account with no legitimate S3 traffic, the noise is

zero and we catch reads on the honey bucket.



\---



\### `honey\_s3`



| Resource | Name | Purpose |

|---|---|---|

| `aws\_s3\_bucket` | `platform-prod-configs-a3f9` | The honey bucket |

| `aws\_s3\_bucket\_notification` | (on above) | EventBridge for write/delete events |

| `aws\_s3\_object` × 3 | configs/, deploy/, terraform/ | Lure objects |



Bucket name follows the pattern of real platform config buckets — no words like

"honey", "test", "canary", or "fake". Public access fully blocked — consistent

with a real production config bucket.



Lure objects are named and formatted to look like genuine infrastructure files

that an attacker would want to exfiltrate:

\- `configs/database.yml` — database connection string with production host

\- `deploy/github-actions-deploy.env` — CI/CD deployment role ARN

\- `terraform/prod.tfvars` — infrastructure sizing variables



\---



\### `sns\_slack`



| Resource | Name | Purpose |

|---|---|---|

| `aws\_sns\_topic` | `honeycloud-alerts` | Alert delivery topic |

| `aws\_sns\_topic\_subscription` | email | soumyarmohanty23@gmail.com |



Simple two-resource module. The topic ARN is passed as an environment variable to

the Lambda function at deploy time — this is why SNS must be deployed before Lambda.



Subscription must be manually confirmed via the AWS confirmation email before any

alerts can be delivered. Terraform creates the subscription in `PendingConfirmation`

state.



\---



\### `lambda\_enrichment`



| Resource | Name | Purpose |

|---|---|---|

| `aws\_lambda\_function` | `honeycloud-alert-enrichment` | Enrichment handler |

| `aws\_iam\_role` | `honeycloud-enrichment-lambda-role` | Execution role |

| `aws\_cloudwatch\_log\_group` | `/aws/lambda/honeycloud-alert-enrichment` | Logs |



\*\*Runtime:\*\* Python 3.11 — `boto3` and `botocore` are pre-installed.

\*\*Timeout:\*\* 30 seconds — allows for two external HTTP calls (ip-api.com + AbuseIPDB).

\*\*Memory:\*\* 256MB — sufficient for the enrichment workload.



Lambda is deployed \*\*outside any VPC\*\* (default configuration). This is intentional

— VPC-attached Lambdas cannot reach the internet without a NAT gateway, which adds

cost and complexity. The enrichment function needs to reach ip-api.com and

api.abuseipdb.com.



\*\*Event normalisation:\*\* The handler receives events from two different shapes:



```

CloudTrail events (IAM + S3):          SSRF custom events:

{                                      {

&#x20; source: "aws.sts",                     source: "honeycloud.ssrf",

&#x20; detail-type: "AWS API Call            detail-type: "IMDSHoneypotAccess",

&#x20;              via CloudTrail",          detail: {

&#x20; detail: {                               sourceIPAddress: "...",

&#x20;   eventName: "...",                     userAgent: "...",

&#x20;   sourceIPAddress: "...",               requestedPath: "..."

&#x20;   userIdentity: { arn: "..." }        }

&#x20; }                                    }

}

```



`extract\_core\_fields()` normalises both shapes into a single dict before enrichment.



\*\*Enrichment pipeline (per invocation):\*\*

1\. `extract\_core\_fields()` — normalise event shape

2\. `enrich\_geoip()` — ip-api.com: country, city, ASN, ISP, VPN/proxy/hosting flags

3\. `enrich\_abuseipdb()` — confidence score, report count, last seen, usage type

4\. `fingerprint\_tool()` — User-Agent substring matching → tool name

5\. `tag\_attack\_technique()` — eventName lookup in TECHNIQUE\_MAP → ATT\&CK ID

6\. `format\_alert()` — structured plaintext alert

7\. `sns.publish()` — deliver to topic



On any exception, a fallback SNS publish sends the raw event — alerts are never

silently dropped.



\---



\### `eventbridge`



| Resource | Name | Matches |

|---|---|---|

| `aws\_cloudwatch\_event\_rule` | `honeycloud-canary-iam-trigger` | CloudTrail events by canary ARN |

| `aws\_cloudwatch\_event\_rule` | `honeycloud-honey-s3-trigger` | CloudTrail S3 data events for honey bucket |

| `aws\_cloudwatch\_event\_rule` | `honeycloud-ssrf-trigger` | Custom `honeycloud.ssrf` events |

| `aws\_lambda\_permission` × 3 | AllowEventBridge\* | Grants EventBridge invocation rights |



Three `aws\_cloudwatch\_event\_target` resources point all three rules at the same

Lambda function. Three `aws\_lambda\_permission` resources grant `events.amazonaws.com`

the right to invoke that function — one permission per rule, per AWS requirement.



\*\*Rule 1 event pattern:\*\*

```json

{

&#x20; "source": \["aws.sts", "aws.iam", "aws.s3", "aws.ec2", "aws.lambda"],

&#x20; "detail-type": \["AWS API Call via CloudTrail"],

&#x20; "detail": {

&#x20;   "userIdentity": {

&#x20;     "type": \["IAMUser"],

&#x20;     "arn": \["arn:aws:iam::<account>:user/service/svc-deploy-pipeline-<hex>"]

&#x20;   }

&#x20; }

}

```



\*\*Rule 2 event pattern:\*\*

```json

{

&#x20; "source": \["aws.s3"],

&#x20; "detail-type": \["AWS API Call via CloudTrail"],

&#x20; "detail": {

&#x20;   "requestParameters": {

&#x20;     "bucketName": \["platform-prod-configs-a3f9"]

&#x20;   }

&#x20; }

}

```



\*\*Rule 3 event pattern:\*\*

```json

{

&#x20; "source": \["honeycloud.ssrf"],

&#x20; "detail-type": \["IMDSHoneypotAccess"]

}

```



\---



\### `ssrf\_honeypot`



| Resource | Name | Purpose |

|---|---|---|

| `aws\_instance` | `internal-build-agent-01` | The honeypot |

| `aws\_security\_group` | `honeycloud-ssrf-honeypot-sg` | Port 80 inbound |

| `aws\_iam\_role` | `honeycloud-ssrf-honeypot-role` | Instance role |

| `aws\_iam\_instance\_profile` | `honeycloud-ssrf-honeypot-profile` | Attached to EC2 |



Instance name `internal-build-agent-01` looks like a real CI/CD build agent —

not obviously a honeypot to a scanning attacker.



\*\*Why Flask on port 80 and not 169.254.169.254:\*\* The real IMDS runs on a

link-local address that can't be publicly routed. A public-facing SSRF honeypot

runs on a standard public IP and port 80, relying on the attacker having already

discovered the IP (via the canary key Gist, Shodan, or port scan).



\*\*Instance profile permissions:\*\* Only `events:PutEvents` — the minimum required

for the Flask app to fire EventBridge events. No S3, no IAM, no other AWS access.



\*\*Fake credentials returned:\*\*

```json

{

&#x20; "AccessKeyId": "ASIA3XFAKECANARY01",

&#x20; "SecretAccessKey": "FaKeS3cr3tKey+DoNotUse+ThisIsAHoneypot",

&#x20; "Token": "FakeSessionToken//example/ThisIsNotReal",

&#x20; "Expiration": "2099-12-31T23:59:59Z"

}

```



These are structurally valid (ASIA prefix = temporary credentials, correct field

names) but completely inert. An attacker who tries to use them gets immediate

`InvalidClientTokenId` from AWS.



\---



\## ATT\&CK Technique Mapping



The `attack\_tagger.py` enricher maps AWS API event names to MITRE ATT\&CK

for Cloud technique IDs. The mapping is split into four category dicts merged

at module load time — this pattern makes duplicate-key collisions explicit

rather than silently overwriting.



```

Discovery           → T1526, T1619, T1087.004

Collection          → T1530, T1555, T1552.001

Persistence         → T1098.001, T1136.003, T1098

Defense Evasion     → T1562.008, T1562

Default (catchall)  → T1078.004 (Valid Accounts: Cloud Accounts)

```



The default covers any API call not explicitly mapped — nearly all initial

attacker behaviour with a stolen key maps to T1078.004 (using valid cloud

credentials).



\---



\## Canary Rotation Design



The rotation mechanism uses Terraform's `keepers` argument on `random\_id`:



```hcl

resource "random\_id" "suffix" {

&#x20; byte\_length = 4

&#x20; keepers = {

&#x20;   rotation = var.rotation\_count

&#x20; }

}

```



Incrementing `rotation\_count` in `terraform.tfvars` changes the keeper value,

which forces `random\_id` to generate a new hex suffix. This cascades:



```

new suffix

&#x20; → new IAM user name (svc-deploy-pipeline-<new-hex>)

&#x20;   → old user destroyed

&#x20;   → new access key generated

&#x20;     → old key destroyed

```



Terraform handles the create-before-destroy sequencing. The old key stops working

the moment the new user is created. Rotation time target: under 5 minutes from

detection to new key live in the Gist.



\---



\## Infrastructure as Code — Key Design Decisions



\*\*Why `-target` phased applies:\*\* Each module is independently verifiable before

the next is added. CloudTrail data events can be confirmed active before

EventBridge rules reference them. SNS subscription confirmed before Lambda is

deployed with the topic ARN baked into its environment.



\*\*Why complete stubs at Phase 1:\*\* Terraform resolves all cross-module output

references at plan time, regardless of which module is targeted. All `outputs.tf`

stubs must be declared with placeholder values before `terraform init` runs.



\*\*Why local state:\*\* The `terraform.tfstate` file contains the canary secret key

in plaintext. A remote S3 backend would require additional IAM permissions and

encryption configuration. For a single-account , local state stored

outside the git repository is the simplest secure option.



\*\*Why no VPC for Lambda:\*\* Enrichment requires two outbound HTTP calls to external

APIs. VPC-attached Lambda would require a NAT gateway ($0.045/hr) to reach the

internet. Default non-VPC Lambda routes to the internet directly at no additional cost.



