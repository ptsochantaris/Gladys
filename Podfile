source 'https://github.com/CocoaPods/Specs.git'

inhibit_all_warnings!
use_modular_headers!

abstract_target 'iOS' do
  platform :ios, '13.0'
  use_frameworks! :linkage => :static

  target 'Gladys' do
    pod 'Fuzi'
    pod 'ZIPFoundation'
    pod 'CallbackURLKit'
    pod 'SwiftLint'
  end

  target 'GladysAction' do
    pod 'Fuzi'
  end

  target 'GladysIntents' do
    pod 'Fuzi'
  end
end

abstract_target 'macOS' do
  platform :osx, '10.13'
  use_frameworks! :linkage => :static

  target 'MacGladys' do
    pod 'Fuzi'
    pod 'HotKey'
    pod 'ZIPFoundation'
    pod 'CallbackURLKit'
    pod 'SwiftLint'
  end
end

post_install do |installer|
  installer.pods_project.build_configurations.each do |config|
    if config.name.include?("Release")
      config.build_settings['GCC_FAST_MATH'] = 'YES'
      config.build_settings['LLVM_LTO'] = 'YES'
      config.build_settings['SWIFT_DISABLE_SAFETY_CHECKS'] = 'YES'
      config.build_settings['ENABLE_BITCODE'] = 'NO'
      config.build_settings['SWIFT_ENFORCE_EXCLUSIVE_ACCESS'] = 'debug-only'
    end
  end
  
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings.delete('IPHONEOS_DEPLOYMENT_TARGET')
    end
  end
end
