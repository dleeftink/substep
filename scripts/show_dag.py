import graphviz
import yaml

# 1. Load the dependencies.yaml file
with open('bq/app/dependencies.yaml', 'r') as f:
    data = yaml.safe_load(f)
    dependencies = data.get('dependencies', {})

# 2. Create a directed graph object
# rankdir='LR' makes it flow Left-to-Right; use 'TB' for Top-to-Bottom
dot = graphviz.Digraph('DAG', format='svg', graph_attr={'rankdir': 'LR'})

# 3. Add nodes and edges
for task, deps in dependencies.items():
    # Style the node (e.g., box with rounded corners)
    dot.node(task, shape='box', style='rounded')
    
    for dep in deps:
        dot.edge(dep, task)

# 4. Render to a file
# This creates 'bq/app/dag.svg' and 'bq/app/dag.gv'
# Set cleanup=True to delete the intermediate .gv file automatically
dot.render('bq/app/dag', cleanup=True)
