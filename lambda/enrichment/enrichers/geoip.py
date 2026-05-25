import requests

FIELDS = "status,country,countryCode,city,as,isp,proxy,hosting,query"

def enrich_geoip(ip: str) -> dict:
    try:
        r = requests.get(
            f"http://ip-api.com/json/{ip}",
            params={"fields": FIELDS},
            timeout=5,
        )
        r.raise_for_status()
        data = r.json()
        return data if data.get("status") == "success" else {}
    except Exception as e:
        return {"error": str(e)}
