# Xcode Cloud and TestFlight setup

Robin's steps, in order. Each says how to tell it worked.

1. **Pair the Apple TV.** In Xcode, Window > Devices and Simulators. On the TV, Settings > Remotes and Devices > Remote App and Devices. Choose Pair and enter the code. Turn on Developer Mode if asked. (Pairing steps are taken from an older Apple Help page and not re-confirmed for Xcode 27.)
   Worked when: the Apple TV is listed in Devices and Simulators as connected.
2. **Register the identifiers** `com.robrolabs.perch`, `com.robrolabs.perch.topshelf` and `group.com.robrolabs.perch` under Parapex Ltd (team 3TWLQK4535). Opening `Perch.xcodeproj` with automatic signing does this.
   Worked when: the identifiers appear under Certificates, Identifiers & Profiles, and Xcode shows no signing errors.
3. **Create the app record** in App Store Connect with bundle ID `com.robrolabs.perch`.
   Worked when: the app appears in My Apps.
4. **Create the workflow** from Xcode (Product > Xcode Cloud) and grant it the repo. Settings:
   - Scheme: `PerchApp`.
   - Start condition: branch changes on `main`.
   - Action: Archive, for tvOS.
   - Distribution: TestFlight internal testing only.
   - Environment: Xcode 27.2 if listed, else Latest Release.
   Worked when: the workflow is listed in App Store Connect under Xcode Cloud with these settings.
5. **Add yourself as an internal tester** in App Store Connect.
   Worked when: your Apple ID shows in the internal testing group.
6. **After merge**, confirm the build reached TestFlight, install it from the TestFlight app on the Apple TV, and confirm it opens to the wordmark. Record the build number.
   Worked when: the build is installed and the wordmark shows on launch.

Notes:

- From WP-08, when Nuke arrives, `Package.resolved` must be committed at `Perch.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`, because Xcode Cloud does not resolve packages automatically.
- TestFlight builds expire after 90 days.
