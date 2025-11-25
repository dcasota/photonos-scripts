#!/bin/bash
# Extract last 3 versions of each installer script from git

SCRIPTS=(
  "installer-consolebackend.sh"
  "installer-ghinterconnection.sh"
  "installer-searchbackend.sh"
  "installer-sitebuild.sh"
  "installer-weblinkfixes.sh"
)

for script in "${SCRIPTS[@]}"; do
  echo "Processing $script..."
  
  # Get last 3 commit hashes for this script
  commits=($(git log --format="%h" --follow "$script" | head -3))
  
  # Extract each version
  for i in "${!commits[@]}"; do
    commit="${commits[$i]}"
    version=$((i+1))
    output="archive/versions/${script%.sh}_v${version}_commit${commit}.sh"
    
    git show "${commit}:${script}" > "$output" 2>/dev/null
    
    if [ $? -eq 0 ]; then
      chmod +x "$output"
      echo "  ✓ Extracted v${version} (commit ${commit})"
    else
      echo "  ✗ Failed to extract v${version} (commit ${commit})"
    fi
  done
done

echo ""
echo "Extraction complete. Archived files:"
ls -lh archive/versions/ | tail -n +2
