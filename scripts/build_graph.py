import yaml

# Load your dependencies
with open('bq/app/dependencies.yaml', 'r') as f:
    data = yaml.safe_load(f)
    dependencies = data.get('dependencies', {})

# Start building the Mermaid string
mermaid_lines = ["graph LR"]  # Use LR for Left-to-Right flow

for task, deps in dependencies.items():
    # Style the task as a rounded box: taskname([taskname])
    for dep in deps:
        mermaid_lines.append(f"    {dep} --> {task}")

# Print the result
print("\n--- COPY THE CODE BELOW ---")
print("\n".join(mermaid_lines))
print("--- END ---")
