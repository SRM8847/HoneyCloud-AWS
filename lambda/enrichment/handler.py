import json
import os
import logging
import boto3
from enrichers.geoip import enrich_geoip
from enrichers.abuseipdb import enrich_abuseipdb
from enrichers.attack_tagger import tag_attack_technique

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
ABUSEIPDB_KEY = os.environ["ABUSEIPDB_API_KEY"]

sns = boto3.client("sns")


def lambda_handler(event, context):
    logger.info("Raw event: %s", json.dumps(event))
    try:
        alert = extract_core_fields(event)

        if alert["source_ip"] and alert["source_ip"] not in ("AWS Internal", ""):
            alert["geo"]        = enrich_geoip(alert["source_ip"])
            alert["reputation"] = enrich_abuseipdb(alert["source_ip"], ABUSEIPDB_KEY)
        else:
            alert["geo"]        = {}
            alert["reputation"] = {"abuse_score": "N/A"}

        alert["attack"] = tag_attack_technique(alert["event_name"])
        message = format_alert(alert)

        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[HONEYCLOUD] Canary triggered: {alert['event_name']}",
            Message=message,
        )
        logger.info("Alert published: %s", alert["event_name"])

    except Exception as e:
        logger.exception("Enrichment failed: %s", e)
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject="[HONEYCLOUD] Canary triggered (enrichment error)",
            Message=f"Raw event:\n{json.dumps(event, indent=2)}\n\nError: {e}",
        )


def extract_core_fields(event: dict) -> dict:
    source = event.get("source", "")
    detail = event.get("detail", {})

    if source == "honeycloud.ssrf":
        return {
            "trigger_type"  : "SSRF_HONEYPOT",
            "event_time"    : detail.get("eventTime", "unknown"),
            "event_name"    : "IMDSHoneypotAccess",
            "event_source"  : "honeycloud.ssrf",
            "source_ip"     : detail.get("sourceIPAddress", ""),
            "user_agent"    : detail.get("userAgent", ""),
            "principal_arn" : "N/A (SSRF — no IAM principal)",
            "account_id"    : "",
            "region"        : detail.get("awsRegion", ""),
            "request_params": {"path": detail.get("requestedPath", "")},
            "error_code"    : "",
            "error_message" : "",
        }
    else:
        uid = detail.get("userIdentity", {})
        return {
            "trigger_type"  : "CLOUDTRAIL",
            "event_time"    : detail.get("eventTime", "unknown"),
            "event_name"    : detail.get("eventName", "unknown"),
            "event_source"  : detail.get("eventSource", "unknown"),
            "source_ip"     : detail.get("sourceIPAddress", ""),
            "user_agent"    : detail.get("userAgent", ""),
            "principal_arn" : uid.get("arn", ""),
            "account_id"    : uid.get("accountId", ""),
            "region"        : detail.get("awsRegion", ""),
            "request_params": detail.get("requestParameters") or {},
            "error_code"    : detail.get("errorCode", ""),
            "error_message" : detail.get("errorMessage", ""),
        }


def format_alert(alert: dict) -> str:
    geo  = alert.get("geo", {})
    rep  = alert.get("reputation", {})
    atk  = alert.get("attack", {})
    tool = fingerprint_tool(alert["user_agent"])
    lines = [
        "=" * 60,
        f"HONEYCLOUD CANARY TRIGGERED [{alert['trigger_type']}]",
        "=" * 60,
        f"Time         : {alert['event_time']}",
        f"Event        : {alert['event_name']} ({alert['event_source']})",
        f"Principal    : {alert['principal_arn']}",
        f"Region       : {alert['region']}",
        "",
        "-- Attacker --",
        f"Source IP    : {alert['source_ip']}",
        f"Tool         : {tool}",
        f"User-Agent   : {alert['user_agent']}",
        "",
        "-- Geolocation --",
        f"Country      : {geo.get('country', 'N/A')} ({geo.get('countryCode', '')})",
        f"City         : {geo.get('city', 'N/A')}",
        f"ASN          : {geo.get('as', 'N/A')}",
        f"ISP          : {geo.get('isp', 'N/A')}",
        f"VPN/Proxy    : {geo.get('proxy', 'N/A')} | Hosting: {geo.get('hosting', 'N/A')}",
        "",
        "-- Reputation --",
        f"AbuseIPDB    : {rep.get('abuse_score', 'N/A')}/100",
        f"Reports      : {rep.get('total_reports', 'N/A')}",
        f"Last Seen    : {rep.get('last_reported_at', 'N/A')}",
        "",
        "-- ATT&CK --",
        f"Technique    : {atk.get('technique_id', 'N/A')} - {atk.get('technique_name', 'N/A')}",
        f"Tactic       : {atk.get('tactic', 'N/A')}",
        f"Reference    : {atk.get('attck_url', '')}",
        "",
        "-- Request --",
        f"Params       : {json.dumps(alert['request_params'], indent=2)}",
        f"Error        : {alert['error_code']} {alert['error_message']}",
        "=" * 60,
    ]
    return "\n".join(lines)


def fingerprint_tool(user_agent: str) -> str:
    ua = user_agent.lower()
    if "aws-cli" in ua:         return "AWS CLI"
    if "boto3" in ua:           return "boto3 (Python)"
    if "pacu" in ua:            return "Pacu (AWS exploitation framework)"
    if "terraform" in ua:       return "Terraform"
    if "postman" in ua:         return "Postman"
    if "curl" in ua:            return "curl"
    if "python-requests" in ua: return "Python requests"
    if "go-http" in ua:         return "Go HTTP client"
    if "ruby" in ua:            return "Ruby SDK"
    return f"Unknown ({user_agent[:80]})"
