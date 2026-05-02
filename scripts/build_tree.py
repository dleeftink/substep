import yaml

def print_tree(nodes, deps_map, prefix="", is_last=True, seen=None):
    if seen is None:
        seen = set()

    for i, node in enumerate(nodes):
        is_item_last = i == len(nodes) - 1
        
        # Branching characters
        marker = "└─ " if is_item_last else "├─ "
        print(f"{prefix}{marker}{node}")

        # Recurse into dependencies
        if node in deps_map:
            # Optional: handle circular deps or just show duplication
            new_prefix = prefix + ("    " if is_item_last else "│   ")
            print_tree(deps_map[node], deps_map, new_prefix, is_item_last, seen)

# 1. Load Data
with open('bq/app/dependencies.yaml', 'r') as f:
    data = yaml.safe_load(f)
    deps_map = data.get('dependencies', {})

# 2. Identify "Top Level" goals (nodes nothing else depends on)
all_reqs = {req for reqs in deps_map.values() for req in reqs}
roots = [task for task in deps_map.keys() if task not in all_reqs]

# 3. Render
print("Project Dependency Tree")
print("───────────────────────")
print_tree(roots, deps_map)
