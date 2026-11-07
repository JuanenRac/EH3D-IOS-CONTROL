# Differences between the iPhone and the Android app

This app is a port of the Android app (EH3D-ANDROID-CONTROL): whatever one app learns, the other learns too. This page lists what the two systems make different, so a difference is a decision and not a slip.

## What is the same

* The rules live in plain code with no screen in it: the summary before a job starts (`Summary.swift`), the state of the link (`ServerLink.swift`), what became of a stop (`Stop.swift`) and what is told when a machine changes (`fleetNotices`). They are in `Sources/Eh3dCore`; the Android app has the same rules in its `model` folder.
* Both apps walk the same case files (`Tests/Eh3dCoreTests/Cases` here, `app/src/test/resources/shared-cases` there): the summary, the link, the failures, the stops, the notices, the addresses and the fields of the answers that are read. The files are identical in both repositories; when one changes, copy it to the other.
* The test of the fields fails when an example of the server carries a field that the app neither reads nor lists as ignored, and when a field listed as read is nowhere in the code.
* The texts are the same Spanish phrases in the same tables of 37 languages (36 files: Spanish is the source and has none) (`Sources/Eh3dCore/Resources/i18n` here, `app/src/main/assets/i18n` there).

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
| Updates | Tells that a version exists and links to it | Downloads the APK and hands it to the installer |
| Certificate of a secure server | Pinned the first time it is seen; one extra phrase in the 37 tables says so | Not pinned; the phrase is not in its tables |
| The stream of the head camera | The camera is read with `URLSession` and stops with its screen | Also stops while the app is out of sight and can decode at a smaller size for the grid |

## Not there in either app yet

* Jog (moving an axis by hand) and a live progress stream of a job: the server has no route for jog and sends progress only in the job (`percent`, `items_done`, `holes_done`, `estimate_s`), which both apps already show; they will follow when the server offers the route.

## Not run yet

The Swift tests and the screens of the iPhone app were written without a Mac: the first run is the CI of this repository.
