#!/usr/bin/env ruby
# 生成 Clipa.xcodeproj（macOS App）。新增源文件后重跑本脚本即可。
require 'xcodeproj'

ROOT = File.expand_path(File.dirname(__FILE__))
PROJ = File.join(ROOT, 'Clipa.xcodeproj')
SRC  = File.join(ROOT, 'Clipa')
LOCK = File.join(PROJ, 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved')
resolved_packages = File.binread(LOCK) if File.file?(LOCK)

File.delete(PROJ) if File.file?(PROJ)
require 'fileutils'
FileUtils.rm_rf(PROJ)

project = Xcodeproj::Project.new(PROJ)
project.root_object.known_regions = ['en', 'zh-Hans', 'Base']
project.root_object.development_region = 'en'
target = project.new_target(:application, 'Clipa', :osx, '14.0')

# 主分组
main_group = project.main_group.new_group('Clipa', 'Clipa')

# 递归添加 Swift 源文件，保持目录分组
Dir.glob(File.join(SRC, '**', '*.swift')).sort.each do |path|
  rel = path.sub(SRC + '/', '')
  parts = rel.split('/')
  group = main_group
  parts[0...-1].each do |dir|
    group = group.children.find { |c| c.display_name == dir && c.is_a?(Xcodeproj::Project::Object::PBXGroup) } || group.new_group(dir, dir)
  end
  ref = group.new_file(path)
  target.add_file_references([ref])
end

# 资源
assets = main_group.new_file(File.join(SRC, 'Resources/Assets.xcassets'))
target.add_resources([assets])

privacy = main_group.new_file(File.join(SRC, 'PrivacyInfo.xcprivacy'))
target.add_resources([privacy])

strings = main_group.new_file(File.join(SRC, 'Resources/Localizable.xcstrings'))
target.add_resources([strings])

# Preserve upstream notices in compiled apps as well as source distributions.
notices = project.main_group.new_group('Third-party notices')
([File.join(ROOT, 'THIRD_PARTY_NOTICES.md')] + Dir.glob(File.join(ROOT, 'docs/licenses/*.txt'))).each do |path|
  target.add_resources([notices.new_file(path)])
end

# Swift Package 依赖（归档服务需要）。保持依赖写进生成脚本，避免重生成项目时丢失。
[
  ['https://github.com/tsolomko/SWCompression', '4.8.0', 'SWCompression'],
  ['https://github.com/mtgto/Unrar.swift', '0.5.0', 'Unrar']
].each do |repository_url, minimum_version, product_name|
  package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  package.repositoryURL = repository_url
  package.requirement = {
    'kind' => 'upToNextMajorVersion',
    'minimumVersion' => minimum_version
  }
  project.root_object.package_references << package

  product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product.package = package
  product.product_name = product_name
  target.package_product_dependencies << product

  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product
  target.frameworks_build_phase.files << build_file
end

# Info.plist / entitlements 仅作引用（通过构建设置使用）
main_group.new_file(File.join(SRC, 'Info.plist'))
main_group.new_file(File.join(SRC, 'Clipa.entitlements'))

# 构建设置
target.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.hansen.clipa'
  s['PRODUCT_NAME'] = 'Clipa'
  s['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
  s['SWIFT_VERSION'] = '5.0'
  s['INFOPLIST_FILE'] = 'Clipa/Info.plist'
  s['CODE_SIGN_ENTITLEMENTS'] = 'Clipa/Clipa.entitlements'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['ENABLE_HARDENED_RUNTIME'] = 'YES'
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  s['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  # Contributors can build locally without the maintainer's signing account.
  # Distribution settings can be supplied with xcodebuild -xcconfig.
  s['CODE_SIGN_STYLE'] = 'Manual'
  s['DEVELOPMENT_TEAM'] = ''
  s['CODE_SIGN_IDENTITY'] = '-'
  s['CLIPA_STARTUP_STATS_URL'] = ''
  s['COMBINE_HIDPI_IMAGES'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../Frameworks']
  s['MARKETING_VERSION'] = '1.1.10'
  s['CURRENT_PROJECT_VERSION'] = '20261013'
end

project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.save_as(PROJ, 'Clipa', true)
if resolved_packages
  FileUtils.mkdir_p(File.dirname(LOCK))
  File.binwrite(LOCK, resolved_packages)
end
puts "已生成 #{PROJ}"
