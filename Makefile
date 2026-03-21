install:
	forge install OpenZeppelin/openzeppelin-contracts --no-commit
	forge install foundry-rs/forge-std --no-commit

build:
	forge build

test:
	forge test --match-contract ProtocolRegistryTest -vvv

test-p0:
	forge test --match-test 'test_T1_02|test_T1_05|test_T1_07|test_T1_09|test_T1_10|testFuzz_T1_19' -vvv

fuzz:
	forge test --match-test testFuzz_T1_19_BelowFloorAlwaysReverts --fuzz-runs 10000 -vv

coverage:
	forge coverage

slither:
	slither contracts/core/ProtocolRegistry.sol > docs/audit-prep/slither-registry.txt
