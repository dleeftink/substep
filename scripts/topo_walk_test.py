from zetasql.api import Parser, ASTNodeVisitor
from zetasql.types import LanguageOptions, AnalyzerOptions

# 1. Enable pipe syntax and maximum features
lang_opts = LanguageOptions.maximum_features()

class MyVisitor(ASTNodeVisitor):
    def visit_ASTFunctionCall(self, node) -> None:
        # Resolve the function identifier safely using .id_string
        func_name = ".".join([n.id_string for n in node.function.names])
        print(f"Function Call Detected: {func_name}")
        
        if func_name.upper() == "UPPER":
            print(f"  -> Found target function: {func_name}")
            
        self.descend(node)

    def visit_ASTPathExpression(self, node) -> None:
        path_names = [n.id_string for n in node.names]
        print(f"Path Expression (Content): {'.'.join(path_names)}")
        self.descend(node)

    # def visit_ASTIntLiteral(self, node) -> None:
    #     print(f"Int Literal Value: {node.id_string}")
    #     self.descend(node)

    def default_visit(self, node) -> None:
        self.descend(node)

# 3. Use parse_statement (not parse_statement_static) and pass the options
stmt = Parser.parse_statement_static("""
select (dat).left(2) from (
  FROM input |> select (u.name).upper().lower() as dat
)
""", options=lang_opts)

# Visit and execute
visitor = MyVisitor()
visitor.visit(stmt)
