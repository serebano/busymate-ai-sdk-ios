# Changelog

## 1.0.1

Fix the example application's saved project format to Xcode 15 (`objectVersion 60`) by explicitly configuring XcodeGen, instead of the newer default format used in 1.0.0. Document the actual validated Xcode 26.6/build 17F113 toolchain and add a format regression guard. Native identity/microphone sources and their hashes remain unchanged. Version 1.0.0 stays immutable.

## 1.0.0

First independent OS distribution: existing identity v1 bridge, frozen identity v2 bridge build 2.0.0, and microphone adapter 1.0.0. Identity source bytes are unchanged. Hosted chat receives updates separately; your native app release is needed to install or upgrade native SDK code.
