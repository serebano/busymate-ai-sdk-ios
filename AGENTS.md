# SDK repository ownership

This repository owns its OS SDK source, examples, packaging, CI and versioned releases.
Use an isolated named worktree/task branch. Preserve all existing lanes and changes.
Never modify an existing release/tag or frozen identity wire bridge. New bytes require a new SDK version.
The private product repository owns hosted chat/server behavior. busymate.ai publishes human integration guides and mirrors versioned artifacts; hashes must match this repository.
Only SDK source intended for customer distribution belongs here. No production keys, backend implementation or tenant credentials.
Before push validate manifests and OS build/sample. Land through protected PRs with sdk-check required. No admin bypass. Publish a versioned release only after successful checks; device permission dialogs require separate physical-device evidence.
