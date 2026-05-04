import yaml

# Load your dependencies
with open('bq/app/dependencies.yaml', 'r') as f:
    data = yaml.safe_load(f)
    dependencies = data.get('dependencies', {})

# 1. Calculate degrees to identify Hubs and Leaves
all_nodes = set(dependencies.keys())
out_counts = {}  # Number of things depending on this node
in_counts = {task: len(deps) for task, deps in dependencies.items()} # Number of deps this task has

for task, deps in dependencies.items():
    all_nodes.update(deps)
    for dep in deps:
        out_counts[dep] = out_counts.get(dep, 0) + 1

# 2. Start building Mermaid string
mermaid_lines = ["graph BT"]

# 3. Define Shapes first (Mermaid uses the first definition it sees)
for node in sorted(all_nodes):
    if out_counts.get(node, 0) >= 3:
        # HUB: Double-bordered box [[node]]
        mermaid_lines.append(f"    {node}([{node}])")
    elif in_counts.get(node, 0) == 0:
        # LEAF: Stadium/Rounded shape ([node]) or Circle ((node))
        mermaid_lines.append(f"    {node}[{node}]")
    else:
        # STANDARD: Regular rounded box
        mermaid_lines.append(f"    {node}(({node}))")

# 4. Add the actual edges
for task, deps in dependencies.items():
    for dep in deps:
        mermaid_lines.append(f"    {dep} --> {task}")

print("\n--- COPY THE CODE BELOW ---")
print("\n".join(mermaid_lines))
