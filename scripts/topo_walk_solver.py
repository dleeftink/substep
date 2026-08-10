from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions

# Enable pipe syntax and maximum features
lang_opts = LanguageOptions.maximum_features()

class DependencyResolverVisitor(ASTNodeVisitor):
    def __init__(self):
        super().__init__()
        # Stack to keep track of the current scope hierarchy (e.g., ['global', 'funcs.function_b'])
        self.scope_stack = ["global"]
        # Track local variables/CTEs within the current context to avoid flagging them as external dependencies
        self.local_identifiers = {"global": set()}
        # Dependency graph: maps a scope to a set of entities it depends on
        self.dependencies = {"global": set()}

    @property
    def current_scope(self) -> str:
        return self.scope_stack[-1]

    def _register_dependency(self, target_name: str) -> None:
        """Helper to register that the current scope depends on a target function/table."""
        # Avoid self-referencing loops and skip locally declared identifiers (like CTEs)
        if target_name != self.current_scope and target_name not in self.local_identifiers.get(self.current_scope, set()):
            self.dependencies[self.current_scope].add(target_name)

    def _extract_name(self, path_expression_node) -> str:
        """Safely extracts a dot-separated string from an ASTPathExpression."""
        if hasattr(path_expression_node, "names"):
            return ".".join([n.id_string for n in path_expression_node.names if hasattr(n, "id_string")])
        return ""

    def visit(self, node):
        """
        Intercepts the visitor lifecycle to handle dynamic scopes cleanly 
        without breaking the underlying C++ traversal engine.
        """
        pushed_scope = False
        
        # Check node type string to safely match underlying zetasql nodes
        node_type = type(node).__name__

        if node_type == "ASTCreateFunctionStatement":
            if hasattr(node, "name"):
                func_name = self._extract_name(node.name)
                self.scope_stack.append(func_name)
                self.dependencies[func_name] = set()
                self.local_identifiers[func_name] = set()
                pushed_scope = True

        elif node_type == "ASTCreateTableFunctionStatement":
            if hasattr(node, "name"):
                tvf_name = self._extract_name(node.name)
                self.scope_stack.append(tvf_name)
                self.dependencies[tvf_name] = set()
                self.local_identifiers[tvf_name] = set()
                pushed_scope = True

        elif node_type == "ASTWithClauseEntry":
            if hasattr(node, "alias") and hasattr(node.alias, "id_string"):
                cte_name = node.alias.id_string
                # Add CTE to local definitions for the immediate scope parent
                self.local_identifiers.setdefault(self.current_scope, set()).add(cte_name)

        elif node_type == "ASTFunctionCall":
            if hasattr(node, "function"):
                func_name = self._extract_name(node.function)
                if func_name:
                    self._register_dependency(func_name)

        elif node_type == "ASTTVF":
            if hasattr(node, "name"):
                tvf_name = self._extract_name(node.name)
                if tvf_name:
                    self._register_dependency(tvf_name)

        # Delegate continuous depth-first traversal to Python-ZetaSQL runtime engine
        super().visit(node)

        # Clean up scope stack context on node exit
        if pushed_scope:
            self.scope_stack.pop()

    def display_graph(self) -> None:
        """Prints a structured view of the dependency graph."""
        print("\n=== RESOLVED DEPENDENCY GRAPH ===")
        for scope in sorted(self.dependencies.keys()):
            deps = self.dependencies[scope]
            if deps or scope != "global":  # Ensure we show all function definitions even if they have 0 dependencies
                print(f"\n📦 Scope: {scope}")
                if deps:
                    for dep in sorted(deps):
                        print(f"  └── ➡️ Depends on: {dep}")
                else:
                    print("  └── (No external dependencies)")

# Test Execution
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
  |> select (val).(funcs.function_b)() as new_val
  |> WHERE True
  |> SELECT (new_val).function_a()
);
""", options=lang_opts)

visitor = DependencyResolverVisitor()

for statement_node in sql_payload.statement_list_node.statement_list:
    visitor.visit(statement_node)

visitor.display_graph()