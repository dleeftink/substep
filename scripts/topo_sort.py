#!/usr/bin/env python3
"""
Topological sort for SQL function dependencies in substep/bq.
Reads SQL files, extracts function definitions and calls, builds a dependency graph, and outputs install order.
"""

#!/usr/bin/env python3
import os
import re
import yaml
import heapq
import sys
from collections import defaultdict

import re

def extract_functions_and_deps(sql_content, valid_namespaces):
    # 1. Strip comments
    sql_content = re.sub(r'--.*', '', sql_content)
    sql_content = re.sub(r'/\*.*?\*/', '', sql_content, flags=re.DOTALL)

    # 2. Extract function definition
    def_pattern = r'create\s+(?:or\s+replace\s+)?(?:table\s+)?function\s+([`\w\.]+)'
    def_match = re.search(def_pattern, sql_content, re.IGNORECASE)
    if not def_match: return None, None, set()

    current_func_original = def_match.group(1).replace('`', '')
    current_func_lower = current_func_original.lower()
    
    # 3. Strip strings
    sql_content = re.sub(r"'[^']*'", "''", sql_content)
    sql_content = re.sub(r'"[^"]*"', '""', sql_content)

    ns_regex = '|'.join(map(re.escape, valid_namespaces))
    
    # Updated chain_pattern: 
    # Matches .(ns.func)(args) where args can be empty or contain text/nested parens
    chain_pattern = r'\.\(\s*((' + ns_regex + r')\.[\w\-]+)\s*\)\(([^)]*)\)'
    
    # Extract just the function names from the chains
    chains = [m[0].lower() for m in re.findall(chain_pattern, sql_content, re.IGNORECASE)]
    
    deps_metadata = set()
    
    if chains:
        for i in range(len(chains) - 1):
            deps_metadata.add(f"INTERNAL_DEP:{chains[i+1]}->{chains[i]}(chained)")
        deps_metadata.add(f"DEP:{chains[-1]}(chained)")

    # Find standard calls (avoiding things already caught in chains)
    all_calls_pattern = r'\b(' + ns_regex + r')\.([\w\-]+)(?!\w)'
    for match in re.finditer(all_calls_pattern, sql_content, re.IGNORECASE):
        dep = f"{match.group(1)}.{match.group(2)}".lower()
        if dep != current_func_lower and dep not in chains:
            deps_metadata.add(f"DEP:{dep}")
            
    return current_func_lower, current_func_original, deps_metadata

def main(excluded_namespaces):
    bq_dir = "bq"
    if not os.path.exists(bq_dir):
        print(f"Error: {bq_dir} not found", file=sys.stderr)
        return

    namespaces = [
        d.lower() for d in os.listdir(bq_dir) 
        if os.path.isdir(os.path.join(bq_dir, d)) and d.lower() not in excluded_namespaces
    ]
    
    graph = defaultdict(set)      # callee -> set of callers
    all_defined_funcs = set()
    func_to_deps = {}             # caller -> set of callees
    func_to_path = {}
    func_to_original = {}

    func_to_deps = defaultdict(set)           # Logic graph (clean names)
    func_to_display_deps = defaultdict(set)   # For YAML output (with tags)

    # Build the graph
    for root, dirs, files in os.walk(bq_dir):
        dirs[:] = [d for d in dirs if d.lower() not in excluded_namespaces]
        for file in files:
            if file.endswith('.sql'):
                path = os.path.join(root, file)
                with open(path, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                func_lower, func_original, deps_metadata = extract_functions_and_deps(content, namespaces)
                if func_lower:
                    all_defined_funcs.add(func_lower)
                    func_to_path[func_lower] = path
                    func_to_original[func_lower] = func_original
                    
                    for item in deps_metadata:
                        if item.startswith("INTERNAL_DEP:"):
                            # Format: INTERNAL_DEP:child->parent(chained)
                            link = item.replace("INTERNAL_DEP:", "")
                            child_raw, parent_raw = link.split("->")
                            
                            child_clean = child_raw.split("(")[0]
                            func_to_deps[child_clean].add(parent_raw.split("(")[0])
                            func_to_display_deps[child_clean].add(parent_raw)
                        else:
                            # Format: DEP:name or DEP:name(chained)
                            dep_raw = item.replace("DEP:", "")
                            dep_clean = dep_raw.split("(")[0]
                            func_to_deps[func_lower].add(dep_clean)
                            func_to_display_deps[func_lower].add(dep_raw)

    # After building func_to_deps, update the global graph
    for caller, deps in func_to_deps.items():
        for dep in deps:
            graph[dep].add(caller)

    # Prepare for Topological Sort
    in_degree = {f: 0 for f in all_defined_funcs}
    clean_graph = defaultdict(set)
    
    for caller, deps in func_to_deps.items():
        for dep in deps:
            if dep in all_defined_funcs:
                clean_graph[dep].add(caller)
                in_degree[caller] += 1

    # Out-degree: How many functions depend on this one? 
    # High out-degree = "High priority" utility function.
    out_degree = {f: len(clean_graph[f]) for f in all_defined_funcs}

    # Heap contains (-out_degree, function_name)
    # Negative out_degree ensures the highest count comes off the heap first.
    queue = [(-out_degree[f], f) for f in all_defined_funcs if in_degree[f] == 0]
    heapq.heapify(queue)
    
    install_order = []
    
    # Audit log to stderr
    print("Dependency graph:", file=sys.stderr)
    for func in sorted(all_defined_funcs):
        internal_deps = sorted([d for d in func_to_deps[func] if d in all_defined_funcs])
        if internal_deps:
            dep_names = [func_to_original[d] for d in internal_deps]
            print(f"  {func_to_original[func]} depends on: {dep_names}", file=sys.stderr)
    print("", file=sys.stderr)

    while queue:
        priority, curr = heapq.heappop(queue)
        install_order.append(curr)
        
        for neighbor in clean_graph[curr]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                # Add to queue with its priority
                heapq.heappush(queue, (-out_degree[neighbor], neighbor))

    # Output paths to stdout for Bash (for now, keep for compatibility or switch to YAML reading)
    # Write dependencies.yaml
    yaml_output = {
        "install_order": [func_to_original[f] for f in install_order],
        "dependencies": {
            func_to_original[f]: sorted([
                # Use display name if defined, otherwise original name
                func_to_original.get(d.split("(")[0], d.split("(")[0]) + ("(chained)" if "(chained)" in d else "")
                for d in func_to_display_deps[f] if d.split("(")[0] in all_defined_funcs
            ])
            for f in install_order
        },
        "path_map": {func_to_original[f]: func_to_path[f] for f in install_order}
    }
    if len(install_order) == len(all_defined_funcs):
        with open("bq/app/dependencies.yaml", "w") as f:
            yaml.dump(yaml_output, f, default_flow_style=False, sort_keys=False)
    else:
        stuck = all_defined_funcs - set(install_order)
        print("\n--- ERROR: CYCLE OR MISSING DEPS ---", file=sys.stderr)
        for f in sorted(stuck):
            blocking = [d for d in func_to_deps[f] if d in all_defined_funcs and d not in install_order]
            blocking_names = [func_to_original[d] for d in blocking]
            print(f"  {func_to_original[f]} is waiting for: {blocking_names}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        excluded_namespaces = sys.argv[1].split(',')
        main(excluded_namespaces)
    else:
        main([])
