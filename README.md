# SAREVU Task 1 — ProtocolRegistry

Single-package Task 1 bundle with first-code layer and acceptance layer in one repo-shaped archive.

## Package layers
- `contracts/` — first code: contract, tests, deploy script
- project root files — Foundry config and repo setup
- `docs/audit-prep/` — audit and static-analysis placeholders
- `docs/acceptance/` — acceptance templates and execution records

## Canonical structure
This package uses the canonical `/contracts/...` layout.
Some earlier source materials and outside drafts referenced `src/...`; that path is treated as non-canonical for this Task 1 deliverable.

## First-time setup
```bash
make install
cp .env.example .env
```

## Verification flow
```bash
make build
make test
make fuzz
make coverage
make slither
```

## Acceptance rule
Close the current task fully, integrate it, update the package, and only then open the next task.

## Honesty note
This environment does not have Foundry or Slither installed, so this package is prepared from the specification and reviewed logic, but not executed here.
## Coverage policy

For Task 1 acceptance, coverage is measured on core contract logic only.

Included in the mandatory coverage target:
- `contracts/core/**`

Excluded from the mandatory coverage target:
- `contracts/script/**`

Rationale:
Deployment scripts are operational helpers and are not part of the protocol's core business logic. Coverage thresholds for acceptance apply to core contracts only.