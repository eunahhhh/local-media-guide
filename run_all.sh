#!/bin/bash

# ================================================
# 매체사별 소재 자동 분류 + Kakao 500KB 압축
# ================================================

# 현재 사용자의 바탕화면 경로 자동 인식
WATCH_FOLDER="$HOME/Desktop/매체정리"
MEDIA_LIST=("Meta" "Google" "Kakao" "Naver" "Youtube" "TikTok" "Coupang")
KAKAO_SIZE_LIMIT=$((500 * 1024))  # 500KB

# 매체정리 폴더가 없으면 자동 생성
mkdir -p "$WATCH_FOLDER"

echo "📂 매체사별 분류 시작..."

# ① 매체사별 분류
for FILE in "$WATCH_FOLDER"/*; do
  [ -f "$FILE" ] || continue
  FILENAME=$(basename "$FILE")
  [[ "$FILENAME" == .* ]] && continue

  MOVED=false
  for MEDIA in "${MEDIA_LIST[@]}"; do
    if echo "$FILENAME" | grep -qi "$MEDIA"; then
      TARGET_DIR="$WATCH_FOLDER/$MEDIA"
      mkdir -p "$TARGET_DIR"
      mv "$FILE" "$TARGET_DIR/$FILENAME"
      echo "[$MEDIA] $FILENAME"
      MOVED=true
      break
    fi
  done

  if [ "$MOVED" = false ]; then
    mkdir -p "$WATCH_FOLDER/기타"
    mv "$FILE" "$WATCH_FOLDER/기타/$FILENAME"
    echo "[기타] $FILENAME"
  fi
done

# ② Kakao 폴더 내 파일 500KB 이하로 압축
echo ""
echo "📏 Kakao 용량 압축 시작..."

KAKAO_FOLDER="$WATCH_FOLDER/Kakao"

for FILE in "$KAKAO_FOLDER"/*; do
  [ -f "$FILE" ] || continue
  FILENAME=$(basename "$FILE")
  [[ "$FILENAME" == .* ]] && continue

  # 이미지 파일만 처리
  case "${FILENAME##*.}" in
    jpg|jpeg|JPG|JPEG) FORMAT="jpeg" ;;
    png|PNG) FORMAT="png" ;;
    *) continue ;;
  esac

  FILESIZE=$(stat -f%z "$FILE")

  if [ "$FILESIZE" -gt "$KAKAO_SIZE_LIMIT" ]; then
    echo "압축 중: $FILENAME ($(echo "$FILESIZE/1024" | bc)KB)"

    QUALITY=85
    while [ "$FILESIZE" -gt "$KAKAO_SIZE_LIMIT" ] && [ "$QUALITY" -gt 10 ]; do
      sips -s format $FORMAT -s formatOptions $QUALITY "$FILE" --out "$FILE" &>/dev/null
      FILESIZE=$(stat -f%z "$FILE")
      QUALITY=$((QUALITY - 10))
    done

    echo "✅ 압축 완료: $FILENAME ($(echo "$FILESIZE/1024" | bc)KB)"
  else
    echo "✅ 용량 적합: $FILENAME ($(echo "$FILESIZE/1024" | bc)KB)"
  fi
done

echo ""
echo "✅ 모든 작업 완료!"
