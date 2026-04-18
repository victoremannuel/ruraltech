#!/usr/bin/env python3
"""Força binding_ready=true na coleira e dispara edge function auto-sync-area-fence."""
import json, os, sys
try:
    import httpx
except ImportError:
    print("pip install httpx", file=sys.stderr); sys.exit(1)

URL = "https://nhoewnfuyjbtpklrotbf.supabase.co"
KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5ob2V3bmZ1eWpidHBrbHJvdGJmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTE3MTk3MywiZXhwIjoyMDkwNzQ3OTczfQ.uQixcWFTH_eSrG-PJEQ7ali3phfGb6Cy-8dkcDnQiO4"
COLLAR_ID = "3222380545"
AREA_ID   = "kQSjWOVdkqTNDM9WBggT"
PROP_ID   = "T0xeG8WQHwJRI6H3t7vr"

h = {
    "apikey": KEY,
    "Authorization": f"Bearer {KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=representation",
}

# 1. Forçar binding na coleira
print("[patch] Forçando binding_ready=true na coleira...")
r = httpx.patch(
    f"{URL}/rest/v1/collars",
    headers=h, timeout=10,
    params={"id": f"eq.{COLLAR_ID}"},
    json={"binding_ready": True, "supports_scoped_lora": True, "property_scope_id": "9FFFC95AA1624895"},
)
print(f"  → {r.status_code}: {r.text[:200]}")
if not r.is_success:
    sys.exit(1)

# 2. Confirmar
r2 = httpx.get(f"{URL}/rest/v1/collars", headers=h, timeout=10,
               params={"select": "id,binding_ready,supports_scoped_lora,property_scope_id", "id": f"eq.{COLLAR_ID}"})
collar = r2.json()[0] if r2.json() else {}
print(f"  collar state: binding_ready={collar.get('binding_ready')} supports_scoped_lora={collar.get('supports_scoped_lora')}")

# 3. Buscar perimeter atual da área
r3 = httpx.get(f"{URL}/rest/v1/areas", headers=h, timeout=10,
               params={"select": "id,property_id,perimeter,linked_device_ids", "id": f"eq.{AREA_ID}"})
area = r3.json()[0]
print(f"  área: {area['id']} perimeter_points={len(area['perimeter'])} devices={area['linked_device_ids']}")

# 4. Chamar edge function diretamente com payload de UPDATE simulado
print("\n[edge] Chamando auto-sync-area-fence diretamente...")
old_perim = area["perimeter"]
new_perim = list(area["perimeter"])
# Desloca vértice 0 ~1m norte para forçar mudança
p0 = new_perim[0]
if isinstance(p0, dict):
    new_perim[0] = {"lat": p0["lat"] + 0.000010, "lon": p0["lon"]}
else:
    new_perim[0] = [p0[0] + 0.000010, p0[1]]

# Primeiro aplica o delta no banco
print("[patch] Aplicando delta no perimeter da área...")
rp = httpx.patch(
    f"{URL}/rest/v1/areas",
    headers=h, timeout=10,
    params={"id": f"eq.{AREA_ID}"},
    json={"perimeter": new_perim},
)
print(f"  → {rp.status_code}")
if not rp.is_success:
    print(f"  ERRO: {rp.text[:300]}")
    sys.exit(1)

# Chama a edge function com o payload webhook
edge_payload = {
    "type": "UPDATE",
    "table": "areas",
    "record": {
        "id": AREA_ID,
        "property_id": PROP_ID,
        "perimeter": new_perim,
        "linked_device_ids": area["linked_device_ids"],
    },
    "old_record": {
        "id": AREA_ID,
        "property_id": PROP_ID,
        "perimeter": old_perim,
        "linked_device_ids": area["linked_device_ids"],
    },
}

ef_headers = {
    "Content-Type": "application/json",
    "Authorization": f"Bearer {KEY}",
}
ref = httpx.post(
    f"{URL}/functions/v1/auto-sync-area-fence",
    headers=ef_headers, timeout=15,
    json=edge_payload,
)
print(f"  edge function → {ref.status_code}: {ref.text[:500]}")

# 5. Verificar se command foi criado
import time
time.sleep(2)
rc = httpx.get(f"{URL}/rest/v1/property_commands", headers=h, timeout=10,
               params={"select": "command_id,command,status,origin_doc_type,origin_doc_id,created_at",
                       "origin_doc_id": f"eq.{AREA_ID}", "origin_doc_type": "eq.area",
                       "order": "created_at.desc", "limit": "3"})
cmds = rc.json()
print(f"\n[check] property_commands para areaId={AREA_ID}:")
for c in cmds:
    print(f"  {c}")

if cmds:
    print(f"\n[OK] commandId={cmds[0]['command_id']}")
    with open("/tmp/e2e_command_id.txt", "w") as f:
        f.write(cmds[0]["command_id"])
else:
    print("\n[AVISO] Nenhum SET_FENCE criado ainda.")
