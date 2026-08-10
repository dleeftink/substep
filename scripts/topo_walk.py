from typing import List, Dict, Any
from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions

# 1. Enable pipe syntax and maximum features
lang_opts = LanguageOptions.maximum_features()

class RobustPipelineTracer(ASTNodeVisitor):
    def __init__(self):
        super().__init__()
        # Every distinct block (Main Query, CTE, or Subquery) is tracked here
        self.scopes: Dict[str, List[Dict[str, Any]]] = {
            "MAIN_TIMELINE": []
        }
        # Tracks which scope label is currently active
        self.scope_context_stack: List[str] = ["MAIN_TIMELINE"]

    @property
    def current_scope(self) -> List[Dict[str, Any]]:
        return self.scopes[self.scope_context_stack[-1]]

    def _add_step(self, step_type: str, name: str, details: str = "") -> None:
        """Appends a new structural operation stage to the active scope sequence."""
        self.current_scope.append({
            "type": step_type,
            "name": name,
            "details": details,
            "expressions": []
        })

    def _add_expr_to_last_step(self, expr_name: str) -> None:
        """Attaches discovered functions directly to the active stage block."""
        if self.current_scope:
            self.current_scope[-1]["expressions"].append(expr_name)
        else:
            # Fallback placeholder if an expression is processed before an ingestion phase
            self._add_step("PROJECTION_EXPRESSION", "SELECT_LIST")
            self.current_scope[-1]["expressions"].append(expr_name)

    # ==========================================
    # 1. FIXED SCOPE TRANSITIONS
    # ==========================================
    def visit_ASTWithClauseEntry(self, node) -> None:
        """Isolates CTE definitions into a dedicated, clean scope key."""
        cte_name = node.alias.id_string
        scope_key = f"CTE: {cte_name}"
        self.scopes[scope_key] = []
        
        self.scope_context_stack.append(scope_key)
        self.descend(node)
        self.scope_context_stack.pop()

    def visit_ASTExpressionSubquery(self, node) -> None:
        """Safely isolates traditional subqueries (e.g. WHERE amount > (SELECT...))."""
        # Create a unique identifiable scope label
        subquery_id = f"SUBQUERY_EXPR_{id(node)}"
        self.scopes[subquery_id] = []
        self._add_expr_to_last_step(f"[Nested Subquery Reference -> {subquery_id}]")
        
        self.scope_context_stack.append(subquery_id)
        self.descend(node)
        self.scope_context_stack.pop()

    def visit_ASTArrayConstructorBySubquery(self, node) -> None:
        """Captures modern inline array generation subqueries: array(select ...)."""
        array_id = f"ARRAY_SUBQUERY_{id(node)}"
        self.scopes[array_id] = []
        self._add_expr_to_last_step(f"ARRAY_CONSTRUCTOR [Nested Subquery -> {array_id}]")
        
        self.scope_context_stack.append(array_id)
        self.descend(node)
        self.scope_context_stack.pop()

    # ==========================================
    # 2. EVALUATION PRECEDENCE OVERRIDES
    # ==========================================
    def visit_ASTSelect(self, node) -> None:
        """Forces FROM data ingestions to evaluate before SELECT functions."""
        if hasattr(node, "from_clause") and node.from_clause:
            self.visit(node.from_clause)
        if hasattr(node, "where_clause") and node.where_clause:
            self.visit(node.where_clause)
        if hasattr(node, "select_list") and node.select_list:
            self.visit(node.select_list)

    # ==========================================
    # 3. SOURCE & PIPE FUNCTION DETECTION
    # ==========================================
    def visit_ASTTablePathExpression(self, node) -> None:
        if hasattr(node, "path_expr") and hasattr(node.path_expr, "names"):
            name = ".".join([n.id_string for n in node.path_expr.names])
            self._add_step("DATA_INGESTION", f"Table/CTE Reference ({name})")
        self.descend(node)

    def visit_ASTTVF(self, node) -> None:
        if hasattr(node, "name") and hasattr(node.name, "names"):
            name = ".".join([n.id_string for n in node.name.names])
            self._add_step("DATA_INGESTION", f"Table-Valued Function Call ({name})")
        self.descend(node)

    def visit_ASTPipeCall(self, node) -> None:
        """Correctly captures |> CALL custom.TVF expressions."""
        if hasattr(node, "call") and hasattr(node.call, "function") and hasattr(node.call.function, "names"):
            name = ".".join([n.id_string for n in node.call.function.names])
            self._add_step("PIPE_TVF_TRANSFORM", f"|> CALL {name}", "Implicitly receives upstream data relation")
        self.descend(node)

    def visit_ASTPipeSelect(self, node) -> None:
        self._add_step("PIPE_SELECT_PROJECTION", "|> SELECT Transformation Step")
        self.descend(node)

    def visit_ASTUnnestExpression(self, node) -> None:
        """Catches and exposes table transformations that unnest arrays."""
        self._add_step("DATA_INGESTION", "UNNEST() Relational Generator")
        self.descend(node)

    # ==========================================
    # 4. SCALAR ATOM INTERCEPTION
    # ==========================================
    def visit_ASTFunctionCall(self, node) -> None:
        if hasattr(node, "function") and hasattr(node.function, "names"):
            name = ".".join([n.id_string for n in node.function.names])
            self._add_expr_to_last_step(name)
        self.descend(node)

    def default_visit(self, node) -> None:
        self.descend(node)

    # ==========================================
    # GRAPH RENDERING OUTPUT
    # ==========================================
    def print_graph(self):
        print("\n=== COMPILATION-SAFE CHRONOLOGICAL EXECUTION GRAPH ===")
        for scope_label, steps in self.scopes.items():
            if not steps:
                continue
            print(f"\n📦 [Execution Block Boundaries]: {scope_label}")
            for step in steps:
                details_str = f" ({step['details']})" if step['details'] else ""
                print(f"  • Operation: {step['type']} -> {step['name']}{details_str}")
                if step["expressions"]:
                    print(f"    ↳ Parsed Functions: {', '.join(step['expressions'])}")

# Complex Query mixing CTEs, regular subqueries, and modern Implicit Pipe TVF Calls
stmt = Parser.parse_statement_static("""
    WITH filtered_records AS (
        SELECT user_id, amount 
        FROM custom.db_table
        WHERE amount > (SELECT AVG(o.total) FROM schema.orders o)
    )
    FROM filtered_records
    |> CALL modern_analytics.ANALYZE_COHORTS(50, "regional")
    |> SELECT (user_id).upper().left(4), array(select cast(v as string).farm_fingerprint() from unnest(generate_array(0,5)) v)
""", options=lang_opts)

tracer = RobustPipelineTracer()
tracer.visit(stmt)
tracer.print_graph()
