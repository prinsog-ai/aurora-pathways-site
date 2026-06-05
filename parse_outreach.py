import re, csv

with open("/Users/woedem/aurora-pathways-site/outreach_emails.md") as f:
    text = f.read()

# Extract emails
records = []
current = None

for line in text.split("\n"):
    line_stripped = line.strip()
    match = re.match(r'\*\*(\d+)\.\s+(.+?)\*\*', line_stripped)
    if match:
        if current and current.get("body"):
            records.append(current)
        current = {"num": match.group(1), "company": match.group(2), "body": "", "contact": ""}
    elif current:
        if "—" in line_stripped and line_stripped.count("(") == 0 and not line_stripped.startswith("#"):
            parts = line_stripped.split("—", 1)
            if len(parts) == 2 and not current.get("contact"):
                current["contact"] = parts[-1].strip().strip("*").strip()
        current["body"] += line + "\n"

if current and current.get("body"):
    records.append(current)

# Write CSV
with open("/Users/woedem/aurora-pathways-site/outreach_tracker.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["#", "Company", "Contact", "Status", "Email Ready", "Sent Date", "Response"])
    for r in records:
        writer.writerow([r.get("num",""), r.get("company",""), r.get("contact",""), 
                        "Draft Ready", "Yes", "", ""])

print(f"Done — {len(records)} leads in outreach_tracker.csv")
