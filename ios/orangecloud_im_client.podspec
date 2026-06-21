Pod::Spec.new do |s|
  s.name             = 'orangecloud_im_client'
  s.version          = '2.0.0'
  s.summary          = 'OrangeCloud IM Flutter SDK (bridges native OrangeCloudIMClient binary).'
  s.description      = <<-DESC
OrangeCloud IM Flutter plugin. 核心逻辑由原生 OrangeCloudIMClient（XCFramework 二进制，随 plugin 自带）实现，本插件仅做桥接。
                       DESC
  s.homepage         = 'https://github.com/OrangeCloud-SDK-IM/orangecloud-im-flutter'
  s.license          = { :type => 'Commercial' }
  s.author           = { 'OrangeCloud' => 'sdk@orangecloud.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'

  # OrangeCloud IM iOS 核心 SDK（随 plugin 自带的 XCFramework 二进制，核心逻辑闭源于此）
  s.vendored_frameworks = 'OrangeCloudIMClient.xcframework'
  # 核心二进制的底层依赖（CocoaPods 上的 SignalR Swift 客户端）
  s.dependency 'SwiftSignalRClient'

  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.9'
end
