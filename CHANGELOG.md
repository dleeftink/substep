# Changelog

Changes and commits for the 'substep' namespace.
All notable changes to this project will be documented in this file.

<!-- The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).-->

## [0.1.2b] - 2026-05-02

### Added
- **Build and installation infrastructure**:
  - `scripts/build_tree.py`: Script to visualize and inspect DAG dependencies.
  - Added tree builders for package DAG analysis.

### Changed
- **Build and installation infrastructure**:
  - Improved dependency tree rendering directly into `install.sql`.
  - Removed unused features.

## [0.1.2] - 2026-04-27

### Changed
- **Build and installation infrastructure**:
  - Enhanced `scripts/topo_sort.py` with original function name casing retention in output while maintaining lowercase matching for consistency.
  - Improved dependency tracking in `install-order.txt` with structured array notation for better readability and parseability.
  - Added minification options to `scripts/build_install.sh` for optimized SQL output.
  - Better handling of source code whitespace and comment stripping during installation.
- Updated namespace version numbers to 0.1.2 for all namespaces.

## [0.1.1] - 2026-04-27

### Added
- **Build and installation infrastructure**:
  - `scripts/topo_sort.py`: Topological sorting script for SQL function dependencies with depth-based tie-breaking.
  - `scripts/build_install.sh`: Automated build script to concatenate SQL files in correct dependency order.
  - `bq/app/install.sql`: Pre-built consolidated installation file with all functions in dependency order.
  - `bq/app/install-order.txt`: Dependency order manifest for reference and reproducibility.

### Changed
- Standardized camelCase JSON function naming across all files and documentation (json prefix in lowercase).
- Updated namespace version numbers to 0.1.1 for affected namespaces (get, lay, map, fix, use).

## [0.1.0] - 2026-04-26

### Added
- **cue namespace**:
  - `cue.meta()`: Metadata function for the cue namespace.
  - `cue.objectMetadataInterface()`: Interface for object metadata in cue operations.

- **def namespace**:
  - `def.meta()`: Metadata function for the def namespace.

- **fix namespace**:
  - `fix.meta()`: Metadata function for the fix namespace.
  - `fix.emptyJsonKeys()`: Fixes empty JSON keys in objects.
  - `fix.keyFragment()`: Fixes key fragments in JSON structures.
  - `fix.shallowItems()`: Applies shallow item fixes.
  - `fix.unsafeJson()`: Handles unsafe JSON corrections.

- **get namespace**:
  - `get.meta()`: Metadata function for the get namespace.
  - `get.characterIndices()`: Extracts character indices from strings.
  - `get.keyFragment()`: Retrieves key fragments from JSON.
  - `get.nearestJsonKeyIndex()`: Finds the nearest JSON key index.
  - `get.objectBoundaries()`: Determines object boundaries in JSON.
  - `get.objectFragment()`: Extracts object fragments.
  - `get.objectMetadata()`: Retrieves metadata for objects.
  - `get.safeJson()`: Safely serializes structs to JSON with escaping.
  - `get.stringifiedJsonFromStruct()`: Converts structs to JSON strings (renamed from `stringifiedStruct`).
  - `get.unrolled()`: Unrolls nested JSON structures.

- **lay namespace**:
  - `lay.meta()`: Metadata function for the lay namespace.
  - `lay.shallowItems()`: Handles shallow item layouts.
  - `lay.unsafeJson()`: Processes unsafe JSON layouts.

- **map namespace**:
  - `map.meta()`: Metadata function for the map namespace.
  - `map.objectContainment()`: Maps object containment relationships.
  - `map.unsafeJson()`: Applies unsafe JSON mappings.

- **try namespace**:
  - `try.meta()`: Metadata function for the try namespace.

- **use namespace**:
  - `use.meta()`: Metadata function for the use namespace.
  - `use.parser()`: Parses complex SQL objects into JSON.
  - `use.unroller()`: Unrolls JSON into linked parent-child structures.

### Changed
- Renamed `get/stringifiedStruct.sql` to `get/stringifiedJsonFromStruct.sql` for better clarity.
- Updated descriptions in `lay.shallowItems()` and `fix.shallowItems()` for improved clarity.
- Standardized camelCase JSON function naming across files and documentation.
- Standardized variable and parameter names in `map.unsafeJson()`, `lay.unsafeJson()`, and `fix.unsafeJson()` for consistency.

### Fixed
- Corrected variable names in `unsafeJson` functions across namespaces for better readability.
- Fixed parameter names in `unsafeJson` functions for clarity.

### Documentation
- Comprehensive updates to `README.md` for clarity on the substep namespace, SQL object usage, and examples.
- Added repository URLs to all meta functions.