from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions

# Enable pipe syntax and maximum features
lang_opts = LanguageOptions.maximum_features()

class DependencyResolverVisitor(ASTNodeVisitor):
    def __init__(self):
        super().__init__()
        # Stack to keep track of the current scope hierarchy (e.g., ['global', 'funcs.function_b'])
        self.scope_stack = ["global"]
        # Dependency graph: maps a scope to a set of entities it depends on
        self.dependencies = {"global": set()}

    @property
    def current_scope(self) -> str:
        return self.scope_stack[-1]

    def _register_dependency(self, target_name: str) -> None:
        """Helper to register that the current scope depends on a target function/table."""
        # Avoid self-referencing loops
        if target_name != self.current_scope:
            self.dependencies[self.current_scope].add(target_name)

    def _extract_name(self, path_expression_node) -> str:
        """Safely extracts a dot-separated string from an ASTPathExpression."""
        if hasattr(path_expression_node, "names"):
            return ".".join([n.id_string for n in path_expression_node.names if hasattr(n, "id_string")])
        return ""

    def visit_ASTCreateFunctionStatement(self, node) -> None:
        """Tracks the creation of scalar and aggregate User-Defined Functions."""
        func_name = self._extract_name(node.name)
        if func_name:
            # Push new scope
            self.scope_stack.append(func_name)
            self.dependencies[func_name] = set()
            
            # Descend to find dependencies inside the function body
            self.descend(node)
            
            # Pop scope back to parent
            self.scope_stack.pop()
        else:
            self.descend(node)

    def visit_ASTCreateTableFunctionStatement(self, node) -> None:
        """Tracks the creation of Table-Valued Functions (TVFs)."""
        tvf_name = self._extract_name(node.name)
        if tvf_name:
            self.scope_stack.append(tvf_name)
            self.dependencies[tvf_name] = set()
            self.descend(node)
            self.scope_stack.pop()
        else:
            self.descend(node)

    def visit_ASTWithClauseEntry(self, node) -> None:
        """Tracks local Common Table Expressions (CTEs) to separate them from global targets."""
        cte_name = node.alias.id_string if hasattr(node, "alias") and hasattr(node.alias, "id_string") else ""
        if cte_name:
            # CTE names create a local scope context, prefixed by their parent to remain unique
            scoped_cte_name = f"{self.current_scope} -> CTE:{cte_name}"
            self.scope_stack.append(scoped_cte_name)
            self.dependencies[scoped_cte_name] = set()
            
            self.descend(node)
            
            self.scope_stack.pop()
        else:
            self.descend(node)

    def visit_ASTFunctionCall(self, node) -> None:
        """Catches Scalar, Aggregate, and Dot-Chained Functions."""
        if hasattr(node, "function"):
            func_name = self._extract_name(node.function)
            if func_name:
                self._register_dependency(func_name)
        
        # Descend to catch nested or chained arguments
        self.descend(node)

    def visit_ASTTVF(self, node) -> None:
        """Catches Table-Valued Function usage inside queries."""
        if hasattr(node, "name"):
            tvf_name = self._extract_name(node.name)
            if tvf_name:
                self._register_dependency(tvf_name)
        self.descend(node)

    def default_visit(self, node) -> None:
        self.descend(node)

    def display_graph(self) -> None:
        """Prints a structured view of the dependency graph."""
        print("\n=== RESOLVED DEPENDENCY GRAPH ===")
        for scope, deps in self.dependencies.items():
            # Skip printing empty global noise if necessary, or print cleanly
            if deps:
                print(f"\n📦 Scope: {scope}")
                for dep in sorted(deps):
                    print(f"  └── ➡️ Depends on: {dep}")

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
