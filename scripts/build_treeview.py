import yaml

with open('bq/app/dependencies.yaml', 'r') as f:
    data = yaml.safe_load(f)
    deps_map = data.get('dependencies', {})

def get_requirements(node, depth=1):
    lines = [f'{"    " * depth}"{node}"']
    # The 'children' here are the dependencies listed in the YAML for this task
    dependencies = deps_map.get(node, [])
    for dep in dependencies:
        lines.extend(get_requirements(dep, depth + 1))
    return lines

# Identify "End Products" (Tasks that nothing else depends on)
all_requirements = {req for reqs in deps_map.values() for req in reqs}
final_outputs = [task for task in deps_map.keys() if task not in all_requirements]

output = ["treeView-beta"]
for task in final_outputs:
    output.extend(get_requirements(task))

print("\n".join(output))
