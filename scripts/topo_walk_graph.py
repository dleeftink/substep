from typing import List, Dict, Set, Optional, Tuple
from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions

# 1. Initialize complete engine properties
lang_opts = LanguageOptions.maximum_features()

class DependencyExtractor(ASTNodeVisitor):
    """
    Traverses the abstract syntax tree of a multi-statement script 
    without clearing context markers prematurely.
    """
    def __init__(self):
        super().__init__()
        self.call_graph: Dict[str, Set[str]] = {}
        self.standalone_calls: Set[str] = set()
        self._current_definition: Optional[str] = None

    def _register_call(self, func_name: str):
        """Routes identified dependencies based on current parent context."""
        normalized_name = func_name.lower()
        if self._current_definition:
            self.call_graph[self._current_definition].add(normalized_name)
        else:
            self.standalone_calls.add(normalized_name)

    # ==========================================
    # 1. FIXED CONTEXT BOUNDARY SCOPING
    # ==========================================
    def visit_ASTCreateFunctionStatement(self, node) -> None:
        """Handles standard and TEMP scalar function definition wrappers."""
        if hasattr(node, "name") and hasattr(node.name, "names"):
            func_name = ".".join([n.id_string for n in node.name.names]).lower()
            
            # Save parent frame context to avoid race conditions
            old_definition = self._current_definition
            self._current_definition = func_name
            if func_name not in self.call_graph:
                self.call_graph[func_name] = set()
            
            # Recursively explore all inner child blocks
            self.descend(node)
            
            # Restore frame state safely
            self._current_definition = old_definition
        else:
            self.descend(node)

    def visit_ASTCreateTableFunctionStatement(self, node) -> None:
        """Handles table-valued function structures."""
        if hasattr(node, "name") and hasattr(node.name, "names"):
            tvf_name = ".".join([n.id_string for n in node.name.names]).lower()
            
            old_definition = self._current_definition
            self._current_definition = tvf_name
            if tvf_name not in self.call_graph:
                self.call_graph[tvf_name] = set()
                
            self.descend(node)
            self._current_definition = old_definition
        else:
            self.descend(node)

    # ==========================================
    # 2. CALL ROUTING OVERRIDES
    # ==========================================
    def visit_ASTFunctionCall(self, node) -> None:
        if hasattr(node, "function") and hasattr(node.function, "names"):
            name = ".".join([n.id_string for n in node.function.names])
            self._register_call(name)
        self.descend(node)

    def visit_ASTPipeCall(self, node) -> None:
        if hasattr(node, "call") and hasattr(node.call, "function") and hasattr(node.call.function, "names"):
            name = ".".join([n.id_string for n in node.call.function.names])
            self._register_call(name)
        self.descend(node)

    def default_visit(self, node) -> None:
        self.descend(node)


def build_installer_call_graph(combined_sql_script: str) -> Tuple[Dict[str, List[str]], List[str]]:
    """
    Parses a single script block and filters output nodes to construct 
    a robust UDF topological layout matrix.
    """
    script_node = Parser.parse_script_static(combined_sql_script, options=lang_opts)
    extractor = DependencyExtractor()
    
    for statement_node in script_node.statement_list_node.statement_list:
        extractor.visit(statement_node)
        
    # Transform active unique sets into formatted arrays
    final_graph = {udf: sorted(list(deps)) for udf, deps in extractor.call_graph.items()}
    defined_udfs = set(final_graph.keys())
    
    # Filter the map: track custom target definitions while removing native commands
    filtered_graph = {}
    for udf, deps in final_graph.items():
        filtered_graph[udf] = [d for d in deps if d in defined_udfs and d != udf]
        
    # Deduplicate non-UDF expressions discovered on the timeline
    clean_standalone = sorted(list({c for c in extractor.standalone_calls if c not in defined_udfs}))
        
    return filtered_graph, clean_standalone

# Semicolon separated arbitrary declaration payload
sql_payload = """
CREATE or replace FUNCTION funcs.function_a(inp ANY TYPE) AS ((
  SELECT inp
));

CREATE or replace FUNCTION funcs.function_b(inp ANY TYPE) AS ((
  SELECT (inp).(funcs.function_a)()
));

CREATE OR REPLACE FUNCTION custom_namespace.analytical_hub(val INT64) AS ((
  SELECT * FROM (SELECT (val).(funcs.function_b)())
  |> WHERE True
  |> SELECT (id).function_a()
));

SELECT (select (2).(funcs.function_a)().(funcs.function_b)()).(funcs.function_a)().(funcs.function_b)();
"""

dependencies, standalone_references = build_installer_call_graph(sql_payload)

print("=== INSTALLER DEPENDENCY GRAPH ===")
for function, targets in dependencies.items():
    print(f"Function `{function}` depends on compilation of: {targets}")

print("\n=== AD-HOC STANDALONE QUERY REFERENCES ===")
print(standalone_references)
