#!/bin/zsh

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"

required_files=(
  LICENSE
  README.md
  SECURITY.md
  THIRD_PARTY_NOTICES.md
  docs/PRIVACY.md
  docs/SECURITY.md
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "$required_file" ]]; then
    print -u2 "Missing required public file: $required_file"
    exit 1
  fi
done

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  candidate_files=("${(@f)$(git ls-files --cached --others --exclude-standard)}")
  publishable_files=()
  for file_path in "${candidate_files[@]}"; do
    case "$file_path" in
      .git/*|.build/*|build/*|DerivedData/*|BackupArtifacts/*|.swiftpm/*|*/.build/*|*/build/*|*/DerivedData/*|*/.swiftpm/*|*/xcuserdata/*|.DS_Store|Config/Local.xcconfig|Config/*.local.xcconfig)
        ;;
      *)
        publishable_files+=("$file_path")
        ;;
    esac
  done
else
  publishable_files=("${(@f)$(find . -type f \
    ! -path './.git/*' \
    ! -path '*/.build/*' \
    ! -path '*/build/*' \
    ! -path '*/DerivedData/*' \
    ! -path './BackupArtifacts/*' \
    ! -path '*/.swiftpm/*' \
    ! -path '*/xcuserdata/*' \
    ! -name '.DS_Store' \
    ! -name 'Local.xcconfig' \
    -print | sed 's#^\./##')}")
fi

if (( ${#publishable_files[@]} == 0 )); then
  print -u2 "No publishable files found."
  exit 1
fi

for file_path in "${publishable_files[@]}"; do
  case "$file_path" in
    BackupArtifacts/*|*client_secret*.json|*GoogleService-Info.plist|*.p12|*.pem|*.key|*.cer|*.mobileprovision|*.provisionprofile|*.sqlite|*.sqlite-shm|*.sqlite-wal|*.store|*.log|Config/Local.xcconfig|Config/*.local.xcconfig)
      print -u2 "Forbidden publishable file: $file_path"
      exit 1
      ;;
  esac
done

scan() {
  local description="$1"
  local expression="$2"
  shift 2

  if rg --hidden --no-messages --pcre2 -n "$expression" "$@" -- "${publishable_files[@]}"; then
    print -u2 "Public-source audit failed: $description"
    exit 1
  fi
}

scan "private key material" 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY'
scan "Google API key" 'AIza[0-9A-Za-z_-]{30,}'
scan "Google OAuth client secret" 'GOCSPX-[0-9A-Za-z_-]{20,}'
scan "Google OAuth client ID" '[0-9]{10,}-[0-9A-Za-z_-]{10,}\.apps\.googleusercontent\.com'
scan "GitHub access token" '(ghp|gho|ghu|ghs|ghr)_[0-9A-Za-z]{30,}|github_pat_[0-9A-Za-z_]{40,}'
scan "personal email provider address" '[0-9A-Za-z._%+-]+@(gmail|icloud|outlook|hotmail|yahoo)\.[A-Za-z]{2,}'
scan "private macOS home path" '"/Users/[0-9A-Za-z._-]+/'

print "Public-source audit passed for ${#publishable_files[@]} files."
