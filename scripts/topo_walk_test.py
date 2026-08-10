from zetasql.api import Parser, ASTNodeVisitor

class MyVisitor(ASTNodeVisitor):
    def visit_ASTFunctionCall(self, node) -> None:
        # Extract the function name from the identifier path
        # ZetaSQL joins path components (e.g., ['project', 'dataset', 'func'])
        func_name = ".".join([n.id_string for n in node.function.names]) # id_string
        
        print(f"Function Call Detected: {func_name}")
        
        # Filter for specific functions
        if func_name.upper() == "UPPER":
            print(f"  -> Found target function: {func_name}")
            
        self.descend(node)

    def visit_ASTPathExpression(self, node) -> None:
        # Extract identifiers like table names or columns (e.g., u.name)
        path_names = [n.id_string for n in node.names]
        print(f"Path Expression (Content): {'.'.join(path_names)}")
        self.descend(node)

    def visit_ASTIntLiteral(self, node) -> None:
        # Extract raw literal values
        print(f"Int Literal Value: {node.id_string}")
        self.descend(node)

    def default_visit(self, node) -> None:
        # Fallback to keep traversing the tree
        self.descend(node)

stmt = Parser.parse_statement_static("""
    SELECT (u.name).upper().lower()
""")

visitor = MyVisitor()
visitor.visit(stmt)
