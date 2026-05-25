import json
import os
import datetime
import boto3
from flask import Flask, request

app = Flask(__name__)
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
events_client = boto3.client("events", region_name=AWS_REGION)

FAKE_RESPONSES = {
    "/latest/meta-data/instance-id"              : "i-0a1b2c3d4e5f67890",
    "/latest/meta-data/public-ipv4"              : "54.192.0.1",
    "/latest/meta-data/local-ipv4"               : "10.0.1.100",
    "/latest/meta-data/hostname"                 : "ip-10-0-1-100.ec2.internal",
    "/latest/meta-data/iam/security-credentials/": "eks-node-bootstrap-role",
    "/latest/meta-data/iam/security-credentials/eks-node-bootstrap-role": json.dumps({
        "Code"           : "Success",
        "Type"           : "AWS-HMAC",
        "AccessKeyId"    : "ASIA3XFAKECANARY01",
        "SecretAccessKey": "FaKeS3cr3tKey+DoNotUse+ThisIsAHoneypot",
        "Token"          : "FakeSessionToken//example/ThisIsNotReal",
        "Expiration"     : "2099-12-31T23:59:59Z",
    }),
}

def fire_event(path, source_ip, user_agent):
    try:
        events_client.put_events(Entries=[{
            "Source"     : "honeycloud.ssrf",
            "DetailType" : "IMDSHoneypotAccess",
            "Detail"     : json.dumps({
                "eventTime"      : datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
                "eventName"      : "IMDSHoneypotAccess",
                "sourceIPAddress": source_ip,
                "userAgent"      : user_agent,
                "requestedPath"  : path,
                "awsRegion"      : AWS_REGION,
            }),
        }])
    except Exception as e:
        app.logger.error("EventBridge PutEvents failed: %s", e)

@app.route("/latest/meta-data/", defaults={"path": ""})
@app.route("/latest/meta-data/<path:path>")
def imds(path):
    full_path = "/latest/meta-data/" + path
    source_ip = request.headers.get("X-Forwarded-For", request.remote_addr)
    fire_event(full_path, source_ip, request.headers.get("User-Agent", ""))
    return FAKE_RESPONSES.get(full_path, "not found"), 200

@app.route("/latest/api/token", methods=["PUT"])
def imdsv2_token():
    source_ip = request.headers.get("X-Forwarded-For", request.remote_addr)
    fire_event("/latest/api/token", source_ip, request.headers.get("User-Agent", ""))
    return "FakeIMDSv2Token-HoneypotDoNotUse", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
