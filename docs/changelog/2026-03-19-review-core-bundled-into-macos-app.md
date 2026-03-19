# 2026-03-19 — Review core Rust bundlizzato nell’app macOS

## Modifiche
- esteso [RustSearchFFIClient.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodebaseIndex/Indexing/RustSearchFFIClient.swift) per cercare `libsolocode_rust_core.dylib` anche dentro:
  - `Contents/MacOS/solocode_rust`
  - `Contents/Resources/solocode_rust`
- aggiornato [build_rust_search_backend.sh](/Users/benjaminstoica/SoloCode/scripts/build_rust_search_backend.sh) con il target opzionale `SOLOCODE_RUST_REVIEW_CORE_BUNDLE_DIR`
- aggiornati [build-app.sh](/Users/benjaminstoica/SoloCode/scripts/build-app.sh) e [run-app.sh](/Users/benjaminstoica/SoloCode/scripts/run-app.sh) per copiare il review core Rust nel bundle app
- esteso il generatore [generate_xcode_project.rb](/Users/benjaminstoica/SoloCode/scripts/generate_xcode_project.rb) con una shell phase `Build Rust Review Core`
- sincronizzato il progetto corrente [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) con la stessa build phase

## Comportamento
- l’app macOS lanciata da Xcode o dai wrapper di build/run ha ora il review core Rust disponibile nel proprio bundle
- il `CodeReviewPanel` non dipende più da un path repository-side o da env forzate per caricare la dylib

## Validazione eseguita
- `xcodebuild build -workspace "/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination "platform=macOS"`
- verifica bundle:
  - `Solo Code.app/Contents/MacOS/solocode_rust/libsolocode_rust_core.dylib`
- verifica simboli:
  - `review_core_version`
  - `review_core_panel_git_context`

## Note
- questa tranche chiude il gap fra test forzati via env e runtime reale dell’app
