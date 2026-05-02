import networkx as nx
import matplotlib.pyplot as plt
import yaml

# Load the dependencies.yaml file
with open('bq/app/dependencies.yaml', 'r') as f:
    dependencies = yaml.safe_load(f)

# Create a directed graph
G = nx.DiGraph()

# Add nodes and edges to the graph
for task, deps in dependencies['dependencies'].items():
    G.add_node(task)
    for dep in deps:
        G.add_edge(dep, task)

# Remove orphans (nodes with no incoming or outgoing edges)
orphans = [node for node in G.nodes() if G.in_degree(node) == 0 and G.out_degree(node) == 0]
G.remove_nodes_from(orphans)

# Position the nodes in the graph using the multipartite layout
pos = nx.spring_layout(G)

# Draw the graph and save as SVG
plt.figure(figsize=(10, 6))
plt.axis('off')
nx.draw(G, pos, with_labels=True, node_color='lightblue', edge_color='gray')
plt.savefig('bq/app/dag.svg', format='svg')
