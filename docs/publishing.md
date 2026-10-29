# Preparing the GitHub repository

Release preparation for https://github.com/byizmysh/SWFence. The first release is a pre-release until real hardware acceptance is complete. Screenshots must not be committed or included in release archives.

1. Review the MIT license and public files. Keep README and INSTALL.md download links aligned with the target version. Set `packages/swfence/files/usr/share/swfence/repository` to `byizmysh/SWFence` before rebuilding packages; this supplies the LuCI footer link. The installer also records its actual repository in `/etc/swfence/repository`. No private device
   MACs or router credentials should be committed.
2. Create the repository and upload this directory as its root.
   Increment both package recipes' `PKG_RELEASE` for changed packages (including
   adding the final repository link), or advance the version consistently, so
   package managers can recognize the update.
3. Run the Test workflow. Run Build native packages manually and review both
   firmware-family artifacts. The packages contain only scripts/JS (`all`
   architecture); kernel dependencies must come from the user's own firmware feed.
4. Complete the hardware acceptance list in `docs/testing.md`. Keep the first
   publication marked pre-release until these checks have been completed.
5. Download the package artifacts into `dist/`, preserving these asset names:
   `swfence-24.10.ipk`, `luci-app-swfence-24.10.ipk`,
   `swfence-25.12.apk`, `luci-app-swfence-25.12.apk`.
6. Run `python3 scripts/build-release.py` to create the source archive, install bundle (when all four packages are present),
   installer, INSTALL.md and a single SHA256SUMS for all assets present in `dist/`.
7. Create/review a draft `v0.3.0` release and upload the complete assets.
   The optional Prepare draft release workflow creates only a source draft;
   native package assets must be added after their build/review.
8. Test the documented SSH download command against the draft's final public
   release URL after publication. Only then advertise installation as available.

The installer requires an explicit repository and exact semantic version tag.
It downloads only the selected package family and verifies each selected asset
against SHA256SUMS before invoking the package manager. The checksum manifest
is from the same release: trust still depends on the GitHub repository/release.
OpenWrt apk assets are unsigned local packages, so installation uses
`apk add --allow-untrusted` only for the two checksum-verified local files.

Never attach the old private network backup directory or a production UCI
configuration to the public repository.
