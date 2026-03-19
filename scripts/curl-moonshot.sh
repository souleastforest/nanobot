#!/bin/bash
# Test Kimi Coding Plan API (Anthropic-compatible endpoint)

# Set your API key here
API_KEY="${ANTHROPIC_API_KEY:-sk-kimi-wPKtrKa4YePd1VpRjnQh4Mha92NWMUCHinxR3OXo6V7OUE1Som1pdE3VPO6ZdxTX}"
API_BASE="${ANTHROPIC_API_BASE:-https://api.kimi.com/coding}"

echo "=== Testing Kimi Coding Plan API ==="
echo "API_BASE: $API_BASE"
echo ""

# Test 1: With model "kimi-for-coding"
echo "=== Test 1: model=kimi-for-coding ==="
curl -s -X POST "${API_BASE}/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "kimi-for-coding",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "hello"}]
  }' | head -200

echo ""
echo ""

# Test 2: With model "kimi-k2-0905-preview"
echo "=== Test 2: model=kimi-k2-0905-preview ==="
curl -s -X POST "${API_BASE}/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "kimi-k2-0905-preview",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "hello"}]
  }' | head -200

echo ""
echo ""

# Test 3: Without anthropic-version header
echo "=== Test 3: Without anthropic-version header ==="
curl -s -X POST "${API_BASE}/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d '{
    "model": "kimi-for-coding",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "hello"}]
  }' | head -200

echo ""
echo ""

# Test 4: Try Moonshot official endpoint instead
echo "=== Test 4: Moonshot official endpoint (api.moonshot.cn) ==="
curl -s -X POST "https://api.moonshot.cn/anthropic/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "kimi-k2-0905-preview",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "hello"}]
  }' | head -200

echo ""
echo "Done."
