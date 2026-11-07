# Changelog

All notable changes to this project are documented here.

## [Unreleased]

- **The camera says why it shows nothing,** as the Android app does: the HTTP status the server answered, "Video not available" or "No pictures are arriving" (texts that were already in the 37 tables) instead of three dots. Not run yet: there is no Xcode here.

## [0.0.9] - 37 languages, the person who started a job on its page and a text for every refusal of the server

- **37 languages:** the app speaks the 37 languages of the EH3D programs on the computer, in the same order: the eight it had (English, Spanish, Italian, German, French, European Portuguese, Chinese and Japanese) and Bulgarian, Croatian, Czech, Danish, Dutch, Estonian, Finnish, Greek, Hungarian, Irish, Latvian, Lithuanian, Maltese, Polish, Romanian, Slovak, Slovenian, Swedish, Norwegian, Icelandic, Ukrainian, Russian, Serbian, Albanian, Catalan, Galician, Basque, Brazilian Portuguese and Canadian French. Every text of the screens, the help and the refusals of the server is in all of them. The words of the 29 new languages are translated by the model and wait for a review by native speakers. Brazilian Portuguese and Canadian French hold only the phrases that differ from European Portuguese and French and take the rest from them; a phrase that a language does not have is shown in English. The list of languages scrolls, the language of the phone picks a variant by its region (`pt-BR`, `fr-CA`), and the tests and `tools/i18n_check.py` check that every table has every phrase, with the same holes and no blank or English-only text. None of the 37 is written right to left. The text the system shows when the app asks to reach the local network is translated into the 29 new languages too.
- **The page of a job says who started it** as well as who stopped it, with the text the machine page already uses.
- **Every refusal of the server has a text in every language of the app:** 31 more codes of the catalog of the server (the tuning, the G-code, the ids, the LED ring, the updates, the jobs and the machines among them) say what went wrong in the language of the app instead of the raw message; a test fails when a code of the catalog has neither a text nor a stated reason (the refusals of files that carry the message of the server, and the codes of the design programs the app never asks for).
- **The case files shared with the Android app are checked in CI:** `tools/check_shared_cases.py` compares them with the ones of the other repository (the sibling folder, or the public one on GitHub) and fails when one differs, is missing or cannot be read; its own test runs before it.
- **Brand:** Add the application icon and the logos of the program.
- **Shared checks updated:** the validator also compares the badge and the Version row of the README with the manifest, fails when one of its checks cannot run, and the CHANGELOG step of the workflow reads the base branch from the environment.
- **More tests:** the preparation of a job, the link, the stops, the drawing and the summary from their edges, the version numbers of releases, and the addresses an operator types.
- **A version number with a fraction or a digit of another script, or too big for an integer, is no longer read as a version;** an address with a port that does not exist is refused, and a duration that is not a number is written as nothing instead of stopping the app.
- **The workflows are hardened:** every action is pinned by its commit with its version in a comment, and the checkouts keep no credentials.
- **More tests of the address of the server:** the private ranges, the names that only look private, the leading zeros, the port and the secure connection.

## [0.0.8] - Summary before a start, an honest link and shared test cases

- **A summary before a job starts:** the dry run of the exact plan (how far each axis goes, the steps and the time) and the warnings of the server (a work that looks tiny, too big, far from the corner, stretched or past the course of an axis) are read, and Start shows what the job does, how long it takes, how far each axis goes and what looks wrong, with Start and Cancel; a setting turns it off (on by default) and then Start only asks once more. Not run yet: there is no Xcode here.
- **The refusal `outside_course` has its own clear text** in the eight languages (the plan takes an axis past its course; move the work on the table or let the machine's tuning warn).
- **The state of the connection is told honestly:** connected, data that is getting old (with its age after five seconds), no connection only after two failures in a row (one blink of the Wi-Fi no longer shows it), and an address that answers another service; the retries slow down from 1.5 s to 10 s while the server is away and a button tries again now.
- **Pressing the stop without a connection warns** that the order may not arrive and to use the physical stop of the machine; a stop that did not reach the server says so plainly, and after a stop that did, the app says it was sent, then confirmed or that the machine still works.
- **Case files shared with the other phone app:** the summary, the link, the failures, the stops, the notices, the addresses and the fields of the answers are tested from the same files in both apps, and a field that the server adds to its examples fails the test until the app reads it or says it ignores it.
- **A job says who started it and who stopped it:** the page of a job shows who stopped it (the server now sends both names).
- **Differences between the two phone apps are written down** in `docs/PLATFORM_DIFFERENCES.md`.
- **The jobs carry when they were made and when they ended** (read, as the Android app does), and what is told when a machine changes is one tested function (`fleetNotices`) instead of code inside the model of the screens. Not run yet: there is no Xcode here.

## [0.0.7] - Issue forms, examples of the server and a CI that builds the app

- **The answers of the server are read in the tests from its own examples:** the fleet, the jobs, a job, the preview, the spindle and an error are the files that the tests of the server make, so a change in the answers that the app does not follow fails here. Not run yet: there is no Xcode here.
- **The CI builds the app target:** besides the package tests, a job makes the Xcode project with XcodeGen, builds the app for the simulator without signing and checks that the built app shows the version and the build number of the project (`tools/check_ios_build.py`, which also runs on every push before the app is built).
- **Issue forms and a pull-request template:** the repository now has the bug report (it asks for the versions that `eh3d-updater --cli status --offline` lists), documentation, improvement and hardware validation forms (with the machine used) and the pull-request template of the suite.

## [0.0.6] - Starting a job asks once more, the emergency stop asks the server to stop the machine and the pin of the certificate is used

- **Starting a job from its page asks once more** (check that the machine is prepared and clear), as it does from Prepare, with the same words in every language; a touch by mistake no longer sets the machine going.
- **The emergency stop asks the server to stop the machine** (`POST /machines/:id/stop`) and the camera asks for a one-use ticket instead of putting the token of the session in the address. Not built or run yet: there is no Xcode here.

- **The pin of the certificate is used:** every request goes through a session whose delegate keeps the key of the server (or of its authority) the first time and refuses a certificate that does not match it afterwards, saying so in the eight languages. Not built or run yet: there is no Xcode here.
- The README says that notices work only while the app is in sight (iOS does not allow useful background polling and the server has no push channel).

- **Signing out closes the session on the server** (the call goes with the token that is being closed), and a slow refresh of another machine no longer paints its spindle or sensors on the page of this one.
- Clearer messages for a wrong setup code, a weak password and a bad name, in the eight languages.

## [0.0.5] - Resume a stopped job and the GRBL switch in read only

- **Go on from where a job stopped, with the file the server kept:** a job that failed or was cancelled (drilling, routing or G-code) has a button that asks the server (`resume-from`) for a new job made from the saved request, with the holes, paths or lines already done left out; the file is not picked again. The new job opens on its page, ready and never started, and says which job it goes on from. Messages for the new refusal `not_stopped` and for the new texts in the seven tables of languages (the same as the Android app). Written; Xcode was not run.
- **The switch of the `$` lines of GRBL, read only:** the page of a machine that takes G-code says whether the administrator allowed the `$` lines of GRBL (`$H` and the like) for that machine; it is changed in Studio. An older server that does not say is read as not allowed.
- 2 tests more (the job that can be gone on from and the switch), written and not run.

## [0.0.4] - Prepare a job, G-code jobs and the sensors of the drill head

- **Prepare job:** the same as the Android app: the page of a free machine has a Prepare job page. Choose what is done (drilling, routing, both or a free G-code program; a machine takes only what its connection allows), pick the file with the system file picker (the server has no list of files, so the text of the file is sent in the request that plans the job; an optional tool table can be picked too), and the server plans it without creating anything. The page lists the tools of the file in the order the job does them, with the count of holes or paths, the diameter when an Excellon file declares it and the spindle speed; switch tools off (`skip_tools`) or start at one tool (the ones before it in the order of the job are left out, as in BUNGARD-GUI); the spindle warnings of the plan are shown. Start asks for a confirmation, creates the job and starts it. With both, a drilling job and a routing job are created and the first starts; the second stays ready in the Jobs tab, because a job never starts by itself.
- **G-code jobs:** pick a G-code file and create a `gcode` job on a machine whose connection is the simulator or GRBL; the page shows the lines that will be sent, the area and the estimate. A running G-code job can be paused and resumed (the held wait and the wait after a stop both say what they are), cancelled, and a failed or stopped one can be continued from the line it reached (`skip` with the `line` of the job; the same program is prepared again, asking for the file when this session does not have it, and the machine waits for the confirmation before its first move). The spindle and the coolant are started again only with the switch "start the spindle and the coolant again", which is off by default.
- **Messages and help:** new messages for the refusals of the server when preparing a job (`bad_gcode`, `bad_ncd`, `unknown_tool`, `bad_tool`, `out_of_table`, `wrong_machine`, `too_big`, `not_pausable`, `not_in_state`), a help topic for the page and 53 phrases in the seven tables of languages.

## [0.0.3] - Spindle of the machine, tools switched off in a job and the sensors of the drill head

- **What the sensors of the drill head say:** the same as the Android app: the card of the head shows how the last reading of the laser went (valid, weak signal, too much spread, out of range, sensor fault) with the distance, how long ago it was taken and the offset the laser was calibrated with; whether the pulses of the speed sensor are clean or noisy and how many were refused as noise; how many temperature sensors the node found on the wire, with a warning when it only guesses which one to read; and the version of the node. A node that does not say (an older one) shows nothing of this. 17 phrases in the seven tables of languages. The settings of the image of the camera, the calibration of the laser and the choice of the temperature sensor stay in the panel of the node: the server does not hand them on yet.
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
