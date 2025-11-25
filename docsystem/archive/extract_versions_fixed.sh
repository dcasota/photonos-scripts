#!/bin/bash
# Extract last 3 versions of each installer script from git
# Must be run from /root/photonos-scripts (parent directory)

cd /root/photonos-scripts

SCRIPTS=(
  "docsystem/installer.sh"
  "docsystem/installer-consolebackend.sh"
  "docsystem/installer-ghinterconnection.sh"
  "docsystem/installer-searchbackend.sh"
  "docsystem/installer-sitebuild.sh"
  "docsystem/installer-weblinkfixes.sh"
)

OUTPUT_DIR="docsystem/archive/versions"
mkdir -p "$OUTPUT_DIR"

for script in "${SCRIPTS[@]}"; do
  script_name=$(basename "$script")
  echo "Processing $script_name..."
  
  # Get last 3 commit hashes for this script
  commits=($(git log --format="%h" --follow "$script" | head -3))
  
  if [ ${#commits[@]} -eq 0 ]; then
    echo "  ⚠ No commits found for $script_name"
    continue
  fi
  
  # Extract each version
  for i in "${!commits[@]}"; do
    commit="${commits[$i]}"
    version=$((i+1))
    output="$OUTPUT_DIR/${script_name%.sh}_v${version}_commit${commit}.sh"
    
    git show "${commit}:${script}" > "$output" 2>/dev/null
    
    if [ $? -eq 0 ] && [ -s "$output" ]; then
      chmod +x "$output"
      lines=$(wc -l < "$output")
      echo "  ✓ Extracted v${version} (commit ${commit}, ${lines} lines)"
    else
      rm -f "$output"
      echo "  ✗ Failed to extract v${version} (commit ${commit})"
    fi
  done
done

echo ""
echo "==============================================="
echo "Extraction complete. Archived files:"
echo "==============================================="
ls -lh "$OUTPUT_DIR/" | grep -v "^total" | awk '{print $9, "("$5")"}'
echo "==============================================="
echo "Total files: $(ls -1 "$OUTPUT_DIR/" | wc -l)"
