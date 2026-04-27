#!/usr/bin/env python3
"""
Topological sort for SQL function dependencies in substep/bq.
Reads SQL files, extracts function definitions and calls, builds a dependency graph, and outputs install order.
"""

#!/usr/bin/env python3
import os
import re
import heapq
from collections import defaultdict

def extract_functions_and_deps(sql_content, valid_namespaces):
    # 1. Strip comments
    sql_content = re.sub(r'--.*', '', sql_content)
    sql_content = re.sub(r'/\*.*?\*/', '', sql_content, flags=re.DOTALL)

    # 2. Extract function definition
    def_pattern = r'create\s+(?:or\s+replace\s+)?(?:table\s+)?function\s+([`\w\.]+)'
    def_match = re.search(def_pattern, sql_content, re.IGNORECASE)
    
    if not def_match:
        return None, set()

    current_func = def_match.group(1).lower().replace('`', '')
    
    # 3. Strip strings to avoid dependencies inside descriptions/URLs
    sql_content = re.sub(r"'[^']*'", "''", sql_content)
    sql_content = re.sub(r'"[^"]*"', '""', sql_content)

    # 4. Match calls using the namespace whitelist (e.g. cue., get., use.)
    ns_regex = '|'.join(map(re.escape, valid_namespaces))
    call_pattern = r'\b(' + ns_regex + r')\.([\w\-]+)(?!\w)'

    deps = set()
    for match in re.finditer(call_pattern, sql_content, re.IGNORECASE):
        dep_func = match.group(0).lower().replace('`', '')
        if dep_func != current_func:
            deps.add(dep_func)
            
    return current_func, deps

def main():
    bq_dir = "bq"
    if not os.path.exists(bq_dir):
        return

    # Whitelist namespaces based on top-level folders
    namespaces = [d.lower() for d in os.listdir(bq_dir) if os.path.isdir(os.path.join(bq_dir, d))]
    
    graph = defaultdict(set)
    all_defined_funcs = set()
    func_to_deps = {}
    func_to_path = {}

    for root, _, files in os.walk(bq_dir):
        for file in files:
            if file.endswith('.sql'):
                path = os.path.join(root, file)
                with open(path, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                func, deps = extract_functions_and_deps(content, namespaces)
                if func:
                    all_defined_funcs.add(func)
                    func_to_deps[func] = deps
                    func_to_path[func] = path
                    for dep in deps:
                        graph[dep].add(func)

    # Topological Sort (Kahn's Algorithm)
    in_degree = {f: 0 for f in all_defined_funcs}
    clean_graph = defaultdict(set)
    for caller, deps in func_to_deps.items():
        for dep in deps:
            if dep in all_defined_funcs:
                clean_graph[dep].add(caller)
                in_degree[caller] += 1

    # Alphabetical tie-breaking via heap
    queue = [f for f in all_defined_funcs if in_degree[f] == 0]
    heapq.heapify(queue)
    
    install_order = []
    while queue:
        curr = heapq.heappop(queue)
        install_order.append(curr)
        for neighbor in clean_graph[curr]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                heapq.heappush(queue, neighbor)

    # Output paths to stdout for Bash
    if len(install_order) == len(all_defined_funcs):
        for func in install_order:
            print(func_to_path[func])
    else:
        # Error to stderr so it doesn't pollute the file list
        import sys
        stuck = all_defined_funcs - set(install_order)
        print("--- UNRESOLVED DEPENDENCIES ---", file=sys.stderr)
        for f in sorted(stuck):
            blocking = [d for d in func_to_deps[f] if d in all_defined_funcs and d not in install_order]
            print(f"{f} is waiting for: {blocking}", file=sys.stderr)

if __name__ == "__main__":
    main()
