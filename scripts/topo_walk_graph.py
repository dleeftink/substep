# Attempts to build call graph from AST

from typing import List, Dict, Any
from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions

# 1. Enable pipe syntax and maximum features
lang_opts = LanguageOptions.maximum_features()

class GraphNode:
    """Represents a structural element in the final call graph hierarchy."""
    def __init__(self, name: str, is_chained: bool = False):
        self.name: str = name
        self.is_chained: bool = is_chained
        self.children: List['GraphNode'] = []

class HierarchyCallGraphBuilder(ASTNodeVisitor):
    def __init__(self, entrypoint_name: str = "use.parser"):
        super().__init__()
        # Initialise the root node for the overall master call graph view
        self.root = GraphNode(entrypoint_name)
        
        # Operational node stack to handle recursive parent linkage
        self.node_stack: List[GraphNode] = [self.root]

    @property
    def current_parent(self) -> GraphNode:
        return self.node_stack[-1]

    def _push_call(self, name: str, is_chained: bool = False) -> GraphNode:
        """Hooks a new discovered calling context to the current active tree parent."""
        new_node = GraphNode(name, is_chained=is_chained)
        self.current_parent.children.append(new_node)
        return new_node

    # ==========================================
    # 1. PARSING SUBQUERIES AND ALIEN PIPELINES
    # ==========================================
    def visit_ASTWithClauseEntry(self, node) -> None:
        """Treats a CTE block definition as a child branch of the main calling scope."""
        cte_name = f"CTE_SCOPE:{node.alias.id_string}"
        new_parent = self._push_call(cte_name, is_chained=True)
        
        self.node_stack.append(new_parent)
        self.descend(node)
        self.node_stack.pop()

    def visit_ASTExpressionSubquery(self, node) -> None:
        """Captures standard conditional subqueries seamlessly as dependent blocks."""
        new_parent = self._push_call("SUBQUERY_CONTEXT", is_chained=True)
        
        self.node_stack.append(new_parent)
        self.descend(node)
        self.node_stack.pop()

    def visit_ASTArrayConstructorBySubquery(self, node) -> None:
        """Treats array(select ...) mappings as an explicit sub-execution call branch."""
        new_parent = self._push_call("array", is_chained=False)
        
        self.node_stack.append(new_parent)
        self.descend(node)
        self.node_stack.pop()

    # ==========================================
    # 2. INGESTION & PIPELINE ADAPTER FUNCTIONS
    # ==========================================
    def visit_ASTTVF(self, node) -> None:
        """Captures relational Table-Valued Functions (e.g. FROM GAP_FILL(...))."""
        if hasattr(node, "name") and hasattr(node.name, "names"):
            name = ".".join([n.id_string for n in node.name.names])
            new_parent = self._push_call(name, is_chained=False)
            
            self.node_stack.append(new_parent)
            self.descend(node)
            self.node_stack.pop()

    def visit_ASTPipeCall(self, node) -> None:
        """Captures modern pipe syntax TVFs (e.g. |> CALL custom_tvf())."""
        if hasattr(node, "call") and hasattr(node.call, "function") and hasattr(node.call.function, "names"):
            name = ".".join([n.id_string for n in node.call.function.names])
            # It's explicitly chained because it consumes the streaming pipe input relation!
            new_parent = self._push_call(name, is_chained=True)
            
            self.node_stack.append(new_parent)
            self.descend(node)
            self.node_stack.pop()

    def visit_ASTUnnestExpression(self, node) -> None:
        """Captures unnest generators as an active contextual call parent node."""
        new_parent = self._push_call("unnest", is_chained=False)
        
        self.node_stack.append(new_parent)
        self.descend(node)
        self.node_stack.pop()

    # ==========================================
    # 3. INTERCEPTING SCALAR EXPRESSIONS
    # ==========================================
    def visit_ASTFunctionCall(self, node) -> None:
        """Handles standard operations.

        Because ZetaSQL parses right-to-left for dot chains,
        the outer function wraps inner ones, matching your graph logic.
        """
        if hasattr(node, "function") and hasattr(node.function, "names"):
            name = ".".join([n.id_string for n in node.function.names])
            
            # Determine chain layout state: if the parent context is another function or array,
            # then this nested operation is structurally dependent/chained.
            is_chained = isinstance(self.current_parent, GraphNode) and self.current_parent != self.root
            
            new_parent = self._push_call(name, is_chained=is_chained)
            
            self.node_stack.append(new_parent)
            self.descend(node)
            self.node_stack.pop()
        else:
            self.descend(node)

    def visit_ASTCastExpression(self, node) -> None:
        """Ensures type casts are mapped correctly as a function frame inside the tree."""
        is_chained = isinstance(self.current_parent, GraphNode) and self.current_parent != self.root
        new_parent = self._push_call("cast", is_chained=is_chained)
        
        self.node_stack.append(new_parent)
        self.descend(node)
        self.node_stack.pop()

    def default_visit(self, node) -> None:
        self.descend(node)

    # ==========================================
    # CLEAN ACCURATE TREE RENDERING PRINTER
    # ==========================================
    def print_graph(self, node: Optional[GraphNode] = None, prefix: str = "", is_last: bool = True):
        if node is None:
            node = self.root
            print(f"  CALL GRAPH: {node.name}()")
            print("  " + "─" * (len(node.name) + 14))
            print("  └─ " + node.name)
            prefix = "      "
            for i, child in enumerate(node.children):
                self.print_graph(child, prefix, i == len(node.children) - 1)
            return

        # Prepare node display name matching your (chained) suffix template rule
        chain_flag = "(chained)" if node.is_chained else ""
        node_display = f"{node.name}{chain_flag}"
        
        # Build standard terminal box-drawing trees
        connector = "└─ " if is_last else "├─ "
        print(f"  {prefix}{connector}{node_display}")
        
        # Append appropriate whitespace/vertical padding parameters based on brother positions
        new_prefix = prefix + ("    " if is_last else "│   ")
        for i, child in enumerate(node.children):
            self.print_graph(child, new_prefix, i == len(node.children) - 1)

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

tracer = HierarchyCallGraphBuilder()
tracer.visit(stmt)
tracer.print_graph()
