#!/usr/bin/env ruby
require 'xcodeproj'

PROJECT_PATH = 'Porter.xcodeproj'
SPARKLE_URL  = 'https://github.com/sparkle-project/Sparkle'
SPARKLE_VERSION = '2.9.0'
SPARKLE_REF = "2.9.0"

proj = Xcodeproj::Project.open(PROJECT_PATH)
target = proj.targets.find { |t| t.name == 'Porter' }
raise "Target 'Porter' not found" unless target

# Add remote Swift package reference
pkg = proj.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
pkg.repositoryURL = SPARKLE_URL
pkg.requirement = {
  'kind'            => 'upToNextMajorVersion',
  'minimumVersion'  => SPARKLE_VERSION
}
proj.root_object.package_references << pkg

# Add product dependency (Sparkle) to target
dep = proj.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
dep.package = pkg
dep.product_name = 'Sparkle'
target.package_product_dependencies << dep

# Link Sparkle in Frameworks build phase
frameworks_phase = target.frameworks_build_phase
ref = proj.new(Xcodeproj::Project::Object::PBXBuildFile)
ref.product_ref = dep
frameworks_phase.files << ref

proj.save
puts "Sparkle #{SPARKLE_VERSION} added to Porter target successfully."
