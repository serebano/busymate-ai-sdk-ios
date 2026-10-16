# Changelog

## 1.0.2

Release packaging: the microphone adapter source (`BusymateMicrophone.swift`, adapter 1.0.0, wire 1, sha256 `a99ae81eb1ac2bf75d268724e94120e3953eb793a10321f16430d5c6594859a8`) is attached to every GitHub release and listed in `SHA256SUMS`; docs link the release, not busymate.ai. No SDK code change; native source hashes are unchanged. Versions 1.0.0 and 1.0.1 stay immutable. (refs serebano/busymate-ai-src#2156)

## 1.0.1

Fix the example application's saved project format to Xcode 15 (`objectVersion 60`) by explicitly configuring XcodeGen, instead of the newer default format used in 1.0.0. Document the actual validated Xcode 26.6/build 17F113 toolchain and add a format regression guard. Native identity/microphone sources and their hashes remain unchanged. Version 1.0.0 stays immutable.

## 1.0.0

First independent OS distribution: existing identity v1 bridge, frozen identity v2 bridge build 2.0.0, and microphone adapter 1.0.0. Identity source bytes are unchanged. Hosted chat receives updates separately; your native app release is needed to install or upgrade native SDK code.
