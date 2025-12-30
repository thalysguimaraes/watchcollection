#!/bin/bash
set -e

BUCKET_NAME="watchcollection-images"

echo "Creating R2 bucket: $BUCKET_NAME"
wrangler r2 bucket create $BUCKET_NAME 2>/dev/null || echo "Bucket may already exist"

echo ""
echo "Bucket created! Now you need to enable public access:"
echo "1. Go to https://dash.cloudflare.com/ → R2 → $BUCKET_NAME"
echo "2. Click 'Settings' tab"
echo "3. Under 'Public access', click 'Allow Access'"
echo "4. Copy the public URL (e.g., https://pub-xxx.r2.dev)"
echo ""
echo "Then set the environment variable:"
echo "export R2_PUBLIC_URL='https://pub-xxx.r2.dev'"
echo ""
echo "And run the image download script:"
echo "python -m watchcollection_crawler.pipelines.images --brand-slug rolex"
