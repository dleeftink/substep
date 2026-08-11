def print_tree(node: dict, prefixes: list[bool] = None) -> None:
    """Recursively formats a graph dictionary into a clean CLI file tree."""
    if prefixes is None:
        prefixes = []

    # Format the current node layout
    indent = ""
    for is_last in prefixes[:-1]:
        indent += "    " if is_last else "│   "

    if prefixes:
        connector = "└── " if prefixes[-1] else "├── "
        print(f"{indent}{connector}{node['label']}")
    else:
        print(node["label"])

    # Traversal lookahead for child boundaries
    children = node["children"]
    child_count = len(children)
    
    for index, child in enumerate(children):
        is_last_child = (index == child_count - 1)
        print_tree(child, prefixes + [is_last_child])