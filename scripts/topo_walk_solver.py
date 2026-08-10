from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions
import json

lang_opts = LanguageOptions.maximum_features()

class DynamicFunctionGraphExtractor(ASTNodeVisitor):
    def __init__(self):
        super().__init__()
        self.current_scope = "global"
        self.graphs = {}
        # Stores locally encountered calls inside the current active expression block
        self.expression_call_stack = []

    def _dynamically_extract_name(self, node) -> str:
        if node is None:
            return ""

        # Strategy 1: Check for explicit name_path/function_path attributes exposed by ZetaSQL-py
        if getattr(node, "name_path", None):
            return node.name_path
        if getattr(node, "function_path", None):
            return node.function_path

        # Strategy 2: Check for direct identifier strings
        if getattr(node, "id_string", None):
            return node.id_string
        if getattr(node, "image", None):
            return node.image

        # Strategy 3: Cycle dynamically through standard naming structures
        for attr_name in ("function_declaration", "function", "name", "method_name"):
            child = getattr(node, attr_name, None)
            if child:
                res = self._dynamically_extract_name(child)
                if res:
                    return res

        # Strategy 4: Fallback to token array paths
        if hasattr(node, "names"):
            try:
                segments = [n.id_string for n in node.names if getattr(n, "id_string", None)]
                if segments:
                    return ".".join(segments)
            except Exception:
                pass

        return ""

    def visit(self, node) -> None:
        if node is None:
            return

        node_type = type(node).__name__
        previous_scope = self.current_scope
        is_scope_defining_node = False

        # 1. Manage Declaration/Definition Scope Boundaries
        if "FunctionStatement" in node_type or "TVFStatement" in node_type:
            is_scope_defining_node = True
            extracted_scope = self._dynamically_extract_name(node)
            self.current_scope = extracted_scope if extracted_scope else "unknown_function_definition"
            if self.current_scope not in self.graphs:
                self.graphs[self.current_scope] = []
            
        # 2. Reset expression tracks at pipeline or statement clause splits
        is_statement_boundary = node_type in (
            "ASTSelectStatement", "ASTPipeSelect", "ASTPipeCall", "ASTPipeWhere", "ASTExpressionStatement"
        )
        
        saved_expr_stack = self.expression_call_stack
        if is_statement_boundary:
            self.expression_call_stack = []

        # 3. Post-Order Traversal (Dig Deep First)
        self.descend(node)

        # 4. Check for targeted call identifiers (Added ASTTVF to catch pipe calls)
        is_function_call = node_type in (
            "ASTFunctionCall", 
            "ASTTableValuedFunctionCall", 
            "ASTTVFCall", 
            "ASTTVF", 
            "ASTTVFArgument", 
            "ASTDotFunctionCall", 
            "ASTMethodCall"
        )

        if is_function_call:
            call_name = self._dynamically_extract_name(node)
            if call_name:
                if self.current_scope not in self.graphs:
                    self.graphs[self.current_scope] = []
                    
                if self.expression_call_stack:
                    child_dependency = self.expression_call_stack[-1]
                    if child_dependency != call_name:
                        edge = {"caller": call_name, "callee": child_dependency}
                        if edge not in self.graphs[self.current_scope]:
                            self.graphs[self.current_scope].append(edge)
                else:
                    edge = {"caller": call_name, "callee": None}
                    if edge not in self.graphs[self.current_scope]:
                        self.graphs[self.current_scope].append(edge)
                
                self.expression_call_stack.append(call_name)

        # 5. Restore stack states when winding upwards out of operations
        if is_statement_boundary:
            self.expression_call_stack = saved_expr_stack

        if is_scope_defining_node:
            self.current_scope = previous_scope
            self.expression_call_stack = []

# --- Execution using your exact original SQL string with `|> call` ---
sql_payload = Parser.parse_script_static("""
CREATE or replace FUNCTION funcs.function_a(inp ANY TYPE) AS ((
  SELECT inp 
));

CREATE or replace FUNCTION funcs.function_b(inp ANY TYPE) AS ((
  SELECT (inp).(funcs.function_a)()
));

CREATE OR REPLACE TABLE FUNCTION custom_namespace.analytical_hub(input TABLE<val int64>) AS (
  SELECT * FROM input
  |> call external_namespace.table_function()
  |> select (val).(funcs.function_b)() as new_val
  |> WHERE True
  |> SELECT (new_val).(funcs.function_a)().(funcs.function_b)().(funcs.function_c)()
);
""", options=lang_opts)

extractor = DynamicFunctionGraphExtractor()
for statement_node in sql_payload.statement_list_node.statement_list:
    extractor.visit(statement_node)

if "global" in extractor.graphs and not extractor.graphs["global"]:
    del extractor.graphs["global"]

print(json.dumps(extractor.graphs, indent=2))
