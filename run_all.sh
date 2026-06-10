#!/bin/bash

# ================================================
# 매체사별 소재 자동 분류 + 용량 압축
# 설정은 config.txt에서만 수정하세요!
# ================================================

WATCH_FOLDER="$HOME/Desktop/매체정리"
CONFIG_FILE="$WATCH_FOLDER/_설정/config.txt"

# config.txt 존재 확인
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ config.txt 파일이 없어요. 매체정리/_설정 폴더 안에 config.txt를 넣어주세요."
  exit 1
fi

# 파일이 완전히 복사될 때까지 대기
sleep 2

# ── config.txt 파싱 ──────────────────────────────

# ① 담당 매체 목록 읽기
MEDIA_LINE=$(grep "^MEDIA=" "$CONFIG_FILE" | head -1 | sed 's/^MEDIA=//' | tr -d '\r' | xargs)
IFS=',' read -ra MEDIA_LIST_RAW <<< "$MEDIA_LINE"

MEDIA_LIST=()
for MEDIA in "${MEDIA_LIST_RAW[@]}"; do
  TRIMMED=$(echo "$MEDIA" | tr -d '\r' | xargs)
  [ -n "$TRIMMED" ] && MEDIA_LIST+=("$TRIMMED")
done

# ── 헬퍼 함수: config.txt에서 직접 조회 ──────────

# 매체 전체 용량 제한 조회 (매체명:용량KB 형식)
get_media_limit() {
  local MEDIA="$1"
  grep -v "^#" "$CONFIG_FILE" | grep -v "^MEDIA=" | grep -v "^$" | while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r' | xargs)
    col_count=$(echo "$line" | tr -cd ':' | wc -c)
    if [ "$col_count" -eq 1 ]; then
      MNAME=$(echo "$line" | cut -d: -f1 | tr -d '\r' | xargs)
      if [ "$MNAME" = "$MEDIA" ]; then
        echo "$line" | cut -d: -f2 | tr -d '\r' | xargs
        return
      fi
    fi
  done
}

# 사이즈별 용량 제한 조회 (매체명:사이즈:용량KB 형식)
get_size_limit() {
  local MEDIA="$1"
  local FILENAME_NFC="$2"
  grep -v "^#" "$CONFIG_FILE" | grep -v "^MEDIA=" | grep -v "^$" | while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r' | xargs)
    col_count=$(echo "$line" | tr -cd ':' | wc -c)
    if [ "$col_count" -eq 2 ]; then
      MNAME=$(echo "$line" | cut -d: -f1 | tr -d '\r' | xargs)
      SIZE_KEY=$(echo "$line" | cut -d: -f2 | tr -d '\r' | xargs)
      LIMIT_KB=$(echo "$line" | cut -d: -f3 | tr -d '\r' | xargs)
      if [ "$MNAME" = "$MEDIA" ] && echo "$FILENAME_NFC" | grep -qiF "$SIZE_KEY"; then
        echo "$LIMIT_KB"
        return
      fi
    fi
  done
}

# 매체에 용량 설정이 있는지 확인
has_any_limit() {
  local MEDIA="$1"
  grep -v "^#" "$CONFIG_FILE" | grep -v "^MEDIA=" | grep -v "^$" | while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r' | xargs)
    [ -z "$line" ] && continue
    MNAME=$(echo "$line" | cut -d: -f1 | tr -d '\r' | xargs)
    if [ "$MNAME" = "$MEDIA" ]; then
      echo "yes"
      return
    fi
  done
}

# ── 압축 함수 ────────────────────────────────────
compress_file() {
  local FILE="$1"
  local LIMIT_KB="$2"
  local LABEL="$3"
  local FILENAME
  FILENAME=$(basename "$FILE")

  case "${FILENAME##*.}" in
    jpg|jpeg|JPG|JPEG) FORMAT="jpeg" ;;
    png|PNG) FORMAT="png" ;;
    *) return ;;
  esac

  local SIZE_LIMIT=$((LIMIT_KB * 1024))
  local FILESIZE
  FILESIZE=$(stat -f%z "$FILE")

  if [ "$FILESIZE" -gt "$SIZE_LIMIT" ]; then
    echo "압축 중: $FILENAME [$LABEL → ${LIMIT_KB}KB 이하]"
    local QUALITY=85
    while [ "$FILESIZE" -gt "$SIZE_LIMIT" ] && [ "$QUALITY" -gt 10 ]; do
      sips -s format $FORMAT -s formatOptions $QUALITY "$FILE" --out "$FILE" &>/dev/null
      FILESIZE=$(stat -f%z "$FILE")
      QUALITY=$((QUALITY - 10))
    done
    echo "✅ 압축 완료: $FILENAME ($(echo "$FILESIZE/1024" | bc)KB)"
  else
    echo "✅ 용량 적합: $FILENAME ($(echo "$FILESIZE/1024" | bc)KB)"
  fi
}

# ── ① 매체사별 분류 ──────────────────────────────
mkdir -p "$WATCH_FOLDER"
echo "📂 매체사별 분류 시작..."

for FILE in "$WATCH_FOLDER"/*; do
  [ -f "$FILE" ] || continue
  FILENAME=$(basename "$FILE")
  [[ "$FILENAME" == .* ]] && continue
  [[ "$FILENAME" == "config.txt" ]] && continue
  [[ "$FILENAME" == "run_all.sh" ]] && continue

  FILENAME_NFC=$(echo "$FILENAME" | iconv -f UTF-8-MAC -t UTF-8)

  MOVED=false
  for MEDIA in "${MEDIA_LIST[@]}"; do
    MEDIA_NFC=$(echo "$MEDIA" | iconv -f UTF-8-MAC -t UTF-8 2>/dev/null || echo "$MEDIA")
    if echo "$FILENAME_NFC" | grep -qiF "$MEDIA_NFC"; then
      TARGET_DIR="$WATCH_FOLDER/$MEDIA"
      mkdir -p "$TARGET_DIR"
      mv "$FILE" "$TARGET_DIR/$FILENAME"
      echo "[$MEDIA] $FILENAME"
      MOVED=true
      break
    fi
  done

  if [ "$MOVED" = false ]; then
    echo "[미분류] $FILENAME — 매체명이 파일명에 없어요"
  fi
done

# ── ② 매체별 용량 압축 ───────────────────────────
echo ""
echo "📏 용량 압축 시작..."

for MEDIA in "${MEDIA_LIST[@]}"; do
  MEDIA_FOLDER="$WATCH_FOLDER/$MEDIA"
  [ -d "$MEDIA_FOLDER" ] || continue

  # 해당 매체에 용량 설정이 있는지 확인
  HAS_LIMIT=$(has_any_limit "$MEDIA")
  [ -z "$HAS_LIMIT" ] && continue

  echo ""
  echo "▶ $MEDIA 폴더 압축 중..."

  for FILE in "$MEDIA_FOLDER"/*; do
    [ -f "$FILE" ] || continue
    FILENAME=$(basename "$FILE")
    [[ "$FILENAME" == .* ]] && continue

    FILENAME_NFC=$(echo "$FILENAME" | iconv -f UTF-8-MAC -t UTF-8)

    # 사이즈별 제한 먼저 확인
    SIZE_LIMIT_KB=$(get_size_limit "$MEDIA" "$FILENAME_NFC")

    if [ -n "$SIZE_LIMIT_KB" ]; then
      compress_file "$FILE" "$SIZE_LIMIT_KB" "사이즈 기준"
    else
      # 전체 용량 제한 확인
      MEDIA_LIMIT_KB=$(get_media_limit "$MEDIA")
      if [ -n "$MEDIA_LIMIT_KB" ]; then
        compress_file "$FILE" "$MEDIA_LIMIT_KB" "전체 기준"
      else
        echo "⏭️  용량 설정 없음 (건너뜀): $FILENAME"
      fi
    fi
  done
done

echo ""
echo "✅ 모든 작업 완료!"
