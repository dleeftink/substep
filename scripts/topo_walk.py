from typing import List, Dict, Any
from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions

# 1. Enable pipe syntax and maximum features
lang_opts = LanguageOptions.maximum_features()

class ScalarNode:
    """Represents a single scalar function or structural marker and its dependencies."""
    def __init__(self, name: str):
        self.name: str = name
        self.dependencies: List['ScalarNode'] = []

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "depends_on": [child.to_dict() for child in self.dependencies]
        }

class LineagePipelineTracer(ASTNodeVisitor):
    def __init__(self):
        super().__init__()
        self.scopes: Dict[str, List[Dict[str, Any]]] = {
            "MAIN_TIMELINE": []
        }
        self.scope_context_stack: List[str] = ["MAIN_TIMELINE"]
        # Context pointer tracking the active scalar expression parent
        self._current_parent_expr: Optional[ScalarNode] = None

    @property
    def current_scope(self) -> List[Dict[str, Any]]:
        return self.scopes[self.scope_context_stack[-1]]

    def _add_step(self, step_type: str, name: str, details: str = "") -> None:
        self.current_scope.append({
            "type": step_type,
            "name": name,
            "details": details,
            "expressions": []  # This will now store ScalarNode trees
        })

    def _register_expression(self, expr_name: str) -> ScalarNode:
        """Registers a scalar entity, linking it into the active execution hierarchy."""
        new_node = ScalarNode(expr_name)
        
        # If we are currently nested inside a parent expression, attach this as its dependency
        if self._current_parent_expr is not None:
            self._current_parent_expr.dependencies.append(new_node)
            return new_node
            
        # Otherwise, it's a top-level expression root in the current select block
        if not self.current_scope:
            self._add_step("PROJECTION_EXPRESSION", "SELECT_LIST")
        self.current_scope[-1]["expressions"].append(new_node)
        return new_node

    # ==========================================
    # 1. SCOPE ISOLATION TRANSITIONS
    # ==========================================
    def visit_ASTWithClauseEntry(self, node) -> None:
        cte_name = node.alias.id_string
        scope_key = f"CTE: {cte_name}"
        self.scopes[scope_key] = []
        
        self.scope_context_stack.append(scope_key)
        # Clear parent expression context when boundary hopping
        old_parent, self._current_parent_expr = self._current_parent_expr, None
        self.descend(node)
        self._current_parent_expr = old_parent
        self.scope_context_stack.pop()

    def visit_ASTExpressionSubquery(self, node) -> None:
        subquery_id = f"SUBQUERY_EXPR_{id(node)}"
        self.scopes[subquery_id] = []
        self._register_expression(f"[Nested Subquery Reference -> {subquery_id}]")
        
        self.scope_context_stack.append(subquery_id)
        old_parent, self._current_parent_expr = self._current_parent_expr, None
        self.descend(node)
        self._current_parent_expr = old_parent
        self.scope_context_stack.pop()

    def visit_ASTArrayConstructorBySubquery(self, node) -> None:
        array_id = f"ARRAY_SUBQUERY_{id(node)}"
        self.scopes[array_id] = []
        self._register_expression(f"ARRAY_CONSTRUCTOR [Nested Subquery -> {array_id}]")
        
        self.scope_context_stack.append(array_id)
        old_parent, self._current_parent_expr = self._current_parent_expr, None
        self.descend(node)
        self._current_parent_expr = old_parent
        self.scope_context_stack.pop()

    # ==========================================
    # 2. SEQUENCE PRECEDENCE ADJUSTMENT
    # ==========================================
    def visit_ASTSelect(self, node) -> None:
        if hasattr(node, "from_clause") and node.from_clause:
            self.visit(node.from_clause)
        if hasattr(node, "where_clause") and node.where_clause:
            self.visit(node.where_clause)
        if hasattr(node, "select_list") and node.select_list:
            self.visit(node.select_list)

    # ==========================================
    # 3. INTERCEPTING COGNIZANT SOURCES
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
        if hasattr(node, "call") and hasattr(node.call, "function") and hasattr(node.call.function, "names"):
            name = ".".join([n.id_string for n in node.call.function.names])
            self._add_step("PIPE_TVF_TRANSFORM", f"|> CALL {name}")
        self.descend(node)

    def visit_ASTPipeSelect(self, node) -> None:
        self._add_step("PIPE_SELECT_PROJECTION", "|> SELECT Transformation Step")
        self.descend(node)

    def visit_ASTUnnestExpression(self, node) -> None:
        self._add_step("DATA_INGESTION", "UNNEST() Relational Generator")
        self.descend(node)

    # ==========================================
    # 4. EXPLICIT DEPENDENCY INTERCEPTION
    # ==========================================
    def visit_ASTFunctionCall(self, node) -> None:
        """Processes functions by establishing structural child dependencies via the stack frame context."""
        if hasattr(node, "function") and hasattr(node.function, "names"):
            name = ".".join([n.id_string for n in node.function.names])
            
            # Register this function
            registered_node = self._register_expression(name)
            
            # Track context shift: down-level calls become dependencies of this node
            old_parent = self._current_parent_expr
            self._current_parent_expr = registered_node
            
            self.descend(node)
            
            # Reset structural alignment up-level on return climb
            self._current_parent_expr = old_parent
        else:
            self.descend(node)

    def default_visit(self, node) -> None:
        self.descend(node)

    # ==========================================
    # GRAPH RE-RENDERER ENGINE
    # ==========================================
    def _print_expr_tree(self, node: ScalarNode, indent_level: int) -> None:
        indent = " " * indent_level
        if node.dependencies:
            print(f"{indent}↳ {node.name} (Calculated from:)")
            for dep in node.dependencies:
                self._print_expr_tree(dep, indent_level + 4)
        else:
            print(f"{indent}↳ {node.name}")

    def print_graph(self):
        print("\n=== TRACED PRECEDENCE LINEAGE DEPENDENCY GRAPH ===")
        for scope_label, steps in self.scopes.items():
            if not steps:
                continue
            print(f"\n📦 [Execution Block]: {scope_label}")
            for step in steps:
                print(f"  • {step['type']} -> {step['name']}")
                if step["expressions"]:
                    print("    [Evaluated Expressions Trace]:")
                    for expr_root in step["expressions"]:
                        self._print_expr_tree(expr_root, 6)

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

tracer = LineagePipelineTracer()
tracer.visit(stmt)
tracer.print_graph()
