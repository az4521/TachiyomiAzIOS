# TachiyomiAZRunner

This is TachiyomiAZ's in-repository source-model and runner-protocol module.
Its product keeps the module name `AidokuRunner` so the GPL Aidoku application
code does not need a risky mass rename.

It is not the source-available AidokuRunner project and does not contain that
project's interpreter, source loader, Wasm3 integration, or implementation
code. AIX/WASM construction fails explicitly. Online sources on iOS are
implemented by TachiyomiAZ's JVM extension host.
