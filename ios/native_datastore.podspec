Pod::Spec.new do |s|
  s.name             = 'native_datastore'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for persistent key-value storage using UserDefaults on iOS.'
  s.description      = <<-DESC
A modern Flutter plugin for persistent key-value storage.
Uses UserDefaults on iOS and Android Jetpack DataStore on Android.
                       DESC
  s.homepage         = 'https://sudhi.in'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Sudhi' => 'sudhi@sudhi.in' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.swift_version = '5.0'
end
