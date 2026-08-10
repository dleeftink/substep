from typing import List, Dict, Any
from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions

# 1. Enable pipe syntax and maximum features
lang_opts = LanguageOptions.maximum_features()

class RobustPipelineTracer(ASTNodeVisitor):
    def __init__(self):
        super().__init__()
        # Keeps track of stacked scopes (handles deep subquery encapsulation)
        self.scope_stack: List[List[Dict[str, Any]]] = [[]]

    @property
    def current_scope_sequence(self) -> List[Dict[str, Any]]:
        return self.scope_stack[-1]

    def _add_step(self, step_type: str, name: str, details: str = "") -> None:
        """Appends a logical transformation step to the active scope sequence."""
        self.current_scope_sequence.append({
            "type": step_type,
            "name": name,
            "details": details,
            "expressions": []
        })

    def _add_expr_to_last_step(self, expr_name: str) -> None:
        """Attaches scalar/aggregate expressions to whichever step is currently active."""
        if self.current_scope_sequence:
            self.current_scope_sequence[-1]["expressions"].append(expr_name)

    # ==========================================
    # 1. HANDLING ISOLATED SUBQUERIES & CTEs
    # ==========================================
    def visit_ASTWithClauseEntry(self, node) -> None:
        """Pushes a unique stack context for an isolated CTE definition block."""
        cte_name = node.alias.id_string
        self._add_step("CTE_DEFINITION_START", cte_name)
        
        # Isolate the CTE pipeline inside its own tracking stack frame
        self.scope_stack.append([])
        self.descend(node)
        cte_steps = self.scope_stack.pop()
        
        # Attach the compiled steps directly into the declaration step
        self.current_scope_sequence[-1]["sub_pipeline"] = cte_steps
        self._add_step("CTE_DEFINITION_END", cte_name)

    def visit_ASTExpressionSubquery(self, node) -> None:
        """Intercepts classical nested subqueries (e.g., WHERE x = (SELECT ...))."""
        self._add_expr_to_last_step("[SUBQUERY_EXPR_MARKER]")
        
        # Isolate inner subquery transformations completely
        self.scope_stack.append([])
        self.descend(node)
        subquery_steps = self.scope_stack.pop()
        
        # Save nested flow right onto the current step
        if self.current_scope_sequence:
            if "nested_subqueries" not in self.current_scope_sequence[-1]:
                self.current_scope_sequence[-1]["nested_subqueries"] = []
            self.current_scope_sequence[-1]["nested_subqueries"].append(subquery_steps)

    # ==========================================
    # 2. RESOLVING STANDARD SQL ORDER INVERSION
    # ==========================================
    def visit_ASTSelect(self, node) -> None:
        """Forces logical operational execution ordering: FROM targets before SELECT list."""
        if hasattr(node, "from_clause") and node.from_clause:
            self.visit(node.from_clause)
        if hasattr(node, "select_list") and node.select_list:
            self.visit(node.select_list)

    # ==========================================
    # 3. INTERCEPTING INGESTIONS & PIPES
    # ==========================================
    def visit_ASTTablePathExpression(self, node) -> None:
        if hasattr(node, "path_expr") and hasattr(node.path_expr, "names"):
            name = ".".join([n.id_string for n in node.path_expr.names])
            self._add_step("INGEST_TABLE/CTE", name)
        self.descend(node)

    def visit_ASTTVF(self, node) -> None:
        """Standard SQL FROM clause TVF (e.g., FROM GAP_FILL(...))."""
        if hasattr(node, "name") and hasattr(node.name, "names"):
            name = ".".join([n.id_string for n in node.name.names])
            self._add_step("INGEST_TVF_SOURCE", name)
        self.descend(node)

    def visit_ASTPipeCall(self, node) -> None:
        """Modern Pipe syntax TVF step (e.g., |> CALL custom.TVF(args)).

        The input table argument is implicitly passed from the upstream pipe!
        """
        if hasattr(node, "call") and hasattr(node.call, "function") and hasattr(node.call.function, "names"):
            name = ".".join([n.id_string for n in node.call.function.names])
            # Explicitly label the implicit streaming data linkage context
            self._add_step("PIPE_TVF_CALL", name, "Implicitly Ingests Upstream Table Context")
        
        # Descending captures any static scalar arguments evaluated inside the TVF wrapper parameters
        self.descend(node)

    def visit_ASTPipeSelect(self, node) -> None:
        """Modern Pipe select step (e.g., |> SELECT x, y)."""
        self._add_step("PIPE_TRANSFORM_SELECT", "SELECT")
        self.descend(node)

    # ==========================================
    # 4. CAPTURING ATOM EXPRESSIONS
    # ==========================================
    def visit_ASTFunctionCall(self, node) -> None:
        if hasattr(node, "function") and hasattr(node.function, "names"):
            name = ".".join([n.id_string for n in node.function.names])
            self._add_expr_to_last_step(name)
        self.descend(node)

    def default_visit(self, node) -> None:
        self.descend(node)

    # ==========================================
    # GRAPH PRINTER ENGINE
    # ==========================================
    def print_pipeline(self, steps: List[Dict[str, Any]] = None, indent: int = 0):
        if steps is None:
            steps = self.scope_stack[0]
            print("\n=== VERIFIED CHRONOLOGICAL EXECUTION GRAPH ===")

        prefix = "  " * indent
        for step in steps:
            print(f"{prefix}• [{step['type']}] Name: {step['name']}" + (f" ({step['details']})" if step['details'] else ""))
            if step["expressions"]:
                print(f"{prefix}    ↳ Scalar Functions: {', '.join(step['expressions'])}")
            
            # Print nested subquery flows inside this clause step
            if "nested_subqueries" in step:
                for sub_seq in step["nested_subqueries"]:
                    print(f"{prefix}    ⚡ [Isolated Evaluation Inner Subquery]:")
                    self.print_pipeline(sub_seq, indent + 3)
            
            # Print recursive CTE inner definitions
            if "sub_pipeline" in step:
                self.print_pipeline(step["sub_pipeline"], indent + 2)

# Complex Query mixing CTEs, regular subqueries, and modern Implicit Pipe TVF Calls
stmt = Parser.parse_statement_static("""
    WITH filtered_records AS (
        SELECT user_id, amount 
        FROM custom.db_table
        WHERE amount > (SELECT AVG(o.total) FROM schema.orders o)
    )
    FROM filtered_records
    |> CALL modern_analytics.ANALYZE_COHORTS(50, "regional")
    |> SELECT (user_id).upper(), amount
""", options=lang_opts)

tracer = RobustPipelineTracer()
tracer.visit(stmt)
tracer.print_pipeline()
