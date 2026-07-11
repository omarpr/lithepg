# Schema Graph Design

**Status:** Approved (in-app graph, force-directed, compact nodes with inspector, ships in the beta)

## Goal

An Obsidian-style graph of the connected database inside LithePG: tables as nodes, foreign keys as edges, columns and types in an inspector. Read-only, local metadata only, no new dependencies.

## Scope

- Derive the graph from the `DatabaseSchema` the app already loads on refresh.
- Force-directed layout with pan, zoom, node dragging and click selection.
- Compact nodes (table name, column count). Selecting a node highlights its edges and shows columns with types and PK/FK badges in an inspector panel.
- Entry points: a Graph button in the schema sidebar and `⇧⌘G`. Presented as a large resizable sheet.

Out of scope: editing schema, running SQL from the graph, persisting layout, exporting images, Obsidian file export.

## Architecture

Four units, following the existing seam pattern (pure Core model, headless presentation, SwiftUI view):

1. **`SchemaGraph`** (Core): nodes (`schema.table`, kind, column count) and edges from `DatabaseSchema.foreignKeys` (child to parent, self-references flagged). Pure, `Sendable`, `Equatable`.
2. **`ForceLayout`** (Core): deterministic simulation. Seeded initial positions from stable node-id hashes, fixed-timestep `step()` applying edge springs, node repulsion, centering pull and damping. Same input always settles to the same positions. `isSettled` when peak velocity drops under a threshold.
3. **`SchemaGraphPresentation`** (App): maps graph, layout and selection to drawable node/edge primitives, inspector rows (column, type, PK and FK badges), highlight states, accessibility labels and empty states.
4. **`SchemaGraphView`** (App): SwiftUI `Canvas` in a sheet. `TimelineView` ticks only while unsettled or dragging. Gestures for pan, zoom, select and drag-to-pin.

## Guardrails

- Metadata only. No SQL execution, no network, no data rows, no credentials anywhere near the graph.
- Schemas over 300 tables skip physics and use a static grid layout so the canvas stays responsive.
- Empty schema and no-FK cases render friendly empty states instead of a blank canvas.

## Testing

- Core: FK-to-edge derivation (cross-schema, composite keys, self-references, views included as nodes), layout determinism, settling behavior and the grid fallback threshold.
- App: presentation mapping (selection highlight sets, inspector rows and badges, empty states) against the seeded dogfood schema fixture.
- No live database needed for any graph test.
