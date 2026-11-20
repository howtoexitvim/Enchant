#!/usr/bin/env ruby
require 'xcodeproj'
require 'fileutils'
root = File.expand_path('..', __dir__)
Dir.chdir(root)
project = Xcodeproj::Project.new('Enchant.xcodeproj')
project.root_object.attributes['LastUpgradeCheck'] = '2630'
project.root_object.development_region = 'zh-Hans'
project.root_object.known_regions = ['zh-Hans', 'en']
phone = project.new_target(:application, 'Enchant', :ios, '17.0')
watch = project.new_target(:application, 'EnchantWatch', :watchos, '10.0')
units = project.new_target(:unit_test_bundle, 'EnchantTests', :ios, '17.0')
tests = project.new_target(:ui_test_bundle, 'EnchantUITests', :ios, '17.0')
shared = Dir['Sources/EnchantCore/*.swift'] + Dir['App/Shared/*.swift']
[phone, watch, tests, units].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['DEVELOPMENT_TEAM'] = ''
    config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
    config.build_settings['MARKETING_VERSION'] = '1.0'
    config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'YES'
    config.build_settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
    config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = config.name == 'Debug' ? 'DEBUG' : ''
    config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon' if [phone, watch].include?(target)
  end
end
cache = {}
ref = lambda { |path| cache[path] ||= project.main_group.new_file(path) }
phone.add_file_references((shared + Dir['App/iOS/*.swift']).map { |path| ref.call(path) })
watch.add_file_references((shared + Dir['App/Watch/*.swift']).map { |path| ref.call(path) })
tests.add_file_references(Dir['App/UITests/*.swift'].map { |path| ref.call(path) })
resources = Dir['App/Resources/*'].reject { |p| p.end_with?('Info.plist', 'entitlements') }
[phone, watch].each { |t| t.resources_build_phase.add_file_reference(ref.call('App/Resources/Assets.xcassets')); resources.reject { |p| p.end_with?('.xcassets') }.each { |p| t.resources_build_phase.add_file_reference(ref.call(p)) } }
phone.build_configurations.each do |c|
  c.build_settings.merge!('PRODUCT_BUNDLE_IDENTIFIER' => 'com.shuqi.enchant', 'INFOPLIST_FILE' => 'App/iOS/Info.plist', 'CODE_SIGN_ENTITLEMENTS' => 'App/iOS/Enchant.entitlements', 'TARGETED_DEVICE_FAMILY' => '1', 'SUPPORTS_MACCATALYST' => 'NO', 'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD' => 'NO')
end
watch.build_configurations.each do |c|
  c.build_settings.merge!('PRODUCT_BUNDLE_IDENTIFIER' => 'com.shuqi.enchant.watchkitapp', 'INFOPLIST_FILE' => 'App/Watch/Info.plist', 'CODE_SIGN_ENTITLEMENTS' => 'App/Watch/Enchant.entitlements', 'TARGETED_DEVICE_FAMILY' => '4', 'SKIP_INSTALL' => 'YES')
end
tests.build_configurations.each do |c|
  c.build_settings.merge!('PRODUCT_BUNDLE_IDENTIFIER' => 'com.shuqi.enchant.uitests', 'GENERATE_INFOPLIST_FILE' => 'YES', 'TEST_TARGET_NAME' => 'Enchant', 'TARGETED_DEVICE_FAMILY' => '1')
end
units.add_file_references(Dir['App/Tests/*.swift'].map { |path| ref.call(path) })
units.build_configurations.each do |c|
  c.build_settings.merge!('PRODUCT_BUNDLE_IDENTIFIER' => 'com.shuqi.enchant.tests', 'GENERATE_INFOPLIST_FILE' => 'YES', 'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/Enchant.app/Enchant', 'BUNDLE_LOADER' => '$(TEST_HOST)', 'TARGETED_DEVICE_FAMILY' => '1')
end
units.add_dependency(phone)
tests.add_dependency(phone)
phone.add_dependency(watch)
embed = phone.new_copy_files_build_phase('Embed Watch Content'); embed.dst_subfolder_spec = '16'; embed.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'
embed.add_file_reference(watch.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
project.save
scheme = Xcodeproj::XCScheme.new; scheme.add_build_target(phone); scheme.add_test_target(tests); scheme.add_test_target(units); scheme.set_launch_target(phone); scheme.save_as(project.path, 'Enchant', true)
watch_scheme = Xcodeproj::XCScheme.new; watch_scheme.add_build_target(watch); watch_scheme.set_launch_target(watch); watch_scheme.save_as(project.path, 'EnchantWatch', true)
puts 'Generated Enchant.xcodeproj (iPhone + Watch + UI tests)'
