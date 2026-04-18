# AGENTS.md: The LithePG Development Squad

## Orchestrator: Superset
- **Role:** Worktree management and agent isolation.
- **Workflow:** Using `superset.sh` to parallelize UI and Logic development.

## Implementation: Claude Code
- **Role:** Senior Swift Engineer & Principal Data Architect.
- **Tasks:** Writing SwiftUI views, implementing the Postgres driver logic, ensuring type safety, schema analysis, architectural reviews, and local AI model integration strategies.
- **Mode:** Primarily used in `PLAN` then `ACT` mode within Superset worktrees.
- **Scope:** Handles both implementation details and the "Big Picture," including complex SQL optimizations.

## Collaboration Protocol
1. **Claude** analyzes the requirement, proposes the architecture, and implements the Swift code in a Superset worktree.
2. **Superset** ensures the git state is clean and ready for the next iteration.
