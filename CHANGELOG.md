# Changelog

Changes and commits for the 'substep' namespace.
All notable changes to this project will be documented in this file.

<!-- The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).-->

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