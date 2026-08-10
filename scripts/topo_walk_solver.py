# The thing won't descend; everything turns up in the global scope

from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions

# Enable pipe syntax and maximum features
lang_opts = LanguageOptions.maximum_features()

class DependencyResolverVisitor(ASTNodeVisitor):
    def __init__(self):
        super().__init__()
        # Stack to keep track of the current scope hierarchy
        self.scope_stack = ["global"]
        # Track local definitions (like CTE names) to avoid treating them as external dependencies
        self.local_identifiers = {"global": set()}
        # Dependency graph mapping scopes to their dependencies
        self.dependencies = {"global": set()}

    @property
    def current_scope(self) -> str:
        return self.scope_stack[-1]

    def _register_dependency(self, target_name: str) -> None:
        """Helper to register that the current scope depends on a target function/table."""
        # Prevent self-referencing loops and ignore local variables/CTEs
        if target_name != self.current_scope and target_name not in self.local_identifiers.get(self.current_scope, set()):
            self.dependencies[self.current_scope].add(target_name)

    def _extract_name(self, path_expression_node) -> str:
        """Safely extracts a dot-separated string from an ASTPathExpression."""
        if hasattr(path_expression_node, "names"):
            return ".".join([n.id_string for n in path_expression_node.names if hasattr(n, "id_string")])
        return ""

    def default_visit(self, node) -> None:
        
        node_type = type(node).__name__
        pushed_scope = False

        # 1. Handle Entry into a New Function Scope Definition
        if node_type in ("ASTCreateFunctionStatement", "ASTCreateTableFunctionStatement"):
            if hasattr(node, "name"):
                func_name = self._extract_name(node.name)
                if func_name:
                    self.scope_stack.append(func_name)
                    self.dependencies[func_name] = set()
                    self.local_identifiers[func_name] = set()
                    pushed_scope = True

        # 2. Handle Entry into a Local CTE Context Block
        elif node_type == "ASTWithClauseEntry":
            if hasattr(node, "alias") and hasattr(node.alias, "id_string"):
                cte_name = node.alias.id_string
                self.local_identifiers.setdefault(self.current_scope, set()).add(cte_name)

        # 3. Handle Active Function Calls (Standard & Dot-Chained)
        elif node_type in ("ASTFunctionCall", "ASTDotFunctionCall"):
            if hasattr(node, "function"):
                func_name = self._extract_name(node.function)
                if func_name:
                    self._register_dependency(func_name)

        # 4. Handle Active Table-Valued Function (TVF) Calls
        elif node_type == "ASTTVF":
            if hasattr(node, "name"):
                tvf_name = self._extract_name(node.name)
                if tvf_name:
                    self._register_dependency(tvf_name)

        # 5. Descend deeper into the AST tree traversal
        self.descend(node)

        # 6. Handle Exit from the Function Scope Definition
        if pushed_scope:
            self.scope_stack.pop()

    def display_graph(self) -> None:
        """Prints a structured view of the dependency graph."""
        print("\n=== RESOLVED DEPENDENCY GRAPH ===")
        for scope in sorted(self.dependencies.keys()):
            deps = self.dependencies[scope]
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
