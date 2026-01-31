# Testing

## Quick Commands

- Full pipeline (unit + integration):

```bash
bash scripts/test/run_e2e.sh
```

- Build gates:

```bash
bash scripts/ci/check_untracked.sh
bash scripts/ci/check_readme_fresh.sh
```

## Test Layers

### Unit Tests

Each module has its own tests:

- `packages/cloudplayplus_core`: entity serialization/deserialization
- `packages/iterm2_host`: bridge + stream host skeleton
- `apps/android_client`: widget tests for pages/components

Run with:

```bash
flutter test
```

### Integration Tests

Located in `test/integration`.

- `bridge_integration_test.dart`: validates Python bridge invocation via mock scripts
- `settings_integration_test.dart`: validates StreamSettings JSON roundtrip

Run with:

```bash
pushd test/integration
flutter pub get
flutter test
popd
```

### E2E

The E2E script currently runs:

1. Setup mock scripts (`scripts/test/setup_iterm2_mock.sh`)
2. Unit tests for each module
3. Integration suite

Run with:

```bash
bash scripts/test/run_e2e.sh
```

## Notes

- Integration tests assume working directory is repository root. The suite adjusts cwd internally.
- WebRTC plugin calls are avoided in unit tests via `StreamHost(enableWebRTC: false)`.

