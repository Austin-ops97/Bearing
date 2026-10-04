# Bearing

Bearing is a native iPhone and iPad personal operations and situational-awareness system.

## Current scope

The current foundation includes the native adaptive application shell, SwiftData domain model, SITREP, Day/Week/Month planning, capacity calculations, local calendar records, actions and waiting workflows, people, operational assets, routines, log, local search, and universal capture with a review-before-commit flow.

Bearing also includes the local foreground foundation for Voice & Verbal Awareness. It uses Apple's dynamically discovered speech voices and provides priority ordering, critical interruption, duplicate cooldowns, output modes, spoken-category controls, verbal-detail levels, and temporary mute. Background/system announcements, voice milestone capture, and Playbook speech remain intentionally staged with their corresponding product phases.

Development-only sample content is inserted for SwiftUI previews and debug builds only. Release builds start with an empty private store.

## Generate and build

The checked-in Xcode project is generated from `project.yml` with XcodeGen. Open `Bearing.xcodeproj` in Xcode. The app targets iOS 18 or newer and supports iPhone and iPad.
