#!/bin/bash
# Aurora Pathways deploy script
# Always deploy from repo root to catch ALL files
set -e

cd /Users/woedem/aurora-pathways-site

echo "Deploying from repo root..."
~/.hermes/node/bin/npx vercel --prod --yes

echo ""
echo "Verifying key pages..."
for url in "/" "/landing/tasklync/" "/landing/pledgly/" "/landing/forekast/" "/landing/ridep2p/" "/portfolio/real-estate.html" "/sales-demos.html" "/test-count.json"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "https://aurorapathways.xyz$url")
  if [ "$code" != "200" ]; then
    echo "FAIL: $url returned $code"
    exit 1
  fi
  echo "OK: $url"
done

echo ""
echo "Deploy complete. All pages verified."
