# Package Map

## Layer A — First Code
- `contracts/core/ProtocolRegistry.sol`
- `contracts/test/ProtocolRegistryTest.t.sol`
- `contracts/script/DeployProtocolRegistry.s.sol`
- `forge.toml`
- `remappings.txt`
- `.gitignore`
- `.env.example`
- `Makefile`
- `README.md`

## Layer B — Verification
- `VERIFICATION_STATUS.md`
- `docs/audit-prep/README.md`
- `docs/audit-prep/slither-registry.txt`

## Layer C — Acceptance
- `docs/acceptance/README.md`
- `docs/acceptance/fuzz-report.txt`
- `docs/acceptance/coverage-report.txt`
- `docs/acceptance/acceptance-note.md`
- `docs/acceptance/change-note.md`

## Rule
One task should live in one zip when it is the same code package and the same acceptance package.
Open a new zip only when a new task or a new phase begins.
