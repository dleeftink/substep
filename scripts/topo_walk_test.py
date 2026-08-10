from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions, AnalyzerOptions

# 1. Enable pipe syntax and maximum features
lang_opts = LanguageOptions.maximum_features()

# Test visistor
class MyVisitor(ASTNodeVisitor):
    def visit_ASTFunctionCall(self, node) -> None:
        # Resolve the function identifier safely using .id_string
        func_name = ".".join([n.id_string for n in node.function.names])
        print(f"Function Call Detected: {func_name}")
        
        # if func_name.upper() == "UPPER":
        #    print(f"  -> Found target function: {func_name}")
            
        self.descend(node)

    def visit_ASTTableExpression(self, node) -> None:
        path_names = [n.id_string for n in node.names]
        print(f"Path Expression (Content): {'.'.join(path_names)}")
        self.descend(node)

    def visit_ASTTVF(self, node) -> None:
       
        print(f"Table valued function (Content): {node.name}")
        self.descend(node)

    # def visit_ASTIntLiteral(self, node) -> None:
    #     print(f"Int Literal Value: {node.id_string}")
    #     self.descend(node)

    def default_visit(self, node) -> None:
        self.descend(node)

# Comprehensive inspection
class GeneralInspectorVisitor(ASTNodeVisitor):
    def default_visit(self, node) -> None:
        node_type = type(node).__name__
        print(f"\n=== Inspecting Node: {node_type} ===")
        
        # 1. Native ZetaSQL Tree Visualisation
        # This shows the entire inner schema of the C++ node object safely
        if hasattr(node, "debug_string"):
            print("[ZetaSQL Native Debug]")
            # Indent lines for readability
            indented = "\n".join(f"  {line}" for line in node.debug_string().strip().split("\n"))
            print(indented)
            
        # 2. Python Dynamic Property/Attribute reflection
        # Safely fetches all exposed Python bindings, attributes, and methods
        print("[Python Attributes available]")
        attributes = [
            attr for attr in dir(node) 
            if not attr.startswith("_") and attr not in ["descend", "visit", "default_visit", "debug_string"]
        ]
        
        for attr in attributes:
            try:
                val = getattr(node, attr)
                # Avoid flooding the console with bound methods or giant child arrays
                if not callable(val) and not isinstance(val, (list, tuple)):
                    print(f"  - {attr}: {val}")
                elif isinstance(val, (list, tuple)):
                    print(f"  - {attr}: <Sequence with {len(val)} elements>")
            except Exception as e:
                print(f"  - {attr}: Error reading ({e})")

        self.descend(node)

# Prints all named things
class ASTDump(ASTNodeVisitor):
    def __init__(self):
        super().__init__()
        self.depth = 0

    def default_visit(self, node) -> None:
        node_type = type(node).__name__
        indent = "  " * self.depth
        
        # 1. Dynamically try to find name/content identifiers
        content = None
        
        # Strategy A: Check for direct identifier string
        if hasattr(node, "id_string") and node.id_string:
            content = f"id_string='{node.id_string}'"
        # Strategy B: Check for raw image string
        elif hasattr(node, "image") and node.image:
            content = f"image='{node.image}'"
        # Strategy C: Check for a function or name path expression nested inside
        elif hasattr(node, "function") and hasattr(node.function, "names"):
            names = [n.id_string for n in node.function.names if hasattr(n, "id_string")]
            content = f"function_path='{'.'.join(names)}'"
        elif hasattr(node, "name") and hasattr(node.name, "names"):
            names = [n.id_string for n in node.name.names if hasattr(n, "id_string")]
            content = f"name_path='{'.'.join(names)}'"
        # Strategy D: Check if it's a raw path expression list itself (e.g. table/column paths)
        elif hasattr(node, "names"):
            try:
                names = [n.id_string for n in node.names if hasattr(n, "id_string")]
                if names:
                    content = f"path='{'.'.join(names)}'"
            except Exception:
                pass

        # Print out the structured row
        content_str = f" | {content}" if content else ""
        print(f"{indent}• {node_type}{content_str}")
        
        # Descend deeper while managing indent levels
        self.depth += 1
        self.descend(node)
        self.depth -= 1

# WIP filter (prints out of order)
class FunctionFilterVisitor(ASTNodeVisitor):
    def __init__(self, target_filter: str = "UPPER"):
        super().__init__()
        self.target_filter = target_filter.upper()

    def _check_and_print(self, category: str, func_name: str) -> None:
        """Helper to uniformise console printing and filtering."""
        is_match = func_name.upper() == self.target_filter
        match_flag = " [MATCHED FILTER]" if is_match else ""
        print(f"[{category}] Found: {func_name}{match_flag}")

    def visit_ASTTVF(self, node) -> None:
        """Catches Table-Valued Functions (e.g., GAP_FILL)."""
        if hasattr(node, "name") and hasattr(node.name, "names"):
            func_name = ".".join([n.id_string for n in node.name.names if hasattr(n, "id_string")])
            self._check_and_print("Table-Valued Function", func_name)
        
        # Must descend to find nested expressions inside arguments
        self.descend(node)

    def visit_ASTFunctionCall(self, node) -> None:
        """Catches Scalar, Aggregate, and Dot-Chained Functions (e.g., lower, upper, SUM)."""
        if hasattr(node, "function") and hasattr(node.function, "names"):
            func_name = ".".join([n.id_string for n in node.function.names if hasattr(n, "id_string")])
            self._check_and_print("Standard/Scalar Function", func_name)
            
        # Must descend because dot-chained functions nest inside each other!
        # Descending ensures we uncover 'upper' underneath 'lower'.
        self.descend(node)

    def default_visit(self, node) -> None:
        self.descend(node)

# 3. Use parse_statement (not parse_statement_static) and pass the options
script_node = Parser.parse_script_static("""
    with init as (
      SELECT (user_id).upper().lower(), SUM(revenue)
      FROM GAP_FILL(TABLE series, microsecond, 1000)
    )
    select * from init;

    with next as (
      FROM GAP_FILL(TABLE series, microsecond, 1000)
      |> SELECT (user_id).upper().lower(), SUM(revenue)
    )

    select * from next;
""", options=lang_opts)

# Visit and execute
visitor = FunctionFilterVisitor()
# visitor.visit(script_node)

for statement_node in script_node.statement_list_node.statement_list:
    visitor.visit(statement_node)
