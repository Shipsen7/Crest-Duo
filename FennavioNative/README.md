# Native application sources

This directory is the complete iPhone/iPad application. Build instructions,
security boundaries and device acceptance requirements are maintained in the
root README. `project.yml` creates `Fennavio.xcodeproj`; the only application
scheme is `FennavioNativePreview`.

`State/` contains Foundation-only validated models and storage, shared directly
with the dependency-free SwiftPM tests. `Browser/` owns system WebKit views,
UI, file export, protected temporary downloads and privacy presentation.
No old browser runtime, helper process or persistence container is used.
