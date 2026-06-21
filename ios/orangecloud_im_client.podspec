Pod::Spec.new do |s|
  s.name             = 'orangecloud_im_client'
  s.version          = '2.0.0'
  s.summary          = 'OrangeCloud IM Flutter SDK (bridges native OrangeCloudIMClient binary).'
  s.description      = <<-DESC
OrangeCloud IM Flutter plugin. 核心逻辑由原生 OrangeCloudIMClient（XCFramework 二进制）实现，本插件仅做桥接。
                       DESC
  s.homepage         = 'https://github.com/OrangeCloud-SDK/orangecloud-im-flutter'
  s.license          = { :type => 'Commercial' }
  s.author           = { 'OrangeCloud' => 'sdk@orangecloud.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'

  # OrangeCloud IM iOS 核心 SDK（核心逻辑闭源于此二进制）
  s.dependency 'OrangeCloudIMClient', '~> 2.0.0'
  # 核心 SDK 的底层依赖
  s.dependency 'SwiftSignalRClient'

  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.9'
end
