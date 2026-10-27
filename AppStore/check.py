"""Checks the store text in metadata.md against App Store Connect's limits."""
import re, sys
text = open(sys.argv[1] if len(sys.argv) > 1 else "AppStore/metadata.md").read()
ok = True
for match in re.finditer(r"^### (.+?)（?\(?(\d+)\)?）?\n(.*?)(?=^### |^## |^---|\Z)", text, re.S | re.M):
    name, limit, body = match.group(1).strip(), int(match.group(2)), match.group(3).strip()
    length = len(body)
    flag = "OK " if length <= limit else "TOO LONG"
    ok &= length <= limit
    print(f"{flag} {length:>5}/{limit:<5} {name}")
sys.exit(0 if ok else 1)
