#!/usr/bin/env bash
set -euo pipefail

# Extract GHCR image references used by all OpenAMI charts into a file.
# Output format (one per line):
#   ghcr.io/devthefuture-org/containers/<name>:<tag>
#
# Usage:
#   charts/scripts/extract-images.sh > containers/images.txt
# or:
#   charts/scripts/extract-images.sh -o containers/images.txt

CHARTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/openami"
OUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      OUT_FILE="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# 1) Parse image triples from values.yaml (registry/repository/tag)
#    Works for nested image objects since awk tokenizes by whitespace and key is first token.
find "${CHARTS_DIR}" -type f -name "values.yaml" -print0 \
| xargs -0 -I{} awk '
  $1=="repository:" { repo=$2; gsub(/"/,"",repo) }
  $1=="registry:"   { reg=$2; gsub(/"/,"",reg)  }
  $1=="tag:"        {
                      tag=$2; gsub(/"/,"",tag);
                      if (repo!="") {
                        regv=(reg!=""?reg:"ghcr.io");
                        printf "%s/%s:%s\n", regv, repo, tag;
                        repo=""; tag="";
                      }
                    }
' "{}" >> "$tmp"

# 2) Parse annotations.images entries in Chart.yaml (lines like: "image: ghcr.io/...")
#    These are authoritative references Bitnami provide for the chart.
grep -RohE "^[[:space:]]*image:[[:space:]]*\S+" "${CHARTS_DIR}"/*/Chart.yaml 2>/dev/null \
  | sed -E "s/^[[:space:]]*image:[[:space:]]*//" \
  | sed -E "s/[[:space:]]+$//" >> "$tmp" || true

# Normalize, keep only GHCR references for our namespace, unique
awk '/^ghcr\.io\/devthefuture-org\/containers\/.+:.+/{print}' "$tmp" \
  | sort -u \
  | if [[ -n "${OUT_FILE}" ]]; then tee "${OUT_FILE}"; else cat; fi
