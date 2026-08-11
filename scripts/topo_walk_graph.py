# A robust, simple AST walker

from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions
from topo_walk_utils import print_tree
import json

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
        """Consistently extracts named tokens from ZetaSQL AST Nodes."""
        if not node:
            return ""
        if hasattr(node, "id_string") and node.id_string:
            return node.id_string
        if hasattr(node, "names") and node.names:
            return ".".join([n.id_string for n in node.names if hasattr(n, "id_string")])
        if hasattr(node, "name") and hasattr(node.name, "id_string"):
            return node.name.id_string
        # Check child paths for ASTPathExpression wrappers
        if hasattr(node, "path_expression"):
            return self._extract_name(node.path_expression)
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

# 4. Parse script using maximum features language options
sql_payload = Parser.parse_script_static("""
CREATE or replace FUNCTION funcs.function_a(inp ANY TYPE) AS ((
  SELECT (inp).(funcs.function_b)() 
));

CREATE or replace FUNCTION funcs.function_b(inp ANY TYPE) AS ((
  SELECT (inp).(funcs.function_a)()
));

CREATE OR REPLACE TABLE FUNCTION custom_namespace.analytical_hub(input TABLE<val int64>) AS (
  with init as (
    SELECT * FROM input
    |> call external_namespace.table_function()
    |> select (val).(funcs.function_b)() as new_val
    |> WHERE True
    |> SELECT 
        funcs.nested_outer( (new_val).(funcs.function_a)().(funcs.function_b)().(funcs.function_c)() ) out_val,
        array(select (v).(funcs.function_c)() from unnest(generate_array(0,5)) v) as arr
  )

  select cast(out_val as string).upper() exit_val, (arr).array_slice(0,2) new_arr from init
);
""", options=lang_opts)

# Execute visitor pass to build the graph
builder = GraphBuilder()
for statement_node in sql_payload.statement_list_node.statement_list:
    builder.visit(statement_node)

# Print out our built tree structures
for built_tree in builder.current_node["children"]:
    json_string = json.dumps(built_tree, indent=2)
    print(json_string)
    # print_tree(built_tree)
