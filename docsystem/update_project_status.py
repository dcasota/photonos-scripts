import os
import json
import urllib.request
import urllib.error
import sys

def fetch_project_data(token, ghusername, project_number):
    # Query to get project ID and Status field ID
    query = """
    query {
      user(login: "%s") {
        projectV2(number: %d) {
          id
          title
          field(name: "Status") {
            ... on ProjectV2FieldSingleSelect {
              id
              options {
                id
                name
              }
            }
          }
          items(first: 20) {
            nodes {
              id
              content {
                ... on Issue {
                  title
                }
                ... on PullRequest {
                  title
                }
                ... on DraftIssue {
                  title
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
    """ % (ghusername, project_number)

    data = json.dumps({"query": query}).encode("utf-8")
    req = urllib.request.Request(
        "https://api.github.com/graphql",
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "Factory-Droid"
        }
    )

    with urllib.request.urlopen(req) as response:
        return json.loads(response.read())

def update_item_status(token, project_id, item_id, field_id, option_id):
    mutation = """
    mutation {
      updateProjectV2ItemFieldValue(
        input: {
          projectId: "%s"
          itemId: "%s"
          fieldId: "%s"
          value: { 
            singleSelectOptionId: "%s" 
          }
        }
      ) {
        projectV2Item {
          id
        }
      }
    }
    """ % (project_id, item_id, field_id, option_id)

    data = json.dumps({"query": mutation}).encode("utf-8")
    req = urllib.request.Request(
        "https://api.github.com/graphql",
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "Factory-Droid"
        }
    )

    with urllib.request.urlopen(req) as response:
        return json.loads(response.read())

def main():
    if len(sys.argv) < 3:
        print("Usage: update_project_status.py <Item Title Substring> <New Status>")
        print("Example: update_project_status.py 'Orphaned Weblinks' 'Done'")
        return

    target_title_substring = sys.argv[1]
    target_status_name = sys.argv[2]

    token = os.environ.get("GITHUB_TOKEN")
    ghusername = os.environ.get("GITHUB_USERNAME")
    
    if not token or not ghusername:
        print("Error: GITHUB_TOKEN or GITHUB_USERNAME not set.")
        return

    try:
        # 1. Fetch Project Data
        result = fetch_project_data(token, ghusername, 5) # Assuming project number 5 based on fetch script
        
        project_node = result.get("data", {}).get("user", {}).get("projectV2")
        if not project_node:
            print("Error: Project not found.")
            return

        project_id = project_node["id"]
        status_field = project_node["field"]
        
        if not status_field:
            print("Error: Status field not found.")
            return

        field_id = status_field["id"]
        options = status_field["options"]
        
        # 2. Find Option ID for target status
        option_id = None
        for opt in options:
            if opt["name"].lower() == target_status_name.lower():
                option_id = opt["id"]
                break
        
        if not option_id:
            print(f"Error: Status '{target_status_name}' not found. Available statuses: {[o['name'] for o in options]}")
            return

        # 3. Find Item ID
        target_item_id = None
        current_status = None
        items = project_node["items"]["nodes"]
        
        for item in items:
            content = item.get("content") or {}
            title = content.get("title", "")
            if target_title_substring.lower() in title.lower():
                target_item_id = item["id"]
                status_val = item.get("fieldValueByName")
                current_status = status_val.get("name") if status_val else "No Status"
                print(f"Found item: '{title}' (Current Status: {current_status})")
                break
        
        if not target_item_id:
            print(f"Error: Item matching '{target_title_substring}' not found.")
            return

        if current_status and current_status.lower() == target_status_name.lower():
            print(f"Item is already in '{target_status_name}'. No change needed.")
            return

        # 4. Update Item
        print(f"Moving item to '{target_status_name}'...")
        update_result = update_item_status(token, project_id, target_item_id, field_id, option_id)
        
        if "errors" in update_result:
             print(f"Error updating item: {update_result['errors']}")
        else:
             print("Successfully updated item status.")

    except urllib.error.HTTPError as e:
        print(f"HTTP Error: {e.code} {e.reason}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
