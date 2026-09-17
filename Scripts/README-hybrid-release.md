# Hybrid release flow

Local Mac builds the DMG/zip; CI only creates the GitHub Release with generated notes when a version tag is pushed. No notarize and no CI binary build.

1. **Build the DMG (and/or zip) locally** on the Mac mini.
2. **Tag and push** a version tag (`v*`), e.g. `git tag v1.1.0 && git push origin v1.1.0`.
3. **CI creates the release** (`.github/workflows/release-on-tag.yml`) with generated notes — no binaries.
4. **Attach the asset(s)** with `Scripts/attach-release-asset.sh`:

   ```bash
   Scripts/attach-release-asset.sh v1.1.0 ./path/to/ScribeFlowPro-1.1.0.dmg
   # or multiple:
   Scripts/attach-release-asset.sh v1.1.0 ./path/to/ScribeFlowPro-1.1.0.dmg ./path/to/ScribeFlowPro-1.1.0.zip
   ```

Existing Latest release is **v1.0.0-dmg.20260727**. This automation does not republish or replace it; a new `v*` tag is required for a new release.
