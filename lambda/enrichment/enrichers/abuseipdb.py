import requests

def enrich_abuseipdb(ip: str, api_key: str) -> dict:
    try:
        r = requests.get(
            "https://api.abuseipdb.com/api/v2/check",
            headers={"Key": api_key, "Accept": "application/json"},
            params={"ipAddress": ip, "maxAgeInDays": 90},
            timeout=5,
        )
        r.raise_for_status()
        data = r.json().get("data", {})
        return {
            "abuse_score"     : data.get("abuseConfidenceScore", 0),
            "total_reports"   : data.get("totalReports", 0),
            "last_reported_at": data.get("lastReportedAt", ""),
            "is_whitelisted"  : data.get("isWhitelisted", False),
            "isp"             : data.get("isp", ""),
            "usage_type"      : data.get("usageType", ""),
        }
    except Exception as e:
        return {"error": str(e)}
