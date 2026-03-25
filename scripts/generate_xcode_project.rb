#!/usr/bin/env ruby
require 'fileutils'
require 'json'
require 'securerandom'
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT_NAME = 'Solo Code'
PROJECT_PATH = File.join(ROOT, "#{PROJECT_NAME}.xcodeproj")
WORKSPACE_PATH = File.join(ROOT, "#{PROJECT_NAME}.xcworkspace")
TESTPLAN_PATH = File.join(ROOT, 'Config/TestPlans/Solo Code.xctestplan')

APP_TARGET = 'Solo Code'
ENGINE_TARGET = 'CoderEngine'
HELPER_FRAMEWORK_TARGET = 'CoderIDEMCPServer'
HELPER_EXECUTABLE_TARGET = 'CoderIDEMCPServerExecutable'
APP_TESTS = 'SoloCodeAppTests'
ENGINE_TESTS = 'CoderEngineTests'
INTEGRATION_TESTS = 'SoloCodeIntegrationTests'

# ---------------------------------------------------------------------------
# Synchronized folder helpers (Xcode 16+ PBXFileSystemSynchronizedRootGroup)
# ---------------------------------------------------------------------------

def add_synced_folder(project, parent_group, targets, relative_path)
  grp = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
  grp.path = relative_path
  grp.source_tree = '<group>'
  parent_group.children << grp
  Array(targets).each { |t| t.file_system_synchronized_groups << grp }
  grp
end

# ---------------------------------------------------------------------------
# Resource helpers (unchanged — resources are explicit, not synced)
# ---------------------------------------------------------------------------

def add_resources(project, group, target)
  %w[
    App/SoloCodeApp/Resources/Assets.xcassets
    App/SoloCodeApp/Resources/AppLogo.png
    App/SoloCodeApp/Resources/SoloCode.icns
    App/SoloCodeApp/Resources/browser-bridge.js
    App/SoloCodeApp/Resources/Fonts
    App/SoloCodeApp/Resources/monaco
  ].each do |rel|
    ref = group.find_file_by_path(rel) || group.new_file(rel)
    target.resources_build_phase.add_file_reference(ref, true)
  end
end

# ---------------------------------------------------------------------------
# Package helpers (unchanged)
# ---------------------------------------------------------------------------

def add_remote_package(project, url, minimum_version)
  ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  ref.repositoryURL = url
  ref.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => minimum_version }
  project.root_object.package_references << ref
  ref
end

def link_package_product(project, target, package_ref, product_name)
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package = package_ref
  dep.product_name = product_name
  target.package_product_dependencies << dep
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dep
  target.frameworks_build_phase.files << build_file
end

# ---------------------------------------------------------------------------
# Build configuration helpers (unchanged)
# ---------------------------------------------------------------------------

def assign_xcconfig(project, target, path)
  ref = project.files.find { |f| f.path == path } || project.main_group.new_file(path)
  target.build_configurations.each { |cfg| cfg.base_configuration_reference = ref }
end

def add_embed_frameworks_phase(project, target, frameworks)
  phase = target.new_copy_files_build_phase('Embed Frameworks')
  phase.dst_subfolder_spec = Xcodeproj::Constants::COPY_FILES_BUILD_PHASE_DESTINATIONS[:frameworks]
  frameworks.each do |framework_target|
    build = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    build.file_ref = framework_target.product_reference
    build.settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }
    phase.files << build
  end
end

# ---------------------------------------------------------------------------
# Scheme helpers (unchanged)
# ---------------------------------------------------------------------------

def add_test_bootstrap_pre_action(scheme, build_target)
  action = Xcodeproj::XCScheme::ExecutionAction.new(nil, :shell_script)
  content = Xcodeproj::XCScheme::ShellScriptActionContent.new
  content.title = 'Bootstrap Test Bundles'
  content.shell_to_invoke = '/bin/sh'
  content.script_text = <<~SH
    if [ -n "$SRCROOT" ] && [ -f "$SRCROOT/scripts/bootstrap_test_bundles.sh" ]; then
      "$SRCROOT/scripts/bootstrap_test_bundles.sh" "$BUILT_PRODUCTS_DIR"
    fi
  SH
  content.buildable_reference = Xcodeproj::XCScheme::BuildableReference.new(build_target)
  action.action_content = content
  scheme.test_action.add_pre_action(action)
end

# ---------------------------------------------------------------------------
# Build phase helpers (unchanged)
# ---------------------------------------------------------------------------

def add_rust_review_core_phase(target)
  phase = target.new_shell_script_build_phase('Build Rust Review Core')
  phase.shell_path = '/bin/sh'
  phase.shell_script = <<~SH
    if [ -n "$SRCROOT" ] && [ -f "$SRCROOT/scripts/build_rust_search_backend.sh" ]; then
      CONFIGURATION="${CONFIGURATION}" \
      SOLOCODE_RUST_REVIEW_CORE_BUNDLE_DIR="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Contents/MacOS/solocode_rust" \
        "$SRCROOT/scripts/build_rust_search_backend.sh"
    fi
  SH
  phase.show_env_vars_in_log = '0'
end

# ===========================================================================
# Project generation
# ===========================================================================

FileUtils.rm_rf(PROJECT_PATH)
FileUtils.rm_rf(WORKSPACE_PATH)
FileUtils.mkdir_p(File.dirname(TESTPLAN_PATH))

project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes['LastUpgradeCheck'] = '1600'

main = project.main_group
app_group = main.find_subpath('App', true)
engine_group = main.find_subpath('Engine', true)
tools_group = main.find_subpath('Tools', true)
tests_group = main.find_subpath('Tests', true)
config_group = main.find_subpath('Config', true)
scripts_group = main.find_subpath('Scripts', true)

# --- Targets ---------------------------------------------------------------

app_target = project.new_target(:application, APP_TARGET, :osx, '13.0')
engine_target = project.new_target(:framework, ENGINE_TARGET, :osx, '13.0')
helper_framework_target = project.new_target(:framework, HELPER_FRAMEWORK_TARGET, :osx, '13.0')
helper_executable_target = project.new_target(:command_line_tool, HELPER_EXECUTABLE_TARGET, :osx, '13.0')
app_tests_target = project.new_target(:unit_test_bundle, APP_TESTS, :osx, '13.0')
engine_tests_target = project.new_target(:unit_test_bundle, ENGINE_TESTS, :osx, '13.0')
integration_tests_target = project.new_target(:unit_test_bundle, INTEGRATION_TESTS, :osx, '13.0')

# --- xcconfig assignments --------------------------------------------------

assign_xcconfig(project, app_target, 'Config/xcconfigs/App.xcconfig')
assign_xcconfig(project, engine_target, 'Config/xcconfigs/Framework.xcconfig')
assign_xcconfig(project, helper_framework_target, 'Config/xcconfigs/Framework.xcconfig')
assign_xcconfig(project, helper_executable_target, 'Config/xcconfigs/Tool.xcconfig')
[app_tests_target, engine_tests_target, integration_tests_target].each do |target|
  assign_xcconfig(project, target, 'Config/xcconfigs/Tests.xcconfig')
end

# --- Per-target build settings ----------------------------------------------

app_tests_target.build_configurations.each do |cfg|
  cfg.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.solocode.tests.app'
  cfg.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Solo Code.app/Contents/MacOS/Solo Code'
end
integration_tests_target.build_configurations.each do |cfg|
  cfg.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.solocode.tests.integration'
  cfg.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Solo Code.app/Contents/MacOS/Solo Code'
end
engine_tests_target.build_configurations.each do |cfg|
  cfg.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.solocode.tests.engine'
end
helper_framework_target.build_configurations.each do |cfg|
  cfg.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.solocode.coderidemcpserver.framework'
  cfg.build_settings['PRODUCT_NAME'] = 'CoderIDEMCPServer'
  cfg.build_settings['PRODUCT_MODULE_NAME'] = 'CoderIDEMCPServer'
end
helper_executable_target.build_configurations.each do |cfg|
  cfg.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.solocode.coderidemcpserver'
  cfg.build_settings['PRODUCT_NAME'] = 'coderide-mcp-server'
  cfg.build_settings['PRODUCT_MODULE_NAME'] = 'CoderIDEMCPServerExecutable'
  cfg.build_settings['EXECUTABLE_NAME'] = 'coderide-mcp-server'
end

# --- Synchronized source folders (Xcode 16+) -------------------------------
# Instead of enumerating every .swift file individually (PBXBuildFile),
# we point each target at its source folder. Xcode syncs automatically.

add_synced_folder(project, app_group, app_target,
                  'App/SoloCodeApp/Sources')
add_synced_folder(project, engine_group, engine_target,
                  'Engine/CoderEngine/Sources')
# Both framework and executable compile the shared MCP server sources
add_synced_folder(project, tools_group, [helper_framework_target, helper_executable_target],
                  'Tools/CoderIDEMCPServer/Sources')
add_synced_folder(project, tools_group, helper_executable_target,
                  'Tools/CoderIDEMCPServerExecutable/Sources')
add_synced_folder(project, tests_group, app_tests_target,
                  'Tests/SoloCodeAppTests')
add_synced_folder(project, tests_group, engine_tests_target,
                  'Tests/CoderEngineTests')
add_synced_folder(project, tests_group, integration_tests_target,
                  'Tests/SoloCodeIntegrationTests')

# --- Resources (explicit, not synced) ---------------------------------------

add_resources(project, app_group, app_target)

# --- SPM packages -----------------------------------------------------------

swift_term_pkg = add_remote_package(project, 'https://github.com/migueldeicaza/SwiftTerm.git', '1.2.0')
mcp_pkg = add_remote_package(project, 'https://github.com/modelcontextprotocol/swift-sdk.git', '0.10.0')
logging_pkg = add_remote_package(project, 'https://github.com/apple/swift-log.git', '1.10.1')
link_package_product(project, app_target, swift_term_pkg, 'SwiftTerm')
link_package_product(project, engine_target, mcp_pkg, 'MCP')
link_package_product(project, helper_framework_target, mcp_pkg, 'MCP')
link_package_product(project, helper_executable_target, mcp_pkg, 'MCP')
link_package_product(project, engine_target, logging_pkg, 'Logging')
link_package_product(project, engine_tests_target, mcp_pkg, 'MCP')

# --- Target dependencies & framework linking --------------------------------

app_target.add_dependency(engine_target)
app_target.frameworks_build_phase.add_file_reference(engine_target.product_reference, true)
app_target.add_dependency(helper_framework_target)
app_target.add_dependency(helper_executable_target)
helper_framework_target.add_dependency(engine_target)
helper_framework_target.frameworks_build_phase.add_file_reference(engine_target.product_reference, true)
helper_executable_target.add_dependency(engine_target)
helper_executable_target.frameworks_build_phase.add_file_reference(engine_target.product_reference, true)
helper_executable_target.add_dependency(helper_framework_target)
helper_executable_target.frameworks_build_phase.add_file_reference(helper_framework_target.product_reference, true)
app_tests_target.add_dependency(app_target)
engine_tests_target.add_dependency(engine_target)
engine_tests_target.add_dependency(helper_framework_target)
integration_tests_target.add_dependency(app_target)
integration_tests_target.add_dependency(engine_target)
engine_tests_target.frameworks_build_phase.add_file_reference(engine_target.product_reference, true)
engine_tests_target.frameworks_build_phase.add_file_reference(helper_framework_target.product_reference, true)

# --- Embed phases -----------------------------------------------------------

add_embed_frameworks_phase(project, app_target, [engine_target, helper_framework_target])
add_embed_frameworks_phase(project, engine_tests_target, [engine_target, helper_framework_target])
add_rust_review_core_phase(app_target)

embed_helper = app_target.new_copy_files_build_phase('Embed Helper')
embed_helper.dst_subfolder_spec = Xcodeproj::Constants::COPY_FILES_BUILD_PHASE_DESTINATIONS[:executables]
helper_build = project.new(Xcodeproj::Project::Object::PBXBuildFile)
helper_build.file_ref = helper_executable_target.product_reference
embed_helper.files << helper_build

# --- Schemes ----------------------------------------------------------------

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app_target, app_tests_target, launch_target: true)
scheme.add_build_target(engine_tests_target, false)
scheme.add_build_target(integration_tests_target, false)
scheme.add_test_target(engine_tests_target)
scheme.add_test_target(integration_tests_target)
add_test_bootstrap_pre_action(scheme, app_target)
scheme.save_as(PROJECT_PATH, 'Solo Code-Debug', true)

engine_test_scheme = Xcodeproj::XCScheme.new
engine_test_scheme.configure_with_targets(engine_target, engine_tests_target, launch_target: false)
engine_test_scheme.add_build_target(helper_framework_target, false)
add_test_bootstrap_pre_action(engine_test_scheme, engine_target)
engine_test_scheme.save_as(PROJECT_PATH, 'CoderEngineTests-Debug', true)

release_scheme = Xcodeproj::XCScheme.new
release_scheme.configure_with_targets(app_target, nil, launch_target: true)
release_scheme.save_as(PROJECT_PATH, 'Solo Code-Release', true)

integration_scheme = Xcodeproj::XCScheme.new
integration_scheme.configure_with_targets(app_target, integration_tests_target, launch_target: true)
add_test_bootstrap_pre_action(integration_scheme, app_target)
integration_scheme.save_as(PROJECT_PATH, 'Solo Code-IntegrationTests', true)

# --- Workspace --------------------------------------------------------------

FileUtils.mkdir_p(WORKSPACE_PATH)
File.write(File.join(WORKSPACE_PATH, 'contents.xcworkspacedata'), <<~XML)
  <?xml version="1.0" encoding="UTF-8"?>
  <Workspace version = "1.0">
    <FileRef location = "group:#{PROJECT_NAME}.xcodeproj"></FileRef>
  </Workspace>
XML

# --- Test plan --------------------------------------------------------------

test_plan = {
  'configurations' => [{ 'id' => SecureRandom.uuid.upcase, 'name' => 'Default', 'options' => {} }],
  'defaultOptions' => { 'codeCoverage' => true },
  'testTargets' => [
    app_tests_target,
    engine_tests_target,
    integration_tests_target,
  ].map do |target|
    { 'target' => { 'containerPath' => "container:#{PROJECT_NAME}.xcodeproj", 'identifier' => target.uuid, 'name' => target.name } }
  end,
  'version' => 1,
}
File.write(TESTPLAN_PATH, JSON.pretty_generate(test_plan))

# --- Save & patch objectVersion ---------------------------------------------

project.save

# Patch objectVersion to 77 (required for PBXFileSystemSynchronizedRootGroup)
pbxproj_path = File.join(PROJECT_PATH, 'project.pbxproj')
content = File.read(pbxproj_path)
content.sub!(/objectVersion = \d+;/, 'objectVersion = 77;')
File.write(pbxproj_path, content)

puts "Generated #{PROJECT_NAME}.xcodeproj with Xcode 16 synchronized folders"
puts "  objectVersion: 77"
puts "  pbxproj lines: #{content.lines.count}"
