# Changelog

All notable changes to this project are documented here.

## [Unreleased]

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
