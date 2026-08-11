from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions

# 1. Enable pipe syntax and maximum features
lang_opts = LanguageOptions.maximum_features()

# 2. Prints named nodes consistently by collecting child identifiers
class Walker(ASTNodeVisitor):
    def __init__(self):
        super().__init__()
        self.depth = 0

    def _extract_name(self, node) -> str:
        """Consistently extracts named tokens from any node type."""
        # Direct check for isolated identifiers
        if hasattr(node, "id_string") and node.id_string:
            return node.id_string
        
        # Check for path expressions that bundle a sequence of names
        if hasattr(node, "names") and node.names:
            return ".".join([n.id_string for n in node.names if hasattr(n, "id_string")])
        
        # Fallback for function entries or definitions that expose a name property
        if hasattr(node, "name") and hasattr(node.name, "id_string"):
            return node.name.id_string

        return ""

    def default_visit(self, node) -> None:
        node_type = node.__class__.__name__
        
        # Skip printing the noise of location ranges to keep the graph clean
        if node_type == "ParseLocationRange":
            return

        # Fetch the name string if this node contains one
        node_value = self._extract_name(node)
        suffix = f" -> '{node_value}'" if node_value else ""

        # Format graph indentation nodes visually using tree connectors
        if self.depth == 0:
            print(f"└── {node_type}{suffix}")
        else:
            indent = "    " * (self.depth - 1)
            print(f"{indent}├── {node_type}{suffix}")
        
        # Descend deeper while managing indent levels
        self.depth += 1
        self.descend(node)
        self.depth -= 1


# 3. Parse script using maximum features language options
sql_payload = Parser.parse_script_static("""
with init as (
  SELECT (user_id).upper().lower(), SUM(revenue)
  FROM GAP_FILL(TABLE series, microsecond, 1000)
)
select * from init;

with next as (
  FROM GAP_FILL(TABLE series, microsecond, 1000)
  |> SELECT (user_id).upper().lower(), SUM(revenue)
)
select * from next;

CREATE or replace FUNCTION funcs.function_a(inp ANY TYPE) AS ((
  SELECT inp 
));

CREATE or replace FUNCTION funcs.function_b(inp ANY TYPE) AS ((
  SELECT (inp).(funcs.function_a)()
));

CREATE OR REPLACE TABLE FUNCTION custom_namespace.analytical_hub(input TABLE<val int64>) AS (
  SELECT * FROM input
  |> call external_namespace.table_function() 
  |> select (val).(funcs.function_b)() as new_val
  |> WHERE True
  |> SELECT (new_val).function_a()
);
""", options=lang_opts)

# Visit and execute
visitor = Walker()

for statement_node in sql_payload.statement_list_node.statement_list:
    visitor.visit(statement_node)
