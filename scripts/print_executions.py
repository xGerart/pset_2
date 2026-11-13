import json, sys
for e in json.load(sys.stdin).get("results", []):
    s = e["state"]
    print(f'{e["flowId"]:<12} {s["current"]:<10} {s["startDate"][:19]}  {e["id"]}')
