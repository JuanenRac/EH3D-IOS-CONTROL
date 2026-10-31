# Changelog

All notable changes to this project are documented here.

## [Unreleased]

- **The spindle of the machine, the same as the Android app:** the page of a machine shows which spindle it carries (the original one or the one with a variable-frequency drive, or none), its limits and the top speed the node should be set to; an administrator chooses the spindle and what the server does with a job that asks for more (refuse it, or let it through cut down to the top of the spindle). A job shows the excesses it was let through with, the tools that were switched off for it and the holes or paths already done that it leaves out. The messages for a job refused by the spindle or left with nothing to do are in the eight languages. Choosing a drilling job, a routing job or both, and switching tools off, is not here: the app does not prepare jobs.
- **Numbers with decimals in the phrases:** a phrase with `%.1f` or `%.3f` is now filled with that many decimals (before, the hole was left as it was written).

## [0.0.2] - The ring of LEDs and the quality check, and the first screens of the other apps

- **The ring of LEDs and the quality check, the same as the Android app:** the page of a machine has the ring of LEDs of the head (off and three levels) and a Quality check card with the verdict as big as a sign, the findings, the profile and the calibration of the scale; the last check of the machine is shown when the page opens. 48 phrases in the seven tables of languages.
- **The first screens in the manner of the other apps of the suite:** the splash with the mark and the name, the wait while the session of the last time is restored, and the sign-in with icons, the eye to show the password and the note about what is kept on the phone.

## [0.0.1] - The first version: the machines, the stop, the job in 2D and 3D and the drill head

- **The machines of the workshop in real time:** the fleet as EH3D-SERVER reports it (free, working, waiting for the operator), with the job of each machine, its progress, the steps and holes done and the time left, read every second and a half while the app is in sight; a notice when a machine waits for the operator or stops.
- **The emergency stop:** a red button for one machine and another for all of them; each asks a second time before it cancels the running job through the server, and only an operator or an administrator can press it. The confirmation of the step that a job waits for (change the tool, check the spindle) is made from the app.
- **The job in 2D and in an isometric view:** the board, the holes (a ring until they are drilled), the paths (dim until they are cut) and the head, where the steps done put it; the isometric view turns with a finger.
- **The drill head:** the camera of EH3D-NODE-BUNGARD-AUX as the server relays it, the turns and the temperature of the spindle, the protect output, and one measure of the table with the laser.
- **Jobs:** the list of the jobs of the server and of each machine, the start of a job that is ready (a job never starts by itself), its cancellation and its removal.
- **Sign-in:** the address of the server (only a private network address, `localhost` or https), the first administrator of a server that has none, the session kept sealed on the phone and an optional "remember me".
- **Eight languages and the Forge theme:** English, Spanish, German, French, Italian, Japanese, Chinese and European Portuguese, with a help and an about page; the same colours as the EH3D programs on the computer.
- **The rules in a Swift package:** `Eh3dCore` holds what does not need a phone (the readers of the server's JSON, the geometry, the address checks, the session, the languages) and is tested with `swift test`; the screens are built with Xcode.
- **The version of the release:** the app tells when a newer release of this project exists on GitHub and links to it; an iPhone app cannot update itself outside the App Store.
