Pod::Spec.new do |s|
  s.name = 'first_party_room_audio'
  s.version = '0.1.0'
  s.summary = 'First-party bounded room audio lifecycle observation.'
  s.description = 'Observes SDK-owned audio session configuration without taking ownership.'
  s.homepage = 'https://example.invalid/voice-social-app'
  s.license = { :type => 'Proprietary' }
  s.author = { 'Voice Social App' => 'mobile@example.invalid' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
  s.frameworks = 'AVFoundation', 'UIKit'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
