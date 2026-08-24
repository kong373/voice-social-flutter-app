Pod::Spec.new do |s|
  s.name             = 'first_party_native_permissions'
  s.version          = '0.1.0'
  s.summary          = 'First-party OS permission bridge.'
  s.description      = 'Native microphone, notification, and photo permission status for the app.'
  s.homepage         = 'https://example.invalid/voice-social-app'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Voice Social App' => 'mobile@example.invalid' }
  s.source           = { :path => '.' }
  s.source_files     = 'first_party_native_permissions/Sources/first_party_native_permissions/**/*'
  s.dependency       'Flutter'
  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
end
