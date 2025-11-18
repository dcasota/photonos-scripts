#!/bin/bash

if [ -z "$INSTALL_DIR" ]; then
  echo "Error: Variable INSTALL_DIR is not set. This sub-script must be called by installer.sh"
  exit 1
fi

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PYTHON_SCRIPT="$SCRIPT_DIR/fetch_project_status.py"

cat > $PYTHON_SCRIPT <<'EOF_PYTHONSCRIPT'
import os
import json
import urllib.request
import urllib.error
import sys

def main():
    token = os.environ.get("GITHUB_TOKEN")
    ghusername = os.environ.get("GITHUB_USERNAME")
    if not token:
        print("\n[Project Status] Warning: GITHUB_TOKEN not set. Cannot fetch project board.")
        print("To see project status, export GITHUB_TOKEN and run this script again.")
        return

    query = """
    query {
      user(login: "%s") {
        projectV2(number: 5) {
          title
          items(first: 20) {
            nodes {
              content {
                ... on Issue {
                  title
                  state
                  number
                  url
                }
                ... on PullRequest {
                  title
                  state
                  number
                  url
                }
                ... on DraftIssue {
                  title
                  body
                }
              }
              fieldValueByName(name: "Status") {
                ... on ProjectV2ItemFieldSingleSelectValue {
                  name
                }
              }
            }
          }
        }
      }
    }
    """

    data = json.dumps({"query": query % ghusername}).encode("utf-8")
    req = urllib.request.Request(
        "https://api.github.com/graphql",
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "Factory-Droid"
        }
    )

    try:
        with urllib.request.urlopen(req) as response:
            result = json.loads(response.read())
            if "errors" in result:
                print(f"\n[Project Status] GraphQL Error: {result['errors'][0]['message']}")
                return

            project = result.get("data", {}).get("user", {}).get("projectV2")
            if not project:
                print("\n[Project Status] Project board not found or access denied.")
                return

            print(f"\n=== {project['title']} ===")
            items = project["items"]["nodes"]
            
            if not items:
                print("No items found on the board.")
                return

            # Group by status
            by_status = {}
            for item in items:
                status_node = item.get("fieldValueByName")
                status = status_node.get("name", "No Status") if status_node else "No Status"
                
                if status not in by_status:
                    by_status[status] = []
                by_status[status].append(item)

            # Print grouped items
            for status, status_items in by_status.items():
                print(f"\n[{status}]")
                for item in status_items:
                    content = item.get("content") or {}
                    title = content.get("title", "Untitled")
                    # item_type = "Draft"
                    # if "state" in content:
                    #     item_type = content["state"]
                    
                    print(f"  - {title}")
            
            print("\n==========================================\n")

    except urllib.error.HTTPError as e:
        print(f"\n[Project Status] HTTP Error: {e.code} {e.reason}")
    except Exception as e:
        print(f"\n[Project Status] Error: {e}")

if __name__ == "__main__":
    main()
EOF_PYTHONSCRIPT

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Warning: GITHUB_TOKEN is not set in the environment."
    echo "Please export GITHUB_TOKEN to view the project status board."
    exit 0
fi

if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "Error: Python script not found at $PYTHON_SCRIPT"
    exit 1
fi

# Check if python3 is available
if command -v python3 &> /dev/null; then
    python3 "$PYTHON_SCRIPT"
else
    echo "Error: python3 is not installed. Cannot fetch project status."
fi
