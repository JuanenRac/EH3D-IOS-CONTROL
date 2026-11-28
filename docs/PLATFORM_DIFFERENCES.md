# Differences between the iPhone and the Android app

This app is a port of the Android app (EH3D-ANDROID-CONTROL): whatever one app learns, the other learns too. This page lists what the two systems make different, so a difference is a decision and not a slip.

## What is the same

* The rules live in plain code with no screen in it: the summary before a job starts (`Summary.swift`), the state of the link (`ServerLink.swift`), what became of a stop (`Stop.swift`) and what is told when a machine changes (`fleetNotices`). They are in `Sources/Eh3dCore`; the Android app has the same rules in its `model` folder.
* Both apps walk the same case files (`Tests/Eh3dCoreTests/Cases` here, `app/src/test/resources/shared-cases` there): the summary, the link, the failures, the stops, the notices, the addresses and the fields of the answers that are read. The files are identical in both repositories; when one changes, copy it to the other.
* The test of the fields fails when an example of the server carries a field that the app neither reads nor lists as ignored, and when a field listed as read is nowhere in the code.
* The rules of the connection are the same (`Connection.swift` here, `Connection.kt` there): the settings and their ranges (time-out 1 to 120 s, retries 0 to 5, the search off), the pauses of 200 ms up to 2 s, which requests may be sent again, the renewal of the login in the last quarter of its life, the logins that the server lists, the machines of the plugins with their detail flattened to at most 24 lines, and the candidates found on the network (8 at most).
* The text of every refusal code of the server is the same table in eight languages (`Sources/Eh3dCore/Resources/server-errors.json` here, `app/src/main/assets/server-errors.json` there), written by the same `tools/gen_server_errors.py` from the catalog of the server; the other 29 languages show the English text.
* The safety of the machines of the plugins is the same logic in both apps (`Sources/Eh3dCore/WorkSafety.swift` here, `model/WorkSafety.kt` there): the SIMULATOR ONLY badge, the interlocks, who may stop, release, start and cancel, the queue of a machine and the switches of the server. Nothing in them depends on the system.
* The page of the settings of the server is the same in both apps: it is drawn from the same copy of the contract of the server (`Sources/Eh3dCore/Resources/settings-contract.json` here, `app/src/main/assets/settings-contract.json` there), with the same sentences in the same table of eight languages (`settings-texts.json`; the other 29 languages read the English text) and the same rules (`SettingsContract.swift` here, `model/SettingsContract.kt` there): the 16 groups, the control of each type, the range checked before sending, the default that can be restored, the second touch for a risky key and for a value looser than recommended, a secret that is never shown, the 19 keys written by `PUT /auth/policy` and the 76 that are only shown. `tools/sync_settings_contract.py --check` keeps the copy true to the server, and `tools/check_app_parity.py` fails when the two apps differ.
* The 3D printers the server watches are read the same way in both apps (`model/Printers.kt` on Android, `Sources/Eh3dCore/Printers.swift` on the iPhone) and walk the same file of cases (`printer_cases.json`): read only, with `GET /printers` each time the home page is refreshed; what a printer did not say is unknown, never zero; a list that is switched off (501), missing (404) or not allowed (403) shows nothing; a server that does not answer keeps the last list, marked as old; the access code, the address and the serial number are never read.
* The texts are the same Spanish phrases in the same tables of the eight languages (7 files: Spanish is the source and has none) (`Sources/Eh3dCore/Resources/i18n` here, `app/src/main/assets/i18n` there).
* The authorization of a job of the generic queue works the same in both apps: each job of a machine shows the first twelve characters of its `toolpath_sha256` with a badge (not authorized, authorized, expired when the authorized hash is not the present one); the button *Authorize* (an operator, a job that waits, scope `jobs:authorize` checked by the server) asks a second time and then sends `POST /work/jobs/{id}/authorize` with the hash that was shown; the start asks twice and sends the same hash. A `stale_authorization` or `authorization_required` makes the app read the queue again, so the job is shown with its present hash and has to be authorized again.

## What the system makes different

| Subject | iPhone | Android |
|---|---|---|
| The summary before a job starts | A sheet | A dialog |
| The warning in the question of a stop when there is no connection | Added to the text of the dialog (the system does not colour it) | In red |
| The clock of the link and of the stops | `DispatchTime.now().uptimeNanoseconds` | `SystemClock.elapsedRealtime` |
| Where the setting of the summary is kept | The preference store of the app | `SharedPreferences` |
| Notices with the app closed | Only while the app is in sight | A periodic job (WorkManager, every 15 minutes at best) |
| An address with a path after the host (`http://192.168.0.5:8080/x`) | The address is refused | The path is dropped |
| Two addresses for one installation (at home and away) | `DualEndpoint` | Not there |
| The search for the server on the local network (`_eh3d._tcp`, off by default) | Bonjour (`NWBrowser`, `ServerDiscovery.swift`) needs the permission of the local network (`NSLocalNetworkUsageDescription`, with the service in `NSBonjourServices`); IPv4 addresses only, 8 seconds, 8 candidates at most; the person chooses what it found; written without a Mac and to be tried on an iPhone | `NsdManager` (`ServerDiscovery.kt`), the same limits |
| The clock of the renewal of the login and of the pauses between tries | `DispatchTime.now().uptimeNanoseconds` and `Task.sleep` | `System.currentTimeMillis` and `delay` |
| What counts as a connection that was never made (a POST may then be sent again) | `URLError` codes `cannotFindHost`, `cannotConnectToHost`, `dnsLookupFailed` and `notConnectedToInternet` | The failure of `connect()` before anything is written |
| The second touch before a release, a start or a cancel in the queue of a machine of a plugin | A confirmation dialog from the bottom of the screen | A dialog in the middle of the screen |
| A temperature that ends in exactly half a degree (`24.5`) shown in whole degrees | Rounded to the even degree by the system (`24`) | Rounded up (`25`) |
| The second touch before a risky change of a setting of the server | A confirmation dialog from the bottom of the screen | A dialog in the middle of the screen |
| The control of a number or a text in the page of the settings | A text field with the numeric keyboard and a Save button | The same, with the number keyboard of Android |
| The choice of an enumerated setting | Buttons in a row that scrolls | Chips in a row that scrolls |
| Updates | Tells that a version exists and links to it | Downloads the APK and hands it to the installer |
| Certificate of a secure server | Pinned the first time it is seen; one extra phrase in the 7 tables says so | Not pinned; the phrase is not in its tables |
| The stream of the head camera | The camera is read with `URLSession` and stops with its screen | Also stops while the app is out of sight and can decode at a smaller size for the grid |
| Notices through the push service of the system | Not there: it needs a key of a paid Apple developer account | Firebase, off by default, in a build with the owner's project; five phrases only that app has |
| Listening while a job runs (off by default) | Not there: the system does not let an app go on asking in the background | A foreground service asks the server every few seconds and stops by itself |

## Not there in either app yet

* Anything about the 3D printers but reading them: registering, changing and removing them is done on the server, nothing can be sent to a printer, there is no notice when a print finishes or fails, and the list is not updated by the `printer` event of the websocket.
* Registering, changing and removing the nodes of the pick-and-place machines, asking a node now, and the update of the list by the `pnp_node` event of the websocket: the apps only read `GET /pnp/nodes` (read only, no token) each time the home page is refreshed, and show nothing while the server has the nodes switched off.
* A stop of a machine of a plugin that the server refused because the session had ended is not sent again after signing in (the stops of the drilling and routing machines are): the person is told at once that it did not arrive and to use the physical stop.
* Jog (moving an axis by hand) and a live progress stream of a job: the server has no route for jog and sends progress only in the job (`percent`, `items_done`, `holes_done`, `estimate_s`), which both apps already show; they will follow when the server offers the route.

## Not run yet

The Swift tests and the screens of the iPhone app were written without a Mac: the first run is the CI of this repository.
