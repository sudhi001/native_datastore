Pod::Spec.new do |s|
  s.name             = 'native_datastore'
  s.version          = '1.5.3'
  s.summary          = 'Flutter plugin for persistent key-value storage using UserDefaults on iOS.'
  s.description      = <<-DESC
A modern Flutter plugin for persistent key-value storage.
Uses UserDefaults on iOS and Android Jetpack DataStore on Android.
                       DESC
  s.homepage         = 'https://sudhi.in'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'Sudhi' => 'sudhi@sudhi.in' }
  s.source           = { :path => '.' }
  s.source_files     = 'native_datastore/Sources/native_datastore/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # The plugin reads and writes UserDefaults on iOS, a required-reason API.
  # PrivacyInfo.xcprivacy declares that use for App Store submission.
  s.resource_bundles = {'native_datastore_privacy' => ['native_datastore/Sources/native_datastore/PrivacyInfo.xcprivacy']}
end
