from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions
import json

lang_opts = LanguageOptions.maximum_features()

class DependencyWalker(ASTNodeVisitor):
    def __init__(self):
        super().__init__()
        self.current_scope = "global"
        self.graphs = {}
        self.current_parent_call = None
        # Track hierarchical structural expressions (CTEs, Subqueries, Pipe statements)
        self.context_stack = []

    def _get_current_context(self) -> str:
        return self.context_stack[-1] if self.context_stack else "statement_body"

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

        # Capture target type name for CAST expressions
        if type(node).__name__ == "ASTType":
            if hasattr(node, "type_name") and getattr(node.type_name, "names", None):
                return ".".join([n.id_string for n in node.type_name.names if getattr(n, "id_string", None)])

        for attr_name in ("function_declaration", "function", "name", "method_name", "type"):
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
        context_pushed = False

        # 1. Scope Tracking (Functions / TVFs)
        if "FunctionStatement" in node_type or "TVFStatement" in node_type:
            is_scope_defining_node = True
            extracted_scope = self._dynamically_extract_name(node)
            self.current_scope = extracted_scope if extracted_scope else "unknown_function_definition"
            if self.current_scope not in self.graphs:
                self.graphs[self.current_scope] = []

        # 2. Structural/Block Segmentation (CTEs, Subqueries, Pipes)
        if "WithClauseEntry" in node_type:
            cte_name = getattr(getattr(node, "alias", None), "id_string", "unknown_cte")
            self.context_stack.append(f"cte:{cte_name}")
            context_pushed = True
        elif "PipeSelect" in node_type or "PipeCall" in node_type:
            self.context_stack.append("pipe_operator_transform")
            context_pushed = True
        elif "ExpressionSubquery" in node_type:
            self.context_stack.append("inline_subquery")
            context_pushed = True

        # 3. Identify function calls and Casts
        is_function_call = node_type in (
            "ASTFunctionCall", "ASTTableValuedFunctionCall", "ASTTVFCall", 
            "ASTTVF", "ASTTVFArgument", "ASTDotFunctionCall", "ASTMethodCall"
        )
        
        is_cast = (node_type == "ASTCastExpression")

        saved_parent_call = self.current_parent_call

        if is_function_call or is_cast:
            if is_cast:
                target_type = self._dynamically_extract_name(node)
                call_name = f"cast_to_{target_type.lower()}" if target_type else "cast"
            else:
                call_name = self._dynamically_extract_name(node)

            if call_name:
                if self.current_scope not in self.graphs:
                    self.graphs[self.current_scope] = []

                # Embed structural context directly into the extraction lineage metadata
                current_ctx = self._get_current_context()

                if self.current_parent_call and self.current_parent_call != call_name:
                    edge = {
                        "caller": self.current_parent_call, 
                        "callee": call_name,
                        "context": current_ctx
                    }
                    if edge not in self.graphs[self.current_scope]:
                        self.graphs[self.current_scope].append(edge)
                else:
                    edge = {
                        "caller": call_name, 
                        "callee": None,
                        "context": current_ctx
                    }
                    if edge not in self.graphs[self.current_scope]:
                        self.graphs[self.current_scope].append(edge)

                self.current_parent_call = call_name

        # 4. Descend down AST
        self.descend(node)

        # 5. Cleanup Node State On Exit
        self.current_parent_call = saved_parent_call

        if context_pushed:
            self.context_stack.pop()

        if is_scope_defining_node:
            self.current_scope = previous_scope


# Complex Edge Verification Payload
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
