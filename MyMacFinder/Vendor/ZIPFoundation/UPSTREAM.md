# ZIPFoundation local compatibility patch

Upstream: https://github.com/weichsel/ZIPFoundation
Version: 0.9.20
Commit: 22787ffb59de99e5dc1fbfe80b19c97a904ad48d
License: MIT (see LICENSE). Source copyright headers are preserved.

The application includes a local source copy rather than editing SwiftPM's disposable checkout.
The package manifest targets the application's macOS 15 baseline and omits upstream's unrelated test resources.

Local change: Date+ZIP.swift interprets and writes DOS calendar fields in the system local time zone.
It uses localtime_r for independent thread-safe tm storage and mktime with tm_isdst = -1 for DST inference.
The upstream UTC conversions caused a +9h decode / -9h encode mismatch against macOS ZIP tools in Asia/Seoul.
This patch does not add extended timestamp fields or change the existing DOS two-second precision / year clamp.

Application interoperability tests cover Python-created DOS-only archives, browsing, extraction,
and application ZIP output read by Python and macOS ditto. Retain these checks when updating upstream.
