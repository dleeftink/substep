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
        self.context_stack = []
        self.context_counters = {}

        # 1. High-level Strategy Configuration
        self.STRATEGY_MAP = {
            "is_scope": lambda name, node: "Statement" in name or name.startswith("ASTCreate"),
            "is_context": lambda name, node: any([
                name.startswith("ASTPipe"), 
                "Subquery" in name, 
                "WithClauseEntry" in name,
                hasattr(node, "query")  # Structural signature of an isolated execution block
            ])
        }

        self.OPERATION_PROCESSORS = {
            **{node: self._dynamically_extract_name  for node in (
                "ASTFunctionCall", "ASTTableValuedFunctionCall", "ASTTVFCall", 
                "ASTTVF", "ASTTVFArgument", "ASTDotFunctionCall", "ASTMethodCall",
                "ASTAnalyticFunctionCall"
            )},
            # "ASTCastExpression": lambda n: f"cast_to_{self._dynamically_extract_name(n).lower()}" if self._dynamically_extract_name(n) else "cast",
            # "ASTExtractExpression": lambda n: "extract",
            # "ASTCaseValueExpression": lambda n: "case_statement",
            # "ASTCaseNoValueExpression": lambda n: "case_statement"
            # "ASTCoalesceExpression": lambda n: "coalesce",
            # "ASTInExpression": lambda n: "in_membership",
            # "ASTLikeExpression": lambda n: "like_pattern",
            # "ASTBetweenExpression": lambda n: "between_range"
        }

    def _dynamically_extract_name(self, node) -> str:
        """Safely extracts identifiers and nested paths from AST nodes without deep recursion."""
        if node is None:
            return ""

        # Direct explicit lookups
        for attr in ("name_path", "function_path", "id_string", "image"):
            val = getattr(node, attr, None)
            if val:
                return str(val)

        # Handle explicit Type specifications or structural lists (e.g. ASTType, ASTPathExpression)
        for attr in ("names", "type_name"):
            nested = getattr(node, attr, None)
            if nested:
                if hasattr(nested, "names"):  # Handle nested type paths
                    nested = nested.names
                try:
                    segments = [n.id_string for n in nested if getattr(n, "id_string", None)]
                    if segments:
                        return ".".join(segments)
                except Exception:
                    pass

        # Clean, explicit bubble-up attributes instead of an open loop
        for bubble_attr in ("function_declaration", "function", "name", "method_name", "type"):
            child = getattr(node, bubble_attr, None)
            if child:
                res = self._dynamically_extract_name(child)
                if res:
                    return res
                
        return ""

    def _generate_unique_context(self, base_name: str) -> str:
        # Normalise class names to clean label tokens (e.g., ASTPipeSelect -> pipe_select)
        token = base_name.replace("AST", "").lower()
        self.context_counters[token] = self.context_counters.get(token, 0) + 1
        return f"{token}#{self.context_counters[token]}"

    def _get_current_context(self) -> str:
        return self.context_stack[-1] if self.context_stack else "statement_body"

    def _resolve_context_label(self, node_type: str, node) -> str:
        """Dynamically derives contextual labels without hardcoding strings."""
        if "WithClauseEntry" in node_type:
            cte_name = getattr(getattr(node, "alias", None), "id_string", "unknown_cte")
            return f"cte:{cte_name}"
        return node_type

    def visit(self, node) -> None:
        if node is None:
            return

        node_type = type(node).__name__
        previous_scope = self.current_scope
        context_pushed = False
        is_scope_defining_node = False
        saved_parent_call = self.current_parent_call

        # 1. Structural Reflection Boundary Check
        if self.STRATEGY_MAP["is_scope"](node_type, node):
            is_scope_defining_node = True
            extracted_scope = self._dynamically_extract_name(node)
            self.current_scope = extracted_scope if extracted_scope else "unknown_function"

        if self.STRATEGY_MAP["is_context"](node_type, node):
            label_base = self._resolve_context_label(node_type, node)
            self.context_stack.append(self._generate_unique_context(label_base))
            context_pushed = True

        # 2. Process Operations
        if node_type in self.OPERATION_PROCESSORS:
            call_name = self.OPERATION_PROCESSORS[node_type](node)
            if call_name:
                self.graphs.setdefault(self.current_scope, [])
                current_ctx = self._get_current_context()

                edge = {
                    "caller": self.current_parent_call if (self.current_parent_call and self.current_parent_call != call_name) else call_name,
                    "callee": call_name if (self.current_parent_call and self.current_parent_call != call_name) else None,
                    "context": current_ctx
                }
                if edge not in self.graphs[self.current_scope]:
                    self.graphs[self.current_scope].append(edge)
                self.current_parent_call = call_name

        # 3. Traversal and Cleanup
        self.descend(node)
        self.current_parent_call = saved_parent_call
        if context_pushed:
            self.context_stack.pop()
        if is_scope_defining_node:
            self.current_scope = previous_scope


# Verification execution
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

print(json.dumps(extractor.graphs, indent=2))
