DISCOVERY = {
    "GetCallerIdentity"              : ("T1526",    "Cloud Service Discovery",        "Discovery"),
    "ListBuckets"                    : ("T1619",    "Cloud Storage Object Discovery", "Discovery"),
    "DescribeInstances"              : ("T1526",    "Cloud Service Discovery",        "Discovery"),
    "ListUsers"                      : ("T1087.004","Cloud Account Discovery",        "Discovery"),
    "ListRoles"                      : ("T1087.004","Cloud Account Discovery",        "Discovery"),
    "GetAccountAuthorizationDetails" : ("T1087.004","Cloud Account Discovery",        "Discovery"),
    "ListFunctions"                  : ("T1526",    "Cloud Service Discovery",        "Discovery"),
}

COLLECTION = {
    "GetObject"         : ("T1530",    "Data from Cloud Storage",                        "Collection"),
    "GetSecretValue"    : ("T1555",    "Credentials from Password Stores",               "Credential Access"),
    "GetParameter"      : ("T1552.001","Credentials In Files",                           "Credential Access"),
    "IMDSHoneypotAccess": ("T1552.001","Unsecured Credentials: Cloud Instance Metadata", "Credential Access"),
}

PERSISTENCE = {
    "CreateAccessKey"   : ("T1098.001","Account Manipulation: Additional Cloud Credentials","Persistence"),
    "CreateLoginProfile": ("T1136.003","Create Cloud Account",                              "Persistence"),
    "AttachUserPolicy"  : ("T1098",    "Account Manipulation",                              "Persistence"),
}

DEFENSE_EVASION = {
    "DeleteTrail" : ("T1562.008","Disable Cloud Logs","Defense Evasion"),
    "StopLogging" : ("T1562.008","Disable Cloud Logs","Defense Evasion"),
    "PutBucketAcl": ("T1562",   "Impair Defenses",   "Defense Evasion"),
}

TECHNIQUE_MAP = {**DISCOVERY, **COLLECTION, **PERSISTENCE, **DEFENSE_EVASION}
DEFAULT = ("T1078.004", "Valid Accounts: Cloud Accounts", "Initial Access")

def tag_attack_technique(event_name: str) -> dict:
    tid, name, tactic = TECHNIQUE_MAP.get(event_name, DEFAULT)
    return {
        "technique_id"  : tid,
        "technique_name": name,
        "tactic"        : tactic,
        "attck_url"     : f"https://attack.mitre.org/techniques/{tid.replace('.', '/')}/"
    }
