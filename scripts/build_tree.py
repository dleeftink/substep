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

# 2. Separate Meta nodes from Function nodes
meta_nodes = sorted([k for k in deps_map.keys() if k.endswith('.meta')])
func_nodes = [k for k in deps_map.keys() if not k.endswith('.meta')]

# 3. Build Namespace Tree Map
# Map namespaces (cue, get, etc) to their member functions
namespace_map = {}
for meta in meta_nodes:
    ns = meta.split('.')[0]
    # Find all functions that start with "ns."
    children = [f for f in func_nodes if f.startswith(f"{ns}.")]
    namespace_map[meta] = sorted(children)

# 4. Identify True Roots for the Dependency Tree
# (Nodes that are functions and aren't dependencies of other functions)
all_func_reqs = {req for k, reqs in deps_map.items() for req in reqs if not k.endswith('.meta')}
func_roots = [f for f in func_nodes if f not in all_func_reqs]

# 5. Render Namespace Tree
print("Namespace Hierarchy")
print("───────────────────")
print_tree(meta_nodes, namespace_map)

print("\nProject Dependency Tree")
print("───────────────────────")
print_tree(func_roots, deps_map)
