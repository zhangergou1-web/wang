#!/bin/sh
# 打包成 zip，方便在手机上直接分享/导入
cd "$(dirname "$0")" || exit 1
OUT="../CostBook-$(date +%Y%m%d).zip"
rm -f "$OUT"
# 只打源码和配置，排除构建产物与缓存
zip -rq "$OUT" . \
  -x "build/*" -x "DerivedData/*" -x "*.xcuserdatad/*" -x "*.xcworkspace/*" \
  -x ".DS_Store" -x "__pycache__/*" -x "lint_swift.py"
ls -lh "$OUT"
echo "完成：$OUT"
