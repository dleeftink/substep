from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions
import json

lang_opts = LanguageOptions.maximum_features()

class DependencyWalker(ASTNodeVisitor):
    def __init__(self):
        super().__init__()
        self.current_scope = "global"
        self.graphs = {}
        # Keeps track of the active operational parent function call node
        self.current_parent_call = None

    def _dynamically_extract_name(self, node) -> str:
        if node is None:
            return ""
        if getattr(node, "name_path", None):
            return node.name_path
        if getattr(node, "function_path", None):
            return node.function_path
        if getattr(node, "id_string", None):
            return node.id_string
        if getattr(node, "image", None):
            return node.image

        for attr_name in ("function_declaration", "function", "name", "method_name"):
            child = getattr(node, attr_name, None)
            if child:
                res = self._dynamically_extract_name(child)
                if res:
                    return res

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

        # 1. Scope Tracking
        if "FunctionStatement" in node_type or "TVFStatement" in node_type:
            is_scope_defining_node = True
            extracted_scope = self._dynamically_extract_name(node)
            self.current_scope = extracted_scope if extracted_scope else "unknown_function_definition"
            if self.current_scope not in self.graphs:
                self.graphs[self.current_scope] = []

        # 2. Identify if this specific node represents a function call
        is_function_call = node_type in (
            "ASTFunctionCall", "ASTTableValuedFunctionCall", "ASTTVFCall", 
            "ASTTVF", "ASTTVFArgument", "ASTDotFunctionCall", "ASTMethodCall"
        )

        saved_parent_call = self.current_parent_call

        if is_function_call:
            call_name = self._dynamically_extract_name(node)
            if call_name:
                if self.current_scope not in self.graphs:
                    self.graphs[self.current_scope] = []

                # LINEAGE LINKAGE: If a parent call frame exists above us,
                # then this current node is a nested sub-dependency (callee) of that parent
                if self.current_parent_call and self.current_parent_call != call_name:
                    edge = {"caller": self.current_parent_call, "callee": call_name}
                    if edge not in self.graphs[self.current_scope]:
                        self.graphs[self.current_scope].append(edge)
                else:
                    # Root level call inside this expression scope block
                    edge = {"caller": call_name, "callee": None}
                    if edge not in self.graphs[self.current_scope]:
                        self.graphs[self.current_scope].append(edge)

                # Set this function as the active parent context for any child nodes beneath it
                self.current_parent_call = call_name

        # 3. Structural Traversal (Pre-order frame propagation, bottom-up resolution)
        self.descend(node)

        # 4. Clean up state variables on exit
        self.current_parent_call = saved_parent_call

        if is_scope_defining_node:
            self.current_scope = previous_scope


# Complex Edge Verification Payload (Combined Dot Chains + Standard Nesting) 
# Also adds a circular dependency for later handling
sql_payload = Parser.parse_script_static("""
CREATE or replace FUNCTION funcs.function_a(inp ANY TYPE) AS ((
  SELECT (inp).(funcs.function_b)() 
));

CREATE or replace FUNCTION funcs.function_b(inp ANY TYPE) AS ((
  SELECT (inp).(funcs.function_a)()
));

CREATE OR REPLACE TABLE FUNCTION custom_namespace.analytical_hub(input TABLE<val int64>) AS (
  with init as (
    SELECT * FROM input
    |> call external_namespace.table_function()
    |> select (val).(funcs.function_b)() as new_val
    |> WHERE True
    |> SELECT 
        funcs.nested_outer( (new_val).(funcs.function_a)().(funcs.function_b)().(funcs.function_c)() ) out_val,
        array(select (v).(funcs_function_c)() from unnest(generate_array(0,5)) v) as arr
  )

  select cast(out_val as string).upper() exit_val, (arr).array_slice(0,2) new_arr from init
);
""", options=lang_opts)

extractor = DependencyWalker()
for statement_node in sql_payload.statement_list_node.statement_list:
    extractor.visit(statement_node)

if "global" in extractor.graphs and not extractor.graphs["global"]:
    del extractor.graphs["global"]

print(json.dumps(extractor.graphs, indent=2))
