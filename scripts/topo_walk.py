from typing import List, Dict, Any
from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions

# 1. Enable pipe syntax and maximum features
lang_opts = LanguageOptions.maximum_features()

class ScalarNode:
    """Represents an isolated expression tree node containing recursive dependencies."""
    def __init__(self, name: str):
        self.name: str = name
        self.dependencies: List['ScalarNode'] = []

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "depends_on": [child.to_dict() for child in self.dependencies]
        }

class IsolatedPipelineTracer(ASTNodeVisitor):
    def __init__(self):
        super().__init__()
        # Scope dictionary stores a dictionary matching distinct execution stages
        self.scopes: Dict[str, Dict[str, List[Any]]] = {
            "MAIN_TIMELINE": {"INGESTION": [], "PROJECTION": []}
        }
        self.scope_context_stack: List[str] = ["MAIN_TIMELINE"]
        
        # Internal flags to track section splits and active tree parents
        self._active_section: str = "INGESTION"
        self._current_parent_expr: Optional[ScalarNode] = None

    @property
    def current_scope_maps(self) -> Dict[str, List[Any]]:
        return self.scopes[self.scope_context_stack[-1]]

    def _add_relational_source(self, step_type: str, name: str, details: str = "") -> None:
        """Appends table sources or streaming operations to the ingestion section."""
        self.current_scope_maps["INGESTION"].append({
            "type": step_type,
            "name": name,
            "details": details
        })

    def _register_scalar_node(self, expr_name: str) -> ScalarNode:
        """Hooks a scalar element safely into the active tree, matching style blends."""
        new_node = ScalarNode(expr_name)
        
        # Context Check: If nested inside a parent node, assign as its dependent child
        if self._current_parent_expr is not None:
            self._current_parent_expr.dependencies.append(new_node)
            return new_node
            
        # Otherwise, write as a top-level root item inside the current step section
        target_list = "PROJECTION" if self._active_section == "PROJECTION" else "INGESTION"
        self.current_scope_maps[target_list].append(new_node)
        return new_node

    # ==========================================
    # 1. CLEAN SCOPE STATE TRANSITIONS
    # ==========================================
    def _enter_isolated_scope(self, scope_label: str, node: Any) -> None:
        """Helper to swap scope keys while preserving execution tracking flags safely."""
        self.scopes[scope_label] = {"INGESTION": [], "PROJECTION": []}
        self.scope_context_stack.append(scope_label)
        
        # Save structural tracking configurations
        old_section, self._active_section = self._active_section, "INGESTION"
        old_parent, self._current_parent_expr = self._current_parent_expr, None
        
        self.descend(node)
        
        # Restore configuration properties
        self._current_parent_expr = old_parent
        self._active_section = old_section
        self.scope_context_stack.pop()

    def visit_ASTWithClauseEntry(self, node) -> None:
        self._enter_isolated_scope(f"CTE: {node.alias.id_string}", node)

    def visit_ASTExpressionSubquery(self, node) -> None:
        sub_id = f"SUBQUERY_EXPR_{id(node)}"
        self._register_scalar_node(f"[Nested Scalar Subquery -> {sub_id}]")
        self._enter_isolated_scope(sub_id, node)

    def visit_ASTArrayConstructorBySubquery(self, node) -> None:
        array_id = f"ARRAY_SUBQUERY_{id(node)}"
        self._register_scalar_node(f"ARRAY_CONSTRUCTOR [Nested Row Pipeline -> {array_id}]")
        self._enter_isolated_scope(array_id, node)

    # ==========================================
    # 2. ENFORCING OPERATIONAL SPLIT ORDERS
    # ==========================================
    def visit_ASTSelect(self, node) -> None:
        """Forces relational pipelines to process completely before evaluation blocks."""
        self._active_section = "INGESTION"
        if hasattr(node, "from_clause") and node.from_clause:
            self.visit(node.from_clause)
        if hasattr(node, "where_clause") and node.where_clause:
            self.visit(node.where_clause)
            
        self._active_section = "PROJECTION"
        if hasattr(node, "select_list") and node.select_list:
            self.visit(node.select_list)

    # ==========================================
    # 3. INTERCEPTING DATA SOURCE OBJECTS
    # ==========================================
    def visit_ASTTablePathExpression(self, node) -> None:
        if hasattr(node, "path_expr") and hasattr(node.path_expr, "names"):
            name = ".".join([n.id_string for n in node.path_expr.names])
            self._add_relational_source("DATA_SOURCE", f"Table/CTE Reference ({name})")
        self.descend(node)

    def visit_ASTTVF(self, node) -> None:
        if hasattr(node, "name") and hasattr(node.name, "names"):
            name = ".".join([n.id_string for n in node.name.names])
            self._add_relational_source("DATA_SOURCE", f"Table Function Source ({name})")
        self.descend(node)

    def visit_ASTPipeCall(self, node) -> None:
        if hasattr(node, "call") and hasattr(node.call, "function") and hasattr(node.call.function, "names"):
            name = ".".join([n.id_string for n in node.call.function.names])
            self._add_relational_source("PIPE_RELATIONAL_TRANSFORM", f"|> CALL {name}")
        self.descend(node)

    def visit_ASTPipeSelect(self, node) -> None:
        self._add_relational_source("PIPE_RELATIONAL_PROJECTION", "|> SELECT Boundary Step")
        self.descend(node)

    def visit_ASTUnnestExpression(self, node) -> None:
        self._add_relational_source("RELATIONAL_GENERATOR", "UNNEST() Functional Set Splitter")
        # Direct functions nested in UNNEST belong inside the local structural Ingestion block context!
        old_section, self._active_section = self._active_section, "INGESTION"
        self.descend(node)
        self._active_section = old_section

    # ==========================================
    # 4. RESOLVING SCALAR EXPRESSION TREES
    # ==========================================
    def visit_ASTFunctionCall(self, node) -> None:
        if hasattr(node, "function") and hasattr(node.function, "names"):
            name = ".".join([n.id_string for n in node.function.names])
            
            registered_node = self._register_scalar_node(name)
            old_parent, self._current_parent_expr = self._current_parent_expr, registered_node
            self.descend(node)
            self._current_parent_expr = old_parent
        else:
            self.descend(node)

    def visit_ASTCastExpression(self, node) -> None:
        """Captures CAST syntactic transformations safely, preserving parent chains."""
        registered_node = self._register_scalar_node("CAST(...)")
        old_parent, self._current_parent_expr = self._current_parent_expr, registered_node
        self.descend(node)
        self._current_parent_expr = old_parent

    def default_visit(self, node) -> None:
        self.descend(node)

    # ==========================================
    # CLEAN TREE PRINTING UTILITIES
    # ==========================================
    def _print_scalar_node(self, node: ScalarNode, indent_level: int) -> None:
        indent = " " * indent_level
        if node.dependencies:
            print(f"{indent}↳ {node.name} (Evaluated via:) ")
            for dependency in node.dependencies:
                self._print_scalar_node(dependency, indent_level + 4)
        else:
            print(f"{indent}↳ {node.name}")

    def print_graph(self):
        print("\n=== ISOLATED LINEAGE PRECISION DEPENDENCY GRAPH ===")
        for scope_label, sections in self.scopes.items():
            if not sections["INGESTION"] and not sections["PROJECTION"]:
                continue
                
            print(f"\n📦 [Execution Framework Context]: {scope_label}")
            
            if sections["INGESTION"]:
                print("  ├── [A. Data Engine Ingestion / Relational Timeline]:")
                for entry in sections["INGESTION"]:
                    if isinstance(entry, dict):
                        details = f" ({entry['details']})" if entry['details'] else ""
                        print(f"  │     • {entry['type']} -> {entry['name']}{details}")
                    elif isinstance(entry, ScalarNode):
                        self._print_scalar_node(entry, 8)
                        
            if sections["PROJECTION"]:
                print("  └── [B. Projection Expressions / Final Scalar Transformations]:")
                for scalar_tree in sections["PROJECTION"]:
                    if isinstance(scalar_tree, ScalarNode):
                        self._print_scalar_node(scalar_tree, 8)

# Complex Query mixing CTEs, regular subqueries, and modern Implicit Pipe TVF Calls
stmt = Parser.parse_statement_static("""
    WITH filtered_records AS (
        SELECT user_id, amount 
        FROM custom.db_table
        WHERE amount > (SELECT AVG(o.total) FROM schema.orders o)
    ),

    process as (    
      FROM filtered_records
      |> CALL modern_analytics.ANALYZE_COHORTS(50, "regional")
      |> SELECT (user_id).upper().left(4) id, array(select cast(v as string).farm_fingerprint() from unnest(generate_array(0,5)) v) arr
    ),

    exit as (
      select id, arr.array_slice(0,2) as arr 
      from process
    )

    select * from exit
""", options=lang_opts)

tracer = IsolatedPipelineTracer()
tracer.visit(stmt)
tracer.print_graph()
