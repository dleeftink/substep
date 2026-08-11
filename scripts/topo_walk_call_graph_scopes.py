from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions
from topo_walk_utils import print_tree

# 1. Enable pipe syntax and maximum features
lang_opts = LanguageOptions.maximum_features()

# 2. Graph builder preserving default_visit and self.descend
class GraphBuilder(ASTNodeVisitor):
    # Single source of truth mapping node types to their dependency graph roles
    NODE_MAP = {
        # Function Definitions
        "ASTCreateFunctionStatement": "definition",
        "ASTCreateTableFunctionStatement": "definition",
        "ASTFunctionDeclaration": "declaration",
        
        # SQL Scopes & Contexts (Standard, Piped, and Relational Data Sources)
        "ASTWithClause": "scope",
        "ASTAliasedQuery": "scope",
        "ASTSubquery": "scope",
        "ASTExpressionSubquery": "scope",
        "ASTPipeCall": "scope",
        "ASTPipeSelect": "scope",
        "ASTPipeWhere": "scope",
        
        # Relational Generators & Table Sources
        "ASTUnnestExpression": "scope",
        "ASTTablePathExpression": "scope",
        "ASTTableSubquery": "scope",
        "ASTJoin": "scope",
        
        # Function & Table-Valued Function (TVF) Calls
        "ASTFunctionCall": "call",
        "ASTTVF": "call",
    }

    def __init__(self):
        super().__init__()
        self.current_node = {"name": "Root", "children": []}
        self.stack = []

    def _extract_name(self, node) -> str:
        """Deeply searches the subtree for standard name/path identifiers."""
        if not node:
            return ""
        
        if hasattr(node, "id_string") and node.id_string:
            return node.id_string
        if hasattr(node, "names") and node.names:
            return ".".join([n.id_string for n in node.names if hasattr(n, "id_string")])
        if hasattr(node, "name") and isinstance(getattr(node, "name"), str):
            return node.name

        for field in ["path_expression", "function_declaration", "name", "function"]:
            if hasattr(node, field):
                name = self._extract_name(getattr(node, field))
                if name:
                    return name

        child_getter = getattr(node, "child_nodes", None) or getattr(node, "children", None)
        if child_getter:
            try:
                children = child_getter() if callable(child_getter) else child_getter
                for child in children:
                    if child.__class__.__name__ in ("ASTQuery", "ASTSelect", "ASTWithClause"):
                        continue
                    name = self._extract_name(child)
                    if name:
                        return name
            except Exception:
                pass
                
        return ""

    def _extract_scope_name(self, node) -> str:
        """Determines context and extracts descriptive semantic names for scopes."""
        node_type = node.__class__.__name__
        
        # 1. Handle CTE / Query Aliases
        if node_type == "ASTAliasedQuery" and hasattr(node, "alias") and node.alias:
            return node.alias.id_string
            
        # 2. Handle Named Pipe Blocks
        if node_type == "ASTPipeCall":
            return "|> CALL"
        if node_type == "ASTPipeSelect":
            return "|> SELECT"
        if node_type == "ASTPipeWhere":
            return "|> WHERE"
            
        # 3. Handle Relational Table Sources / Generators
        if node_type == "ASTUnnestExpression":
            return "UNNEST"
        if node_type == "ASTTablePathExpression":
            return f"FROM {self._extract_name(node)}"
        if node_type == "ASTTableSubquery":
            return "FROM (subquery)"
        if node_type == "ASTJoin":
            return "JOIN"
            
        # 4. Handle Subqueries and Anonymous Collections
        if node_type in ("ASTSubquery", "ASTExpressionSubquery"):
            return "(subquery)"
        if node_type == "ASTWithClause":
            return "WITH"
            
        return ""

    def default_visit(self, node) -> None:
        node_type = node.__class__.__name__
        
        if node_type == "ParseLocationRange":
            return

        node_category = self.NODE_MAP.get(node_type)
        pushed = False

        if node_category:
            if node_category == "scope":
                node_value = self._extract_scope_name(node)
            else:
                node_value = self._extract_name(node)
                
            display_label = f"[{node_category.upper()}] {node_type}"
            if node_value:
                display_label += f" -> '{node_value}'"
            
            new_node = {"label": display_label, "children": []}
            self.current_node["children"].append(new_node)
            
            self.stack.append(self.current_node)
            self.current_node = new_node
            pushed = True
        
        self.descend(node)
        
        if pushed:
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
    print_tree(built_tree)
