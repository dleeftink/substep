import yaml

def print_tree(nodes, deps_map, prefix="", is_last=True):
    for i, node in enumerate(nodes):
        is_item_last = i == len(nodes) - 1
        marker = "└─ " if is_item_last else "├─ "
        print(f"{prefix}{marker}{node}")

        if node in deps_map:
            new_prefix = prefix + ("    " if is_item_last else "│   ")
            print_tree(deps_map[node], deps_map, new_prefix)

# 1. Load Data
with open('bq/app/dependencies.yaml', 'r') as f:
    data = yaml.safe_load(f)
    deps_map = data.get('dependencies', {})

# 2. Identify Meta vs Function nodes
meta_nodes = sorted([k for k in deps_map.keys() if k.endswith('.meta')])
func_nodes = [k for k in deps_map.keys() if not k.endswith('.meta')]

# 3. Calculate Roots (Functions that aren't dependencies of anything else)
all_dependencies = {dep for deps in deps_map.values() for dep in deps}
func_roots = sorted([n for n in func_nodes if n not in all_dependencies])

# 4. Render Namespace Hierarchy
print("Namespace Hierarchy")
print("─" * 19)
namespace_map = {}
for meta in meta_nodes:
    ns_prefix = meta.split('.')[0] + "."
    namespace_map[meta] = sorted([f for f in func_nodes if f.startswith(ns_prefix)])

print_tree(meta_nodes, namespace_map)

# 5. Render Individual Call Graphs for each Root
for root in func_roots:
    print(f"\n\nCALL GRAPH: {root}")
    print("─" * (12 + len(root)))
    print_tree([root], deps_map)
