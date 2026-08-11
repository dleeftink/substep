from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions

# 1. Enable pipe syntax and maximum features
lang_opts = LanguageOptions.maximum_features()

# 2. Graph builder preserving default_visit and self.descend
class GraphBuilder(ASTNodeVisitor):
    def __init__(self):
        super().__init__()
        # Points to the current parent dictionary node we are attaching children to
        self.current_node = {"name": "Root", "children": []}
        # Keep a history stack of parent nodes as we dive down the tree
        self.stack = []

    def _extract_name(self, node) -> str:
        """Consistently extracts named tokens from any node type."""
        if hasattr(node, "id_string") and node.id_string:
            return node.id_string
        
        if hasattr(node, "names") and node.names:
            return ".".join([n.id_string for n in node.names if hasattr(n, "id_string")])
        
        if hasattr(node, "name") and hasattr(node.name, "id_string"):
            return node.name.id_string

        return ""

    def default_visit(self, node) -> None:
        node_type = node.__class__.__name__
        
        # Skip the noise of location ranges completely
        if node_type == "ParseLocationRange":
            return

        # Prepare graph payload
        node_value = self._extract_name(node)
        display_label = f"{node_type} -> '{node_value}'" if node_value else node_type
        
        new_node = {"label": display_label, "children": []}
        
        # Append to our active tracking branch
        self.current_node["children"].append(new_node)
        
        # Push current state onto the stack and step inward
        self.stack.append(self.current_node)
        self.current_node = new_node
        
        # Standard visitor descent
        self.descend(node)
        
        # Pop back out to the parent level
        self.current_node = self.stack.pop()

# 3. Dedicated clean tree rendering utility
def print_file_tree(node: dict, prefixes: list[bool] = None) -> None:
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
        print_file_tree(child, prefixes + [is_last_child])

# 4. Parse script using maximum features language options
sql_payload = Parser.parse_script_static("""
with init as (
  SELECT (user_id).upper().lower(), SUM(revenue)
  FROM GAP_FILL(TABLE series, microsecond, 1000)
)
select * from init;
""", options=lang_opts)

# Execute visitor pass to build the graph
builder = GraphBuilder()
for statement_node in sql_payload.statement_list_node.statement_list:
    builder.visit(statement_node)

# Print out our built tree structures
for built_tree in builder.current_node["children"]:
    print_file_tree(built_tree)
