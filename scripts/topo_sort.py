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

def extract_functions_and_deps(sql_content, valid_namespaces):
    """Extract definitions and deps, stripping comments/strings for accuracy."""
    # 1. Strip comments
    sql_content = re.sub(r'--.*', '', sql_content)
    sql_content = re.sub(r'/\*.*?\*/', '', sql_content, flags=re.DOTALL)

    # 2. Extract function definition
    def_pattern = r'create\s+(?:or\s+replace\s+)?(?:table\s+)?function\s+([`\w\.]+)'
    def_match = re.search(def_pattern, sql_content, re.IGNORECASE)
    if not def_match:
        return None, None, set()

    current_func_original = def_match.group(1).replace('`', '')
    current_func_lower = current_func_original.lower()
    
    # 3. Strip strings (descriptions/options)
    sql_content = re.sub(r"'[^']*'", "''", sql_content)
    sql_content = re.sub(r'"[^"]*"', '""', sql_content)

    # 4. Match calls using the namespace whitelist
    ns_regex = '|'.join(map(re.escape, valid_namespaces))
    call_pattern = r'\b(' + ns_regex + r')\.([\w\-]+)(?!\w)'

    deps_lower = set()
    for match in re.finditer(call_pattern, sql_content, re.IGNORECASE):
        dep_func_lower = match.group(0).lower().replace('`', '')
        if dep_func_lower != current_func_lower:
            deps_lower.add(dep_func_lower)
            
    return current_func_lower, current_func_original, deps_lower

def main():
    bq_dir = "bq"
    exclude_dirs = {"app", "try"}
    if not os.path.exists(bq_dir):
        print(f"Error: {bq_dir} not found", file=sys.stderr)
        return

    namespaces = [
        d.lower() for d in os.listdir(bq_dir) 
        if os.path.isdir(os.path.join(bq_dir, d)) and d.lower() not in exclude_dirs
    ]
    
    graph = defaultdict(set)      # callee -> set of callers
    all_defined_funcs = set()
    func_to_deps = {}             # caller -> set of callees
    func_to_path = {}
    func_to_original = {}

    # Build the graph
    for root, dirs, files in os.walk(bq_dir):
        # Skip excluded directories
        dirs[:] = [d for d in dirs if d.lower() not in exclude_dirs]
        
        for file in files:
            if file.endswith('.sql'):
                path = os.path.join(root, file)
                with open(path, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                func_lower, func_original, deps_lower = extract_functions_and_deps(content, namespaces)
                if func_lower:
                    all_defined_funcs.add(func_lower)
                    func_to_deps[func_lower] = deps_lower
                    func_to_path[func_lower] = path
                    func_to_original[func_lower] = func_original
                    for dep in deps_lower:
                        graph[dep].add(func_lower)

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
            func_to_original[f]: [func_to_original[d] for d in sorted(func_to_deps[f]) if d in all_defined_funcs]
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
    main()
