#!/usr/bin/env python3
"""
Topological sort for SQL function dependencies in substep/bq.
Reads SQL files, extracts function definitions and calls, builds a dependency graph, and outputs install order.
"""

import os
import re
from collections import defaultdict, deque

def extract_functions_and_deps(sql_content):
    """Extract function definitions and dependencies from SQL content."""
    functions = set()
    deps = defaultdict(set)
    
    # Find function definitions: create or replace function <namespace>.<name>
    func_pattern = r'create or replace function (\w+)\.(\w+)\('
    matches = list(re.finditer(func_pattern, sql_content, re.IGNORECASE))
    if matches:
        namespace, name = matches[0].groups()  # Assume one function per file
        func_name = f"{namespace}.{name}"
        functions.add(func_name)
        
        # Find function calls: .(<namespace>.<name>) or CALL <namespace>.<name>
        call_pattern = r'\.\((\w+)\.(\w+)\)\('
        for match in re.finditer(call_pattern, sql_content, re.IGNORECASE):
            dep_namespace, dep_name = match.groups()
            dep_func = f"{dep_namespace}.{dep_name}"
            deps[func_name].add(dep_func)
    
    return functions, deps

def topological_sort(graph):
    """Perform topological sort using Kahn's algorithm."""
    in_degree = {node: 0 for node in graph}
    for node in graph:
        for dep in graph[node]:
            in_degree[dep] += 1
    
    queue = deque([node for node in in_degree if in_degree[node] == 0])
    result = []
    
    while queue:
        node = queue.popleft()
        result.append(node)
        for neighbor in graph.get(node, []):
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                queue.append(neighbor)
    
    if len(result) != len(graph):
        raise ValueError("Cycle detected in dependencies")
    
    return result

def main():
    bq_dir = "bq"
    graph = defaultdict(set)
    all_functions = set()
    
    for root, dirs, files in os.walk(bq_dir):
        for file in files:
            if file.endswith('.sql'):
                filepath = os.path.join(root, file)
                with open(filepath, 'r') as f:
                    content = f.read()
                functions, deps = extract_functions_and_deps(content)
                all_functions.update(functions)
                for func, func_deps in deps.items():
                    for dep in func_deps:
                        graph[dep].add(func)  # Reverse: dep -> func, so dep before func
    
    # Add all dependencies as nodes with no deps if not already present
    for func in list(graph.keys()):
        for dep in graph[func]:
            if dep not in graph:
                graph[dep] = set()
    
    # Add missing functions as nodes with no deps
    for func in all_functions:
        if func not in graph:
            graph[func] = set()
    
    print("Dependency graph:")
    for func, deps in sorted(graph.items()):
        if deps:
            print(f"{func}: {sorted(deps)}")
    
    try:
        order = topological_sort(graph)
        print("\nTopological order:")
        print("\n".join(order))
    except ValueError as e:
        print(f"Error: {e}")
        # Fallback: alphabetical order
        print("Fallback order:")
        print("\n".join(sorted(all_functions)))

if __name__ == "__main__":
    main()