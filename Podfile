source 'https://github.com/CocoaPods/Specs.git'

use_frameworks!
inhibit_all_warnings!

target 'Gladys' do
  platform :ios, '11.0'
  pod 'Fuzi'
  pod 'ZIPFoundation'
  pod 'CallbackURLKit'
end

target 'GladysAction' do
  platform :ios, '11.0'
  pod 'Fuzi'
end

target 'MacGladys' do
  platform :osx, '10.13'
  pod 'Fuzi'
  pod 'HotKey'
  pod 'ZIPFoundation'
  pod 'CallbackURLKit'
  pod 'CDEvents'
end

target 'GladysIntents' do
  platform :ios, '11.0'
  pod 'Fuzi'
end

target 'GladysFramework' do
  platform :ios, '11.0'
  pod 'OpenSSL-Universal'
end

target 'MacGladysFramework' do
  platform :osx, '10.13'
  pod 'OpenSSL-Universal'
end

post_install do |installer|
	installer.pods_project.build_configurations.each do |config|
		if config.name.include?("Release")
			config.build_settings['GCC_FAST_MATH'] = 'YES'
			config.build_settings['LLVM_LTO'] = 'YES'
			config.build_settings['SWIFT_DISABLE_SAFETY_CHECKS'] = 'YES'
			config.build_settings['SWIFT_ENFORCE_EXCLUSIVE_ACCESS'] = 'debug-only'
		end
	end
end
