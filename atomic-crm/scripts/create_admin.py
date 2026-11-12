"""Create the CRM's first user (becomes administrator) through the local auth admin
API, with the email marked confirmed so no email is sent. Then prove login and a
contact round trip as that user (create, read, delete). Reads CRM_ADMIN_EMAIL and
CRM_ADMIN_PASSWORD from atomic-crm/.env and the service key from ../supabase/.env;
prints no secret. Idempotent: an existing user is reused.

Usage (from Shared\\docker\\atomic-crm):  python scripts/create_admin.py [--check-only]
"""
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
API = "http://127.0.0.1:54321"   # Python resolves "localhost" slowly here (~15 s per call); browsers do not


def env(path: Path) -> dict:
    return {k: v.strip().strip('"') for k, v in re.findall(r"^([A-Z_]+)=(.*)$", path.read_text(encoding="utf-8"), re.M)}


crm, supa = env(HERE / ".env"), env(HERE.parent / "supabase" / ".env")
PUB = crm["VITE_SB_PUBLISHABLE_KEY"]
SERVICE = supa.get("SERVICE_ROLE_KEY") or supa["SUPABASE_SECRET_KEY"]


def call(method, path, body=None, key=PUB, token=None, prefer=None):
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None)
    req.add_header("apikey", key)
    req.add_header("Authorization", f"Bearer {token or key}")
    req.add_header("Content-Type", "application/json")
    if prefer:
        req.add_header("Prefer", prefer)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw.decode(errors="replace")[:300]


def main() -> int:
    email, password = crm["CRM_ADMIN_EMAIL"], crm["CRM_ADMIN_PASSWORD"]
    if "--check-only" not in sys.argv:
        st, body = call("POST", "/auth/v1/admin/users", {
            "email": email, "password": password, "email_confirm": True,
            "user_metadata": {"first_name": "Jon", "last_name": "Dumont"}}, key=SERVICE)
        exists = st in (400, 409, 422) and "already" in json.dumps(body).lower()
        print("create user:", st, "created" if st in (200, 201) else ("already exists" if exists else body))
        if st not in (200, 201) and not exists:
            return 1
    st, tok = call("POST", "/auth/v1/token?grant_type=password", {"email": email, "password": password})
    print("login:", st, "ok" if st == 200 else tok)
    if st != 200:
        return 1
    t = tok["access_token"]
    st, me = call("GET", "/rest/v1/sales?select=id,first_name,administrator", token=t)
    print("sales row:", st, me)
    st, made = call("POST", "/rest/v1/contacts?select=id,first_name,last_name", token=t, prefer="return=representation",
                    body={"first_name": "Test", "last_name": "Contact (delete me)", "sales_id": me[0]["id"]})
    print("create contact:", st, made)
    if st not in (200, 201):
        return 1
    cid = made[0]["id"]
    st, got = call("GET", f"/rest/v1/contacts?id=eq.{cid}&select=id", token=t)
    print("read contact:", st, got)
    st, _ = call("DELETE", f"/rest/v1/contacts?id=eq.{cid}", token=t)
    st2, gone = call("GET", f"/rest/v1/contacts?id=eq.{cid}&select=id", token=t)
    print("delete contact:", st, "| after delete:", gone)
    st, anon = call("GET", "/rest/v1/contacts?select=id&limit=1")
    print("anon (no login) reads contacts:", st, anon)
    return 0 if gone == [] else 1


if __name__ == "__main__":
    sys.exit(main())
