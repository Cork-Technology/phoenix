# Changelog

## 1.4.0-rc.1

### Compatibility and migration

This candidate is not ABI-compatible with 1.3.0-rc.1. The version label must not be interpreted as a promise of a drop-in upgrade.

- `Market` expands from eight fields to ten, adding swap and unwind-swap fees. Regenerate bindings for pool creation, identifier derivation, the `market(bytes32)` result, and share-factory deployment. An unchanged getter selector does not make its expanded return tuple compatible.
- Fees are fixed when a pool is created and participate in its identifier. Derive identifiers from the complete market tuple; do not reuse identifiers calculated with the former tuple.
- The pool manager and controller fee setters are removed, as is the controller's fee-manager role getter. Fee-update event signatures are removed and `MarketCreated` adds the fee fields. Update governance tooling and indexers accordingly.
- Each creation-time fee must be strictly below `100 ether` (100%); equality is rejected. Percentage values use 18 decimals: `1 ether` means 1%, not 100%. Integrators must evaluate their fee assumptions; the source label does not certify economic safety.

### Added

- Pool shares support `permit(address,address,uint256,uint256,bytes)` for ERC-1271 contract signers, alongside the existing ERC-2612 signature form. Both overloads share the same nonce sequence and signing domain. A successful permit through either form consumes the next nonce for both.

### Deprecated

No staged deprecation is introduced. The removed fee-management surface is a breaking removal, not a deprecated alias. Publishing this source does not retire or change any existing deployment or withdraw its support.

### Consumer tree

The tree includes core and periphery sources, public dependency gitlinks, consumer tests, build configuration and a two-profile CI workflow. Operational scripts, deployment-specific configurations and receipts, internal development tooling, deployment-only tests and standalone diagnostic suites are excluded. The environment template is omitted; the smoke guide describes explicit caller-provided configuration. The lockfile includes the Safe test dependency and all dependency URLs use HTTPS.

Safe permit fixtures compile independently without IR while Phoenix production contracts and tests retain via-IR compilation. Both CI test profiles remain enabled, with the real pinned Safe implementation and fallback handler deployed from build artifacts. Contract sources and dependency revisions are unchanged by this test-harness correction.

### Assurance

The source version is recorded in package metadata; contracts do not report a component version getter. The EIP-712 domain version remains a separate identifier. This changelog makes no audit, deployment equivalence, notice completion or production-readiness claim.
